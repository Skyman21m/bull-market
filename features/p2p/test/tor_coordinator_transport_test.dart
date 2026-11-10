import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bull_tor/tor.dart';
import 'package:p2p/src/data/tor_coordinator_transport.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:socks5_proxy/enums.dart';
import 'package:socks5_proxy/exceptions.dart';
import 'package:test/test.dart';

/// The Tor side, faked: each session gets its own endpoint, and the tests see which sessions were opened and closed.
final class _Sessions {
  final List<TorSession> opened = [];
  final Set<int> closed = {};

  Future<TorSession> open() async {
    final index = opened.length;
    final session = TorSession(
      TorProxyEndpoint(host: '127.0.0.1', port: 9000 + index),
      TorTransport.direct,
      () async => closed.add(index),
    );
    opened.add(session);
    return session;
  }

  /// The index of the session that owns [endpoint].
  static int indexOf(TorProxyEndpoint endpoint) => endpoint.port - 9000;
}

/// A coordinator on the loopback interface: one handler per path, and what it received.
final class _Server {
  final HttpServer _server;
  final Map<String, Future<void> Function(HttpRequest)> _routes;
  final List<HttpHeaders> received = [];

  _Server._(this._server, this._routes);

  static Future<_Server> start(
    Map<String, Future<void> Function(HttpRequest)> routes,
  ) async {
    final server = _Server._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      routes,
    );
    server._server.listen((request) {
      server.received.add(request.headers);
      final route = server._routes[request.uri.path];
      if (route == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close().ignore();
        return;
      }
      route(request).catchError((Object _) {});
    });
    return server;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> close() => _server.close(force: true);
}

/// Answers with [body] as JSON, with a `Content-Length`.
Future<void> Function(HttpRequest) _json(String body) => (request) async {
  final bytes = utf8.encode(body);
  request.response
    ..headers.contentType = ContentType.json
    ..contentLength = bytes.length
    ..add(bytes);
  await request.response.close();
};

/// Answers with [length] bytes sent in chunks, without a `Content-Length`.
Future<void> Function(HttpRequest) _chunked(int length) => (request) async {
  request.response.headers.contentType = ContentType.json;
  var left = length;
  while (left > 0) {
    final size = left < 1000 ? left : 1000;
    request.response.add(Uint8List(size));
    left -= size;
    await request.response.flush();
  }
  await request.response.close();
};

CoordinatorRequest _get(
  Uri url, {
  int maxResponseBytes = 4096,
  Map<String, String> headers = const {'Accept': 'application/json'},
}) => CoordinatorRequest(
  method: CoordinatorHttpMethod.get,
  url: url,
  headers: headers,
  maxResponseBytes: maxResponseBytes,
);

/// An HTTP client whose SOCKS proxy refuses every connection with [code], as Tor does when it cannot reach an onion service.
HttpClient _socksRefusal(CommandReplyCode code) =>
    HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) async =>
          throw SocksClientConnectionCommandFailedException(code);

/// Sends the requests of a [CoordinatorClient] to [server], whatever coordinator they are for.
final class _ToServer implements CoordinatorTransport {
  final CoordinatorTransport _inner;
  final _Server _server;

  _ToServer(this._inner, this._server);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) => _inner.send(
    CoordinatorRequest(
      method: request.method,
      url: _server.url(request.url.path),
      headers: request.headers,
      maxResponseBytes: request.maxResponseBytes,
      body: request.body,
    ),
  );
}

void main() {
  late _Sessions sessions;
  final servers = <_Server>[];
  final transports = <TorCoordinatorTransport>[];

  setUp(() => sessions = _Sessions());

  tearDown(() async {
    for (final transport in transports) {
      await transport.closeSessions();
    }
    transports.clear();
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
  });

  Future<_Server> serve(
    Map<String, Future<void> Function(HttpRequest)> routes,
  ) async {
    final server = await _Server.start(routes);
    servers.add(server);
    return server;
  }

  TorCoordinatorTransport transport({
    Duration deadline = const Duration(seconds: 5),
    HttpClient Function(TorProxyEndpoint endpoint)? createHttpClient,
    Future<TorSession> Function()? openSession,
  }) {
    final transport = TorCoordinatorTransport.withSeams(
      openSession: openSession ?? sessions.open,
      createHttpClient: createHttpClient ?? (_) => HttpClient(),
      deadline: deadline,
      attemptTimeout: const Duration(seconds: 10),
    );
    transports.add(transport);
    return transport;
  }

  group('answers', () {
    test('gives the status, the body and lowercase header names', () async {
      final server = await serve({
        '/api/info/': (request) async {
          request.response
            ..headers.contentType = ContentType.json
            ..headers.set('X-Mixed-Case', 'kept', preserveHeaderCase: true)
            ..write('{"ok":true}');
          await request.response.close();
        },
      });

      final result = await transport().send(_get(server.url('/api/info/')));

      final response = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('unexpected $failure'),
      };
      expect(response.statusCode, 200);
      expect(String.fromCharCodes(response.body), '{"ok":true}');
      expect(response.contentType, startsWith('application/json'));
      expect(response.headers['x-mixed-case'], 'kept');
      for (final name in response.headers.keys) {
        expect(name, name.toLowerCase());
      }
    });

    test('sends no User-Agent and no Accept-Encoding header', () async {
      final server = await serve({'/api/info/': _json('{}')});

      await transport().send(
        _get(
          server.url('/api/info/'),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'should never be sent',
          },
        ),
      );

      final headers = server.received.single;
      expect(headers.value(HttpHeaders.userAgentHeader), isNull);
      expect(headers.value(HttpHeaders.acceptEncodingHeader), isNull);
      expect(headers.value(HttpHeaders.acceptHeader), 'application/json');
    });

    test('returns a redirect as it is, without following it', () async {
      var followed = 0;
      final server = await serve({
        '/api/info/': (request) async {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/elsewhere/');
          await request.response.close();
        },
        '/api/book/': (request) async {
          request.response
            ..statusCode = HttpStatus.movedPermanently
            ..headers.set(HttpHeaders.locationHeader, '/elsewhere/');
          await request.response.close();
        },
        '/elsewhere/': (request) async {
          followed++;
          await _json('{}')(request);
        },
      });
      final tor = transport();

      for (final (path, status) in [('/api/info/', 302), ('/api/book/', 301)]) {
        final result = await tor.send(_get(server.url(path)));
        expect(
          result,
          isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>().having(
            (ok) => ok.value.statusCode,
            'statusCode',
            status,
          ),
        );
      }
      expect(followed, 0);
    });

    test('lets the coordinator client reject a redirect', () async {
      final server = await serve({
        '/api/info/': (request) async {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/api/info/x/');
          await request.response.close();
        },
      });
      final client = CoordinatorClient(_ToServer(transport(), server));

      final result = await client.fetchInfo(
        Federation.robosats.coordinators.first,
        RobosatsNetwork.mainnet,
      );

      expect(
        result,
        isA<Err<CoordinatorInfo, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorUnexpectedStatus>().having(
            (failure) => failure.statusCode,
            'statusCode',
            302,
          ),
        ),
      );
    });

    test('reuses one session per origin, even for concurrent requests', () async {
      final first = await serve({'/api/info/': _json('{}')});
      final second = await serve({'/api/info/': _json('{}')});
      final tor = transport();

      final results = await Future.wait([
        tor.send(_get(first.url('/api/info/'))),
        tor.send(_get(first.url('/api/info/'))),
        tor.send(_get(first.url('/api/info/'))),
      ]);
      await tor.send(_get(first.url('/api/info/')));
      await tor.send(_get(second.url('/api/info/')));

      expect(results, everyElement(isA<Ok<Object?, Failure>>()));
      expect(sessions.opened, hasLength(2));
      expect(sessions.closed, isEmpty);
    });
  });

  group('size cap', () {
    test('accepts a body of exactly the cap', () async {
      final server = await serve({'/api/book/': _chunked(4096)});

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 4096),
      );

      expect(
        result,
        isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>().having(
          (ok) => ok.value.body.length,
          'body length',
          4096,
        ),
      );
    });

    test('refuses a body announced larger than the cap', () async {
      final server = await serve({'/api/book/': _json('x' * 4097)});

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 4096),
      );

      expect(result, _failsWith<CoordinatorResponseTooLarge>());
    });

    test('stops reading a chunked body one byte over the cap', () async {
      final server = await serve({'/api/book/': _chunked(4097)});

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 4096),
      );

      expect(result, _failsWith<CoordinatorResponseTooLarge>());
    });

    test('stops reading a body that never ends and drops the connection', () async {
      final serverStopped = Completer<int>();
      final server = await serve({
        '/api/book/': (request) async {
          request.response.headers.contentType = ContentType.json;
          final chunk = Uint8List(16 * 1024);
          var sent = 0;
          try {
            // Bounded only so that a broken transport fails this test instead of filling the memory.
            while (sent < 256 * 1024 * 1024) {
              request.response.add(chunk);
              await request.response.flush();
              sent += chunk.length;
            }
          } on Object {
            // The client went away: what this test waits for.
          }
          serverStopped.complete(sent);
        },
      });
      final watch = Stopwatch()..start();

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 64 * 1024),
      );

      expect(result, _failsWith<CoordinatorResponseTooLarge>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      // The server notices the closed connection: the client really stopped reading.
      final sent = await serverStopped.future.timeout(
        const Duration(seconds: 10),
      );
      expect(sent, lessThan(256 * 1024 * 1024));
    });
  });

  group('deadline', () {
    test('cuts a body sent a byte at a time', () async {
      final server = await serve({
        '/api/book/': (request) async {
          request.response
            ..headers.contentType = ContentType.json
            ..contentLength = 1000;
          for (var i = 0; i < 1000; i++) {
            request.response.add(const [0x20]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          await request.response.close();
        },
      });
      final watch = Stopwatch()..start();

      final result = await transport(
        deadline: const Duration(seconds: 1),
      ).send(_get(server.url('/api/book/')));

      expect(result, _failsWith<CoordinatorTimedOut>());
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('cuts a coordinator that never sends its headers', () async {
      final server = await serve({
        '/api/info/': (request) => Completer<void>().future,
      });

      final result = await transport(
        deadline: const Duration(seconds: 1),
      ).send(_get(server.url('/api/info/')));

      expect(result, _failsWith<CoordinatorTimedOut>());
    });

    test('cuts a Tor session that never opens', () async {
      final result = await transport(
        deadline: const Duration(milliseconds: 300),
        openSession: () => Completer<TorSession>().future,
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorTimedOut>());
    });
  });

  group('connection failures', () {
    test('retries a GET on a new session after a SOCKS refusal', () async {
      final server = await serve({'/api/info/': _json('{}')});
      final tor = transport(
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
            ? _socksRefusal(CommandReplyCode.hostUnreachable)
            : HttpClient(),
      );

      final result = await tor.send(_get(server.url('/api/info/')));

      expect(result, isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>());
      expect(sessions.opened, hasLength(2));
      expect(sessions.closed, {0});
      // The new session serves the next request.
      await tor.send(_get(server.url('/api/info/')));
      expect(sessions.opened, hasLength(2));
    });

    test('gives up after two retries, each on a new session', () async {
      final result = await transport(
        createHttpClient: (_) => _socksRefusal(CommandReplyCode.ttlExpired),
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(sessions.opened, hasLength(1 + coordinatorConnectRetries));
      expect(sessions.closed, {0, 1, 2});
    });

    test('retries a refused TCP connection', () async {
      final closedPort = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = closedPort.port;
      await closedPort.close();

      final result = await transport().send(
        _get(Uri.parse('http://127.0.0.1:$port/api/info/')),
      );

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(sessions.opened, hasLength(1 + coordinatorConnectRetries));
    });

    test('never retries a request that is not a GET', () async {
      final result = await transport(
        createHttpClient: (_) =>
            _socksRefusal(CommandReplyCode.hostUnreachable),
      ).send(
        CoordinatorRequest(
          method: CoordinatorHttpMethod.post,
          url: Uri.parse('http://127.0.0.1:1/api/make/'),
          headers: const {'Content-Type': 'application/json'},
          body: Uint8List.fromList('{}'.codeUnits),
          maxResponseBytes: 4096,
        ),
      );

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(sessions.opened, hasLength(1));
      expect(sessions.closed, {0});
    });

    test('reports a connection lost in the middle of the body', () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.listen((socket) {
        var answered = false;
        socket.listen((_) {
          if (answered) return;
          answered = true;
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: application/json\r\n'
              'Content-Length: 1000\r\n'
              '\r\n'
              '0123456789',
            ),
          );
          socket.flush().then((_) => socket.destroy());
        });
      });
      try {
        final result = await transport().send(
          _get(Uri.parse('http://127.0.0.1:${raw.port}/api/book/')),
        );

        expect(result, _failsWith<CoordinatorUnreachable>());
        expect(sessions.opened, hasLength(1));
      } finally {
        await raw.close();
      }
    });
  });

  group('never throws', () {
    test('when Tor cannot give a session', () async {
      final result = await transport(
        openSession: () async => throw const TorBackendException(
          TorBootstrapFailure('no network'),
        ),
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorUnreachable>());
    });

    test('when the HTTP client factory throws, and closes the session', () async {
      final result = await transport(
        createHttpClient: (_) => throw const TorBackendException(
          TorUnexpectedFailure('not an IP literal'),
        ),
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorTransportFailed>());
      expect(sessions.closed, {0});
    });

    test('when the URL is not HTTP', () async {
      final result = await transport().send(
        _get(Uri.parse('ftp://127.0.0.1/api/info/')),
      );

      expect(result, _failsWith<CoordinatorTransportFailed>());
      expect(sessions.opened, isEmpty);
    });

    test('and tries a new session after Tor failed to give one', () async {
      var failing = true;
      final server = await serve({'/api/info/': _json('{}')});
      final tor = transport(
        openSession: () async {
          if (failing) {
            throw const TorBackendException(TorBootstrapFailure('offline'));
          }
          return sessions.open();
        },
      );

      expect(
        await tor.send(_get(server.url('/api/info/'))),
        _failsWith<CoordinatorUnreachable>(),
      );
      failing = false;
      expect(
        await tor.send(_get(server.url('/api/info/'))),
        isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>(),
      );
    });
  });

  group('closeSessions', () {
    test('closes every session, and the next request opens a new one', () async {
      final first = await serve({'/api/info/': _json('{}')});
      final second = await serve({'/api/info/': _json('{}')});
      final tor = transport();
      await tor.send(_get(first.url('/api/info/')));
      await tor.send(_get(second.url('/api/info/')));

      await tor.closeSessions();

      expect(sessions.closed, {0, 1});
      final result = await tor.send(_get(first.url('/api/info/')));
      expect(result, isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>());
      expect(sessions.opened, hasLength(3));
    });

    test('fails a request in progress without opening a new session', () async {
      final arrived = Completer<void>();
      final server = await serve({
        '/api/info/': (request) {
          arrived.complete();
          return Completer<void>().future;
        },
      });
      final tor = transport();
      final watch = Stopwatch()..start();

      final pending = tor.send(_get(server.url('/api/info/')));
      await arrived.future;
      await tor.closeSessions();
      final result = await pending;

      expect(
        result,
        isA<Err<CoordinatorResponse, CoordinatorTransportFailure>>(),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(sessions.opened, hasLength(1));
      expect(sessions.closed, {0});
    });

    test('closes a session that finishes opening afterwards', () async {
      final opening = Completer<TorSession>();
      final tor = transport(openSession: () => opening.future);

      final pending = tor.send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));
      await Future<void>.delayed(Duration.zero);
      await tor.closeSessions();
      opening.complete(await sessions.open());

      expect(await pending, _failsWith<CoordinatorTransportFailed>());
      expect(sessions.closed, {0});
    });
  });
}

Matcher _failsWith<F extends CoordinatorTransportFailure>() =>
    isA<Err<CoordinatorResponse, CoordinatorTransportFailure>>().having(
      (err) => err.failure,
      'failure',
      isA<F>(),
    );
