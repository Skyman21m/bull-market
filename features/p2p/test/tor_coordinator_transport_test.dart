import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bull_tor/tor.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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

  /// The sessions whose close was asked for, in that order: a session is in [closed] only once its close completes.
  final List<int> closing = [];

  /// What the close of a session waits for before it completes, by session index: a future that never completes makes a session that never finishes closing.
  final Map<int, Future<void>> closeGates = {};

  /// What the close of a session waits for when [closeGates] has nothing for it, asked when the close starts.
  Future<void> Function(int index)? closeGateOf;

  /// What the close of a session throws once it completes, by session index.
  final Map<int, Object> closeThrows = {};

  /// The most sessions that were open at the same time, a session being open until its close completes.
  int maxOpen = 0;

  Future<TorSession> open() async {
    final index = opened.length;
    final session = TorSession(
      TorProxyEndpoint(host: '127.0.0.1', port: 9000 + index),
      TorTransport.direct,
      () async {
        closing.add(index);
        await (closeGates[index] ?? closeGateOf?.call(index));
        closed.add(index);
        final thrown = closeThrows[index];
        if (thrown != null) throw thrown;
      },
    );
    opened.add(session);
    final open = opened.length - closed.length;
    if (open > maxOpen) maxOpen = open;
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

/// A coordinator written byte by byte: [onRequest] runs once the request arrives.
final class _RawServer {
  final ServerSocket _socket;
  final _clientGone = Completer<void>();

  /// The connections the server accepted.
  int connections = 0;

  _RawServer._(this._socket);

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_socket.port}$path');

  /// Completes when a client closes its connection: the server sees it go away.
  Future<void> get clientGone => _clientGone.future;

  Future<void> close() => _socket.close();
}

/// The headers of a JSON answer that announces [length] bytes.
List<int> _jsonHead(int length) => utf8.encode(
  'HTTP/1.1 200 OK\r\n'
  'Content-Type: application/json\r\n'
  'Content-Length: $length\r\n'
  '\r\n',
);

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

/// A request that is never retried, since it is not a `GET`.
CoordinatorRequest _post(Uri url, {RobotSessionKey? robot}) =>
    CoordinatorRequest(
      method: CoordinatorHttpMethod.post,
      url: url,
      headers: const {'Content-Type': 'application/json'},
      body: Uint8List.fromList('{}'.codeUnits),
      maxResponseBytes: 4096,
      robot: robot,
    );

CoordinatorRequest _get(
  Uri url, {
  int maxResponseBytes = 4096,
  Map<String, String> headers = const {'Accept': 'application/json'},
  RobotSessionKey? robot,
}) => CoordinatorRequest(
  method: CoordinatorHttpMethod.get,
  url: url,
  headers: headers,
  maxResponseBytes: maxResponseBytes,
  robot: robot,
);

/// A Garage Key made for these tests only, whose robots give as many distinct session keys as a test needs.
final GarageKey _testGarageKey = switch (GarageKey.fromBytes(
  Uint8List.fromList(List.generate(32, (index) => index + 1)),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

final Map<int, RobotIdentity> _identities = {};

/// The test robot number [number].
RobotIdentity _identity(int number) =>
    _identities[number] ??= switch (_testGarageKey.deriveIdentity(number)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

/// The session key of the test robot number [number].
RobotSessionKey _robot(int number) => _identity(number).sessionKey;

/// An HTTP client that connects once, then is refused by its SOCKS proxy, as when Tor loses the onion service: the session works for its first request only.
HttpClient _oneConnectionThenRefused() {
  var connections = 0;
  return HttpClient()
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      connections++;
      if (connections > 1) {
        throw SocksClientConnectionCommandFailedException(
          CommandReplyCode.hostUnreachable,
        );
      }
      return ConnectionTask.fromSocket(
        Socket.connect(uri.host, uri.port),
        () {},
      );
    };
}

/// Answers `{}` and records, under the `X-Label` header of each request, the client port of the connection that carried it.
Future<void> Function(HttpRequest) _recordingConnection(
  Map<String, int> ports,
) => (request) async {
  ports[request.headers.value('x-label') ?? ''] =
      request.connectionInfo?.remotePort ?? -1;
  await _json('{}')(request);
};

/// Answers `[]` once [release] completes, after telling [arrived] that the request is there.
Future<void> Function(HttpRequest) _held(
  Future<void> release, {
  void Function()? arrived,
}) => (request) async {
  arrived?.call();
  await release;
  await _json('[]')(request);
};

/// A path that answers `[]` only once [release] is called, and tells how many requests wait there.
final class _Held {
  final _release = Completer<void>();
  final _waiters = <(int, Completer<void>)>[];
  int _arrived = 0;

  Future<void> handle(HttpRequest request) async {
    _arrived++;
    for (final (count, waiter) in _waiters) {
      if (_arrived >= count && !waiter.isCompleted) waiter.complete();
    }
    await _release.future;
    await _json('[]')(request);
  }

  /// Completes once [count] requests have arrived.
  Future<void> waiting(int count) {
    final waiter = Completer<void>();
    if (_arrived >= count) waiter.complete();
    _waiters.add((count, waiter));
    return waiter.future;
  }

  void release() {
    if (!_release.isCompleted) _release.complete();
  }
}

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
      robot: request.robot,
    ),
  );
}

void main() {
  late _Sessions sessions;
  final servers = <_Server>[];
  final rawServers = <_RawServer>[];
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
    for (final server in rawServers) {
      await server.close();
    }
    rawServers.clear();
  });

  Future<_Server> serve(
    Map<String, Future<void> Function(HttpRequest)> routes,
  ) async {
    final server = await _Server.start(routes);
    servers.add(server);
    return server;
  }

  Future<_RawServer> rawServer(Future<void> Function(Socket) onRequest) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _RawServer._(socket);
    socket.listen((client) {
      server.connections++;
      var answered = false;
      void gone() {
        if (!server._clientGone.isCompleted) server._clientGone.complete();
      }

      client.listen(
        (_) {
          if (answered) return;
          answered = true;
          onRequest(client).catchError((Object _) {});
        },
        onError: (Object _) => gone(),
        onDone: gone,
      );
    });
    rawServers.add(server);
    return server;
  }

  /// A transport that reaches the loopback servers of these tests instead of onion services.
  ///
  /// The tests of the bound of all the robot sessions put every place on one loopback server: they pass [maxRobotSessions] as [placesPerCoordinator], which is [maxRobotSessionsPerCoordinator] otherwise.
  TorCoordinatorTransport transport({
    Duration deadline = const Duration(seconds: 5),
    Duration? closeTimeout,
    HttpClient Function(TorProxyEndpoint endpoint)? createHttpClient,
    Future<TorSession> Function()? openSession,
    int? placesPerCoordinator,
  }) {
    final transport = TorCoordinatorTransport.withSeams(
      openSession: openSession ?? sessions.open,
      createHttpClient: createHttpClient ?? (_) => HttpClient(),
      deadline: deadline,
      attemptTimeout: const Duration(seconds: 10),
      closeTimeout: closeTimeout,
      acceptsHost: (host) => host == '127.0.0.1',
      placesPerCoordinator: placesPerCoordinator,
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

    test('sends no User-Agent and asks for no compression', () async {
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
      expect(headers.value(HttpHeaders.acceptEncodingHeader), 'identity');
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

    test(
      'reuses one session per origin, even for concurrent requests',
      () async {
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
      },
    );
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

    test(
      'refuses at once a body announced too large, and drops the connection',
      () async {
        final raw = await rawServer((socket) async {
          // No body follows: only the announced length can refuse the answer.
          socket.add(_jsonHead(1024 * 1024 * 1024));
          await socket.flush();
        });
        final watch = Stopwatch()..start();

        final result = await transport().send(
          _get(raw.url('/api/book/'), maxResponseBytes: 64 * 1024),
        );

        expect(result, _failsWith<CoordinatorResponseTooLarge>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
        await raw.clientGone.timeout(const Duration(seconds: 1));
      },
    );

    test('stops reading a chunked body one byte over the cap', () async {
      final server = await serve({'/api/book/': _chunked(4097)});

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 4096),
      );

      expect(result, _failsWith<CoordinatorResponseTooLarge>());
    });

    test('stops reading a body that never ends and drops the connection', () async {
      final serverStopped = Completer<int>();
      final raw = await rawServer((socket) async {
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Transfer-Encoding: chunked\r\n'
            '\r\n',
          ),
        );
        final chunk = utf8.encode('4000\r\n${' ' * 0x4000}\r\n');
        var sent = 0;
        try {
          // Bounded only so that a broken transport fails this test instead of filling the memory.
          while (sent < 256 * 1024 * 1024) {
            socket.add(chunk);
            await socket.flush();
            sent += 0x4000;
          }
        } on Object {
          // The client went away: what this test waits for.
        }
        serverStopped.complete(sent);
      });
      final watch = Stopwatch()..start();

      final result = await transport().send(
        _get(raw.url('/api/book/'), maxResponseBytes: 64 * 1024),
      );

      expect(result, _failsWith<CoordinatorResponseTooLarge>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      // The server sees the connection closed: the client neither reads on nor keeps it open.
      final sent = await serverStopped.future.timeout(
        const Duration(seconds: 10),
      );
      expect(sent, lessThan(64 * 1024 * 1024));
    });

    test('neither asks for nor inflates a compressed body', () async {
      final compressed = gzip.encode(Uint8List(8 * 1024 * 1024));
      final server = await serve({
        '/api/book/': (request) async {
          request.response
            ..headers.contentType = ContentType.json
            ..headers.set(HttpHeaders.contentEncodingHeader, 'gzip')
            ..contentLength = compressed.length
            ..add(compressed);
          await request.response.close();
        },
      });

      final result = await transport().send(
        _get(server.url('/api/book/'), maxResponseBytes: 64 * 1024),
      );

      expect(
        server.received.single.value(HttpHeaders.acceptEncodingHeader),
        'identity',
      );
      // The 8 MB of zeros stay the few kilobytes that arrived, which the coordinator client then rejects as not JSON.
      expect(
        result,
        isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>().having(
          (ok) => ok.value.body,
          'body',
          compressed,
        ),
      );
    });
  });

  group('deadline', () {
    test(
      'cuts a body sent a byte at a time, and drops the connection',
      () async {
        final raw = await rawServer((socket) async {
          socket.add(_jsonHead(1000));
          for (var i = 0; i < 1000; i++) {
            socket.add(const [0x20]);
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        final watch = Stopwatch()..start();

        final result = await transport(
          deadline: const Duration(seconds: 1),
        ).send(_get(raw.url('/api/book/')));

        expect(result, _failsWith<CoordinatorTimedOut>());
        expect(watch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
        expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
        // The request is abandoned, not only answered for.
        await raw.clientGone.timeout(const Duration(seconds: 1));
      },
    );

    test(
      'cuts a coordinator that never sends its headers, and drops the connection',
      () async {
        final raw = await rawServer((socket) => Completer<void>().future);

        final result = await transport(
          deadline: const Duration(seconds: 1),
        ).send(_get(raw.url('/api/info/')));

        expect(result, _failsWith<CoordinatorTimedOut>());
        await raw.clientGone.timeout(const Duration(seconds: 1));
        expect(sessions.closed, {0});
      },
    );

    test('cancels a connection still being made', () async {
      var cancelled = 0;

      final result = await transport(
        deadline: const Duration(milliseconds: 300),
        createHttpClient: (_) => HttpClient()
          ..connectionFactory = (uri, proxyHost, proxyPort) async =>
              ConnectionTask.fromSocket(
                Completer<Socket>().future,
                () => cancelled++,
              ),
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorTimedOut>());
      final watch = Stopwatch()..start();
      while (cancelled == 0 && watch.elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Without this, the connection would wait for the timeout of the attempt, ten seconds here.
      expect(cancelled, greaterThan(0));
      expect(sessions.closed, {0});
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

      expect(
        result,
        isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>(),
      );
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
      final result =
          await transport(
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

    // An action on an order (a take, a cancel) is a `POST` that the coordinator may have carried out even when no answer came back: sent twice, it could act twice.
    test('never sends a POST again once it reached the coordinator', () async {
      final raw = await rawServer((socket) async {
        socket.add(utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: appl'));
        await socket.flush();
        socket.destroy();
      });

      final result = await transport().send(
        _post(raw.url('/api/order/'), robot: _robot(1)),
      );

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(raw.connections, 1);
      expect(sessions.opened, hasLength(1));
    });

    test('never sends a POST again after its deadline passed', () async {
      var received = 0;
      final server = await serve({
        '/api/order/': (request) async {
          received++;
          await Completer<void>().future;
        },
      });

      final result = await transport(
        deadline: const Duration(seconds: 1),
      ).send(_post(server.url('/api/order/'), robot: _robot(1)));

      expect(result, _failsWith<CoordinatorTimedOut>());
      // Long enough for a second attempt, had there been one.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(received, 1);
      expect(sessions.opened, hasLength(1));
    });

    test('retries a connection closed before the headers', () async {
      final raw = await rawServer((socket) async {
        socket.add(utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: appl'));
        await socket.flush();
        socket.destroy();
      });

      final result = await transport().send(_get(raw.url('/api/info/')));

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(sessions.opened, hasLength(1 + coordinatorConnectRetries));
    });

    test('closes a replaced session only when its last request ends', () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      final server = await serve({
        '/slow': (request) async {
          request.response
            ..headers.contentType = ContentType.json
            ..write('[');
          await request.response.flush();
          arrived.complete();
          await release.future;
          request.response.write(']');
          await request.response.close();
        },
        '/fast': _json('{}'),
      });
      var connections = 0;
      final tor = transport(
        createHttpClient: (endpoint) {
          if (_Sessions.indexOf(endpoint) != 0) return HttpClient();
          // The first session connects once, then Tor refuses it.
          return HttpClient()
            ..connectionFactory = (uri, proxyHost, proxyPort) async {
              connections++;
              if (connections > 1) {
                throw SocksClientConnectionCommandFailedException(
                  CommandReplyCode.hostUnreachable,
                );
              }
              return ConnectionTask.fromSocket(
                Socket.connect(uri.host, uri.port),
                () {},
              );
            };
        },
      );

      final slow = tor.send(_get(server.url('/slow')));
      await arrived.future;
      final fast = await tor.send(_get(server.url('/fast')));

      expect(fast, isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>());
      expect(sessions.opened, hasLength(2));
      // The first session is replaced, but its slow request still runs on it.
      expect(sessions.closed, isEmpty);

      release.complete();
      expect(
        await slow,
        isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sessions.closed, {0});
      await tor.send(_get(server.url('/fast')));
      expect(sessions.opened, hasLength(2));
    });

    test('reports a connection lost in the middle of the body', () async {
      final raw = await rawServer((socket) async {
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: 1000\r\n'
            '\r\n'
            '0123456789',
          ),
        );
        await socket.flush();
        socket.destroy();
      });

      final result = await transport().send(_get(raw.url('/api/book/')));

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(sessions.opened, hasLength(1));
    });
  });

  group('answers that are not HTTP fail at once, without retry', () {
    for (final (name, answer) in [
      ('garbage instead of a status line', 'GARBAGE GARBAGE\r\n\r\n'),
      (
        'a negative Content-Length',
        'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: -5\r\n\r\n{}',
      ),
      (
        'two Content-Lengths',
        'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: 2\r\nContent-Length: 900000\r\n\r\n{}',
      ),
      (
        'a NUL in a header',
        'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'X-A: a\u0000b\r\nContent-Length: 2\r\n\r\n{}',
      ),
    ]) {
      test(name, () async {
        final raw = await rawServer((socket) async {
          socket.add(latin1.encode(answer));
          await socket.flush();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          socket.destroy();
        });

        final result = await transport().send(_get(raw.url('/api/book/')));

        expect(result, _failsWith<CoordinatorTransportFailed>());
        expect(sessions.opened, hasLength(1));
      });
    }

    test('an endless header section', () async {
      final raw = await rawServer((socket) async {
        socket.add(
          utf8.encode('HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'),
        );
        final line = utf8.encode('X-Pad: ${'a' * 4000}\r\n');
        // Bounded only so that a broken transport fails this test instead of filling the memory.
        for (var sent = 0; sent < 64 * 1024 * 1024; sent += line.length) {
          socket.add(line);
          await socket.flush();
        }
      });

      final result = await transport().send(_get(raw.url('/api/book/')));

      expect(result, _failsWith<CoordinatorTransportFailed>());
      expect(sessions.opened, hasLength(1));
    });
  });

  group('only reaches onion services', () {
    test('refuses by default anything but http to a .onion host', () async {
      final tor = TorCoordinatorTransport.withSeams(
        openSession: sessions.open,
        createHttpClient: (_) => HttpClient(),
      );
      transports.add(tor);

      for (final url in [
        'https://ammannjgzybw4qm2odmci7xgolh5grzijidacjxose5tthm375dcopad.onion/api/info/',
        'http://example.com/api/info/',
        'http://127.0.0.1/api/info/',
        'file:///etc/passwd',
        'ftp://ammannjgzybw4qm2odmci7xgolh5grzijidacjxose5tthm375dcopad.onion/',
        'http://abc.onion.example.com/api/info/',
        'http://a.onion@example.com/api/info/',
        'http://user:secret@ammannjgzybw4qm2odmci7xgolh5grzijidacjxose5tthm375dcopad.onion/api/info/',
      ]) {
        expect(
          await tor.send(_get(Uri.parse(url))),
          _failsWith<CoordinatorTransportFailed>(),
          reason: url,
        );
      }
      // Nothing can be sent without a session.
      expect(sessions.opened, isEmpty);
    });

    test('lets an http .onion URL through to Tor', () async {
      var asked = 0;
      final tor = TorCoordinatorTransport.withSeams(
        openSession: () async {
          asked++;
          throw const TorBackendException(TorBootstrapFailure('offline'));
        },
        createHttpClient: (_) => HttpClient(),
      );

      final result = await tor.send(
        _get(
          Uri.parse(
            'http://ammannjgzybw4qm2odmci7xgolh5grzijidacjxose5tthm375dcopad.onion/api/info/',
          ),
        ),
      );

      expect(result, _failsWith<CoordinatorUnreachable>());
      expect(asked, 1);
    });
  });

  group('programming errors', () {
    test('an Error from the session opener reaches the caller', () async {
      final tor = transport(openSession: () async => throw StateError('bug'));

      await expectLater(
        tor.send(_get(Uri.parse('http://127.0.0.1:1/api/info/'))),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'an Error from the client factory reaches the caller, and the session is closed',
      () async {
        final tor = transport(createHttpClient: (_) => throw ArgumentError());

        await expectLater(
          tor.send(_get(Uri.parse('http://127.0.0.1:1/api/info/'))),
          throwsA(isA<ArgumentError>()),
        );
        expect(sessions.opened, hasLength(1));
        expect(sessions.closed, {0});
      },
    );

    test(
      'an Error from the close of a Tor session reaches closeSessions once, and the session no longer counts',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        sessions.closeThrows[0] = StateError('bug');
        final tor = transport();
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
          isA<Ok<Object?, Failure>>(),
        );
        expect(tor.countsForTesting.places, 1);

        await expectLater(tor.closeSessions(), throwsA(isA<StateError>()));

        expect(tor.countsForTesting.live, 0);
        expect(tor.countsForTesting.places, 0);
        // The next close does not meet it again, and the robot gets a new session.
        await tor.closeSessions();
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
          isA<Ok<Object?, Failure>>(),
        );
        expect(sessions.opened, hasLength(2));
      },
    );

    test(
      'an Error from the close of a session left without a client reaches the caller, and the place is given back',
      () async {
        sessions.closeThrows[0] = StateError('bug');
        final tor = transport(
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
              ? throw const SocketException('no client')
              : HttpClient(),
        );

        await expectLater(
          tor.send(
            _get(Uri.parse('http://127.0.0.1:1/api/robot/'), robot: _robot(1)),
          ),
          throwsA(isA<StateError>()),
        );
        expect(sessions.closed, {0});
        expect(tor.countsForTesting.places, 0);
        expect(tor.countsForTesting.placesOf, isEmpty);
      },
    );
  });

  group('never throws', () {
    test('when Tor cannot give a session', () async {
      final result = await transport(
        openSession: () async =>
            throw const TorBackendException(TorBootstrapFailure('no network')),
      ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

      expect(result, _failsWith<CoordinatorUnreachable>());
    });

    test(
      'when the HTTP client factory throws, and closes the session',
      () async {
        final result = await transport(
          createHttpClient: (_) => throw const TorBackendException(
            TorUnexpectedFailure('not an IP literal'),
          ),
        ).send(_get(Uri.parse('http://127.0.0.1:1/api/info/')));

        expect(result, _failsWith<CoordinatorTransportFailed>());
        expect(sessions.closed, {0});
      },
    );

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

  group('robot sessions', () {
    test(
      'keep a robot apart from the anonymous requests and from another robot',
      () async {
        final ports = <String, int>{};
        final server = await serve({
          '/api/robot/': _recordingConnection(ports),
        });
        final tor = transport();
        Future<void> send(String label, RobotSessionKey? robot) async {
          final result = await tor.send(
            _get(
              server.url('/api/robot/'),
              headers: {'X-Label': label},
              robot: robot,
            ),
          );
          expect(result, isA<Ok<Object?, Failure>>(), reason: label);
        }

        await send('anonymous 1', null);
        await send('robot 1, first', _robot(1));
        await send('robot 2, first', _robot(2));
        await send('robot 1, second', _robot(1));
        await send('anonymous 2', null);
        await send('robot 2, second', _robot(2));

        expect(sessions.opened, hasLength(3));
        expect(sessions.closed, isEmpty);
        // Each session has its own HTTP client: its requests reuse its connection, and no other does.
        expect(ports['anonymous 2'], ports['anonymous 1']);
        expect(ports['robot 1, second'], ports['robot 1, first']);
        expect(ports['robot 2, second'], ports['robot 2, first']);
        expect({
          ports['anonymous 1'],
          ports['robot 1, first'],
          ports['robot 2, first'],
        }, hasLength(3));
      },
    );

    test(
      'are required for a credential: none travels on an anonymous session',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport();

        for (final name in [
          'Authorization',
          'authorization',
          'AUTHORIZATION',
        ]) {
          final result = await tor.send(
            _get(
              server.url('/api/robot/'),
              headers: {'Accept': 'application/json', name: 'Token abc'},
            ),
          );

          expect(result, _failsWith<CoordinatorTransportFailed>());
        }
        expect(sessions.opened, isEmpty);
        expect(server.received, isEmpty);
      },
    );

    test('give a robot one session per coordinator', () async {
      final first = await serve({'/api/robot/': _json('{}')});
      final second = await serve({'/api/robot/': _json('{}')});
      final tor = transport();

      for (final server in [first, second, first, second]) {
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      }

      expect(sessions.opened, hasLength(2));
      expect(sessions.closed, isEmpty);
    });

    test(
      'share the session of a robot between its concurrent requests',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport();

        final results = await Future.wait([
          for (var i = 0; i < 4; i++)
            tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
        ]);

        expect(results, everyElement(isA<Ok<Object?, Failure>>()));
        expect(sessions.opened, hasLength(1));
      },
    );

    test('carry a first-contact header as it is given', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      // The characters of a real header: base91 with quotes and pipes, armored keys with backslashes.
      final authorization =
          'Token ab"c|d~{e}<f>?[g]^`h | Public -----BEGIN\\${'A/b+9=' * 150}\\-----END'
          ' | Private ${'Zz09+/' * 200}\\=abcd | Nostr ${'0f' * 32}';

      final result = await transport().send(
        _get(
          server.url('/api/robot/'),
          headers: {
            'Accept': 'application/json',
            'Authorization': authorization,
          },
          robot: _robot(1),
        ),
      );

      expect(result, isA<Ok<Object?, Failure>>());
      final headers = server.received.single;
      expect(headers.value(HttpHeaders.authorizationHeader), authorization);
      expect(authorization.length, greaterThan(2000));
      expect(headers.value(HttpHeaders.userAgentHeader), isNull);
    });

    test(
      'retry on a new session of the same robot, and leave the others alone',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport(
          // Session 0 is the anonymous one, session 1 the first of the robot.
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 1
              ? _socksRefusal(CommandReplyCode.hostUnreachable)
              : HttpClient(),
        );
        await tor.send(_get(server.url('/api/robot/')));

        final result = await tor.send(
          _get(server.url('/api/robot/'), robot: _robot(1)),
        );

        expect(
          result,
          isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>(),
        );
        expect(sessions.opened, hasLength(3));
        expect(sessions.closed, {1});
        // The new session serves the robot, the anonymous one still serves the rest.
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
        await tor.send(_get(server.url('/api/robot/')));
        expect(sessions.opened, hasLength(3));
      },
    );

    test('are bounded: the least recently used idle one makes room', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final tor = transport(placesPerCoordinator: maxRobotSessions);
      Future<void> send(RobotSessionKey? robot) async {
        final result = await tor.send(
          _get(server.url('/api/robot/'), robot: robot),
        );
        expect(result, isA<Ok<Object?, Failure>>());
      }

      // Session 0 is anonymous; robot n gets session n.
      await send(null);
      for (var robot = 1; robot <= maxRobotSessions; robot++) {
        await send(_robot(robot));
      }
      expect(sessions.opened, hasLength(1 + maxRobotSessions));
      expect(sessions.closed, isEmpty);

      // Robot 1 is used again, so robot 2 is now the least recently used.
      await send(_robot(1));
      await send(_robot(maxRobotSessions + 1));
      expect(sessions.opened, hasLength(2 + maxRobotSessions));
      expect(sessions.closed, {2});

      // Robot 2 comes back on a new session, and takes the place of robot 3.
      await send(_robot(2));
      expect(sessions.opened, hasLength(3 + maxRobotSessions));
      expect(sessions.closed, {2, 3});

      // The anonymous session is neither counted nor closed, and the robots kept still have theirs.
      await send(null);
      await send(_robot(1));
      await send(_robot(maxRobotSessions));
      expect(sessions.opened, hasLength(3 + maxRobotSessions));
      expect(sessions.closed, {2, 3});
    });

    test('are bounded: a request fails when every session is in use', () async {
      final release = Completer<void>();
      var arrived = 0;
      final allArrived = Completer<void>();
      final server = await serve({
        '/held': _held(
          release.future,
          arrived: () {
            if (++arrived == maxRobotSessions) allArrived.complete();
          },
        ),
        '/api/robot/': _json('{}'),
      });
      final tor = transport(
        deadline: const Duration(seconds: 20),
        placesPerCoordinator: maxRobotSessions,
      );

      final held = [
        for (var robot = 1; robot <= maxRobotSessions; robot++)
          tor.send(_get(server.url('/held'), robot: _robot(robot))),
      ];
      await allArrived.future;
      final refused = await tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
      );
      // A robot that has its session, and the anonymous requests, are not affected.
      final sameRobot = await tor.send(
        _get(server.url('/api/robot/'), robot: _robot(1)),
      );
      final anonymous = await tor.send(_get(server.url('/api/robot/')));

      // The failure of the bound, which a caller tells apart from a coordinator that does not work.
      expect(refused, _failsWith<CoordinatorTransportBusy>());
      expect(sameRobot, isA<Ok<Object?, Failure>>());
      expect(anonymous, isA<Ok<Object?, Failure>>());
      expect(sessions.opened, hasLength(maxRobotSessions + 1));
      expect(sessions.closed, isEmpty);

      release.complete();
      expect(
        await Future.wait(held),
        everyElement(isA<Ok<Object?, Failure>>()),
      );
      // Once a session is idle again, the robot that was refused gets its place.
      final accepted = await tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
      );
      expect(accepted, isA<Ok<Object?, Failure>>());
      expect(sessions.closed, hasLength(1));
    });

    test(
      'are bounded: a session replaced while a request still uses it keeps its place',
      () async {
        final release = Completer<void>();
        var arrived = 0;
        final allArrived = Completer<void>();
        final server = await serve({
          '/held': _held(
            release.future,
            arrived: () {
              if (++arrived == maxRobotSessions) allArrived.complete();
            },
          ),
          '/api/robot/': _json('{}'),
        });
        final tor = transport(
          placesPerCoordinator: maxRobotSessions,
          deadline: const Duration(seconds: 20),
          // The first session of every robot serves one request, then fails to connect.
          createHttpClient: (endpoint) =>
              _Sessions.indexOf(endpoint) < maxRobotSessions
              ? _oneConnectionThenRefused()
              : HttpClient(),
        );
        final held = [
          for (var robot = 1; robot <= maxRobotSessions; robot++)
            tor.send(_get(server.url('/held'), robot: _robot(robot))),
        ];
        await allArrived.future;

        // A second request of each robot: its session is replaced, and still used by the first request.
        final second = await Future.wait([
          for (var robot = 1; robot <= maxRobotSessions; robot++)
            tor.send(_get(server.url('/api/robot/'), robot: _robot(robot))),
        ]);

        // No place is left for a replacement: the sessions being replaced still count.
        expect(second, everyElement(_failsWith<CoordinatorTransportBusy>()));
        expect(sessions.opened, hasLength(maxRobotSessions));
        expect(sessions.closed, isEmpty);

        release.complete();
        expect(
          await Future.wait(held),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
        // The replaced sessions close with their last request, and give their places back.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sessions.closed, hasLength(maxRobotSessions));
        final after = await Future.wait([
          for (var robot = 1; robot <= maxRobotSessions; robot++)
            tor.send(_get(server.url('/api/robot/'), robot: _robot(robot))),
        ]);
        expect(after, everyElement(isA<Ok<Object?, Failure>>()));
        expect(sessions.opened, hasLength(2 * maxRobotSessions));
        expect(
          sessions.opened.length - sessions.closed.length,
          maxRobotSessions,
        );
      },
    );

    test(
      'are bounded: a retry at the bound takes the place of the session it replaces',
      () async {
        final release = Completer<void>();
        var arrived = 0;
        final allArrived = Completer<void>();
        final server = await serve({
          '/held': _held(
            release.future,
            arrived: () {
              if (++arrived == maxRobotSessions - 1) allArrived.complete();
            },
          ),
          '/api/robot/': _json('{}'),
        });
        final tor = transport(
          placesPerCoordinator: maxRobotSessions,
          deadline: const Duration(seconds: 20),
          // The session opened last, for the robot that comes last, never connects.
          createHttpClient: (endpoint) =>
              _Sessions.indexOf(endpoint) == maxRobotSessions - 1
              ? _socksRefusal(CommandReplyCode.hostUnreachable)
              : HttpClient(),
        );
        final held = [
          for (var robot = 1; robot < maxRobotSessions; robot++)
            tor.send(_get(server.url('/held'), robot: _robot(robot))),
        ];
        await allArrived.future;

        final retried = await tor.send(
          _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions)),
        );

        // The failed session closes, and only then does its replacement open, in its place.
        expect(retried, isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(maxRobotSessions + 1));
        expect(sessions.closed, {maxRobotSessions - 1});
        release.complete();
        await Future.wait(held);
      },
    );

    test('are not closed to make room once a request has picked them', () async {
      final release = Completer<void>();
      var arrived = 0;
      final allArrived = Completer<void>();
      final server = await serve({
        '/held': _held(
          release.future,
          arrived: () {
            if (++arrived == maxRobotSessions - 1) allArrived.complete();
          },
        ),
        '/api/robot/': _json('{}'),
      });
      final tor = transport(
        deadline: const Duration(seconds: 20),
        placesPerCoordinator: maxRobotSessions,
      );
      // Robot 1 has an idle session, every other session is busy.
      await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      final held = [
        for (var robot = 2; robot <= maxRobotSessions; robot++)
          tor.send(_get(server.url('/held'), robot: _robot(robot))),
      ];
      await allArrived.future;

      // In the same turn: robot 1 picks its session, then a new robot looks for one to close.
      final picked = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(1)),
      );
      final newcomer = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
      );

      expect(await picked, isA<Ok<Object?, Failure>>());
      expect(await newcomer, _failsWith<CoordinatorTransportBusy>());
      expect(sessions.opened, hasLength(maxRobotSessions));
      expect(sessions.closed, isEmpty);
      release.complete();
      await Future.wait(held);
    });
  });

  group('the cap per coordinator and robot', () {
    test(
      'leaves two places to a coordinator that drops and holds the connections of one robot',
      () async {
        // The hostile coordinator drops every second connection before any header, and never answers the others.
        var connections = 0;
        var holding = 0;
        final hostile = await rawServer((socket) async {
          if ((++connections).isEven) {
            socket.destroy();
          } else {
            holding++;
          }
        });
        final honest = await serve({'/api/robot/': _json('{}')});
        final tor = transport(
          deadline: const Duration(seconds: 20),
          placesPerCoordinator: maxRobotSessions,
        );
        Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> ask(
          int robot,
        ) => tor.send(_get(honest.url('/api/robot/'), robot: _robot(robot)));
        // Other robots have an idle session each on the honest coordinator, and three places are left.
        const idle = maxRobotSessions - 3;
        for (var robot = 100; robot < 100 + idle; robot++) {
          expect(await ask(robot), isA<Ok<Object?, Failure>>());
        }

        // Forty requests of one robot, each started while the ones before are held or over.
        final results =
            <
              Future<Result<CoordinatorResponse, CoordinatorTransportFailure>>
            >[];
        var over = 0;
        for (var i = 0; i < 40; i++) {
          final settled = holding + over;
          results.add(
            tor.send(_get(hostile.url('/api/order/'), robot: _robot(1)))
              ..whenComplete(() => over++).ignore(),
          );
          while (holding + over == settled) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        }

        // The robot has its two sessions, each held by one request, and every other request failed at once.
        expect(holding, 2);
        expect(over, 38);
        expect(sessions.opened, hasLength(idle + 2));
        expect(sessions.closed, isEmpty);
        // A robot on the honest coordinator takes the last place.
        expect(await ask(1000), isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(maxRobotSessions));
        // At the bound, the robot of the hostile coordinator still gets no third session, though closing an idle one would make room.
        expect(
          await tor.send(_get(hostile.url('/api/order/'), robot: _robot(1))),
          _failsWith<CoordinatorTransportBusy>(),
        );
        expect(sessions.opened, hasLength(maxRobotSessions));
        expect(sessions.closed, isEmpty);
        // The idle sessions of the other robots are all there: their requests open nothing.
        for (var robot = 100; robot < 100 + idle; robot++) {
          expect(await ask(robot), isA<Ok<Object?, Failure>>());
        }
        expect(sessions.opened, hasLength(maxRobotSessions));
        expect(sessions.closed, isEmpty);
        expect(sessions.maxOpen, maxRobotSessions);

        await tor.closeSessions();
        // The two that were held end with the close, the others had found no place.
        final busy = _failsWith<CoordinatorTransportBusy>();
        final outcomes = await Future.wait(results);
        expect(
          outcomes.where((outcome) => busy.matches(outcome, {})),
          hasLength(38),
        );
      },
    );

    test(
      'lets a robot that has its two sessions take the place of its own closing one',
      () async {
        final held = _Held();
        final server = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        final gate = Completer<void>();
        sessions.closeGates[1] = gate.future;
        final tor = transport(
          deadline: const Duration(seconds: 20),
          // Session 0 serves one request, session 1 never connects, session 2 works.
          createHttpClient: (endpoint) => switch (_Sessions.indexOf(endpoint)) {
            0 => _oneConnectionThenRefused(),
            1 => _socksRefusal(CommandReplyCode.hostUnreachable),
            _ => HttpClient(),
          },
        );
        final first = tor.send(_get(server.url('/held'), robot: _robot(1)));
        await held.waiting(1);

        // Refused on session 0, which the first request still uses, then on session 1, which closes: the robot has its two places.
        final second = tor.send(
          _get(server.url('/api/robot/'), robot: _robot(1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Far below the bound, yet its third session waits for the second to be closed.
        expect(sessions.closing, [1]);
        expect(sessions.opened, hasLength(2));
        gate.complete();
        expect(await second, isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(3));
        expect(sessions.closed, {1});
        held.release();
        expect(await first, isA<Ok<Object?, Failure>>());
      },
    );

    test(
      'holds at the bound: the robot has two idle sessions closed, and no more',
      () async {
        // The hostile coordinator drops every second connection before any header, and never answers the others.
        var connections = 0;
        var holding = 0;
        final hostile = await rawServer((socket) async {
          if ((++connections).isEven) {
            socket.destroy();
          } else {
            holding++;
          }
        });
        final honest = await serve({'/api/robot/': _json('{}')});
        final tor = transport(
          deadline: const Duration(seconds: 20),
          placesPerCoordinator: maxRobotSessions,
        );
        // Every place holds the idle session of another robot.
        for (var robot = 100; robot < 100 + maxRobotSessions; robot++) {
          await tor.send(_get(honest.url('/api/robot/'), robot: _robot(robot)));
        }

        var over = 0;
        final results =
            <
              Future<Result<CoordinatorResponse, CoordinatorTransportFailure>>
            >[];
        for (var i = 0; i < 8; i++) {
          final settled = holding + over;
          results.add(
            tor.send(_get(hostile.url('/api/order/'), robot: _robot(1)))
              ..whenComplete(() => over++).ignore(),
          );
          while (holding + over == settled) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        }

        // Its two sessions took the places of the two least recently used ones, and its other requests closed nothing.
        expect(holding, 2);
        expect(over, 6);
        expect(sessions.closed, {0, 1});
        expect(sessions.opened, hasLength(maxRobotSessions + 2));
        expect(sessions.maxOpen, maxRobotSessions);
        await tor.closeSessions();
        final busy = _failsWith<CoordinatorTransportBusy>();
        expect(
          (await Future.wait(
            results,
          )).where((outcome) => busy.matches(outcome, {})),
          hasLength(6),
        );
      },
    );

    test(
      'gives a robot that has its two sessions no place from the closing session of another',
      () async {
        final held = _Held();
        final server = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        final gate = Completer<void>();
        sessions.closeGates[0] = gate.future;
        final tor = transport(
          deadline: const Duration(seconds: 20),
          // Session 0 is the one of robot 2; the sessions of robot 1 serve one request each.
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
              ? HttpClient()
              : _oneConnectionThenRefused(),
        );
        // The session of robot 2 is closing, slowly.
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(2)));
        final closing = tor.closeRobotSessions(_robot(2));
        // Robot 1 has two sessions, each held by a request.
        final requests = [
          for (var i = 0; i < 2; i++)
            tor.send(_get(server.url('/held'), robot: _robot(1))),
        ];
        await held.waiting(2).timeout(const Duration(seconds: 5));
        expect(sessions.closing, [0]);
        expect(sessions.opened, hasLength(3));

        final third = tor.send(
          _get(server.url('/api/robot/'), robot: _robot(1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        gate.complete();

        expect(await third, _failsWith<CoordinatorTransportBusy>());
        await closing;
        expect(sessions.opened, hasLength(3));
        held.release();
        expect(
          await Future.wait(requests),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );

    test(
      'keeps a robot that held two places and got one back capped at two',
      () async {
        final releaseFirst = Completer<void>();
        final arrivedFirst = Completer<void>();
        final held = _Held();
        final server = await serve({
          '/first': _held(releaseFirst.future, arrived: arrivedFirst.complete),
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        // Every session serves one request, then Tor refuses its connections.
        final tor = transport(
          deadline: const Duration(seconds: 20),
          createHttpClient: (_) => _oneConnectionThenRefused(),
        );
        int placesOfTheRobot() =>
            tor.countsForTesting.placesOf.values.fold(0, (sum, p) => sum + p);

        final first = tor.send(_get(server.url('/first'), robot: _robot(1)));
        await arrivedFirst.future;
        // Refused on session 0, which the first request still uses, the second request goes to session 1.
        final second = tor.send(_get(server.url('/held'), robot: _robot(1)));
        await held.waiting(1);
        expect(placesOfTheRobot(), 2);
        // The first request ends, and session 0 closes: one place comes back.
        releaseFirst.complete();
        expect(await first, isA<Ok<Object?, Failure>>());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(sessions.closed, {0});
        expect(placesOfTheRobot(), 1);
        expect(tor.countsForTesting.places, 1);
        // Refused on session 1, which the second request still uses, a third request goes to session 2.
        final third = tor.send(_get(server.url('/held'), robot: _robot(1)));
        await held.waiting(2);
        expect(placesOfTheRobot(), 2);

        // Refused on session 2, which the third request still uses, a fourth request finds the robot at its cap.
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
          _failsWith<CoordinatorTransportBusy>(),
        );
        expect(sessions.opened, hasLength(3));
        held.release();
        expect(
          await Future.wait([second, third]),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );

    test(
      'gives a robot at its cap no place from its own closing session on another coordinator',
      () async {
        final held = _Held();
        final server = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        final gate = Completer<void>();
        sessions.closeGates[0] = gate.future;
        final tor = transport(
          deadline: const Duration(seconds: 20),
          // Session 0, the one of the robot on the other coordinator, never connects; the others serve one request each.
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
              ? _socksRefusal(CommandReplyCode.hostUnreachable)
              : _oneConnectionThenRefused(),
        );
        // A request that is not retried leaves the session of the robot on the other coordinator closing, slowly.
        expect(
          await tor.send(
            _post(Uri.parse('http://127.0.0.1:1/api/robot/'), robot: _robot(1)),
          ),
          _failsWith<CoordinatorUnreachable>(),
        );
        expect(sessions.closing, [0]);
        // On this coordinator, the robot has its two sessions, each held by a request.
        final requests = [
          for (var i = 0; i < 2; i++)
            tor.send(_get(server.url('/held'), robot: _robot(1))),
        ];
        await held.waiting(2).timeout(const Duration(seconds: 5));
        expect(sessions.opened, hasLength(3));

        // Refused on its second session, a third request finds the robot at its cap here: its closing session elsewhere is no place for it.
        final third = await tor
            .send(_get(server.url('/api/robot/'), robot: _robot(1)))
            .timeout(const Duration(seconds: 3));

        expect(third, _failsWith<CoordinatorTransportBusy>());
        expect(sessions.opened, hasLength(3));
        gate.complete();
        held.release();
        expect(
          await Future.wait(requests),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );

    test('gives a robot its places back when its sessions close', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final tor = transport();

      for (var round = 0; round < 4; round++) {
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
          isA<Ok<Object?, Failure>>(),
        );
        await tor.closeRobotSessions(_robot(1));
      }

      expect(sessions.opened, hasLength(4));
      expect(sessions.closed, {0, 1, 2, 3});
    });

    test('counts the places of a robot per coordinator', () async {
      final held = _Held();
      final first = await serve({'/held': held.handle});
      final second = await serve({'/held': held.handle});
      final tor = transport(
        deadline: const Duration(seconds: 20),
        createHttpClient: (_) => _oneConnectionThenRefused(),
      );

      // Two sessions of the same robot on each coordinator, every one held by a request.
      final requests = [
        for (final server in [first, first, second, second])
          tor.send(_get(server.url('/held'), robot: _robot(1))),
      ];
      await held.waiting(4).timeout(const Duration(seconds: 5));

      expect(sessions.opened, hasLength(4));
      expect(
        await tor.send(_get(second.url('/held'), robot: _robot(1))),
        _failsWith<CoordinatorTransportBusy>(),
      );
      expect(sessions.opened, hasLength(4));
      held.release();
      expect(
        await Future.wait(requests),
        everyElement(isA<Ok<Object?, Failure>>()),
      );
    });
  });

  group('the ceiling per coordinator', () {
    test(
      'keeps places for the other coordinators when sixteen robots are sent to one that drops and holds their connections',
      () async {
        // The hostile coordinator drops every second connection before any header, and never answers the others.
        var connections = 0;
        var holding = 0;
        final hostile = await rawServer((socket) async {
          if ((++connections).isEven) {
            socket.destroy();
          } else {
            holding++;
          }
        });
        final honest = await serve({'/api/robot/': _json('{}')});
        final tor = transport(deadline: const Duration(seconds: 20));
        // Robot 500 has an idle session on the honest coordinator.
        expect(
          await tor.send(_get(honest.url('/api/robot/'), robot: _robot(500))),
          isA<Ok<Object?, Failure>>(),
        );

        // Four requests for each of sixteen robots, each started once the ones before are held or over.
        final results =
            <
              Future<Result<CoordinatorResponse, CoordinatorTransportFailure>>
            >[];
        var over = 0;
        for (var robot = 1; robot <= 16; robot++) {
          for (var i = 0; i < 4; i++) {
            final settled = holding + over;
            results.add(
              tor.send(_get(hostile.url('/api/order/'), robot: _robot(robot)))
                ..whenComplete(() => over++).ignore(),
            );
            while (holding + over == settled) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
        }

        // Twelve robots have their two sessions there, each held by a request, and the other requests failed at once.
        expect(holding, maxRobotSessionsPerCoordinator);
        expect(over, 64 - maxRobotSessionsPerCoordinator);
        final hostileOrigin = hostile.url('/').origin;
        expect(
          tor.countsForTesting.placesAt[hostileOrigin],
          maxRobotSessionsPerCoordinator,
        );
        // No session of the honest coordinator was closed for the hostile one, and its robots still find places.
        expect(sessions.closed, isEmpty);
        expect(
          await tor.send(_get(honest.url('/api/robot/'), robot: _robot(501))),
          isA<Ok<Object?, Failure>>(),
        );
        final opened = sessions.opened.length;
        expect(
          await tor.send(_get(honest.url('/api/robot/'), robot: _robot(500))),
          isA<Ok<Object?, Failure>>(),
        );
        expect(sessions.opened, hasLength(opened));
        expect(sessions.closed, isEmpty);

        await tor.closeSessions();
        final busy = _failsWith<CoordinatorTransportBusy>();
        expect(
          (await Future.wait(
            results,
          )).where((outcome) => busy.matches(outcome, {})),
          hasLength(64 - maxRobotSessionsPerCoordinator),
        );
      },
    );

    test(
      'lets a user with more robots on one coordinator recycle their idle sessions there',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport();
        final origin = server.url('/').origin;

        for (
          var robot = 1;
          robot <= maxRobotSessionsPerCoordinator + 6;
          robot++
        ) {
          expect(
            await tor.send(
              _get(server.url('/api/robot/'), robot: _robot(robot)),
            ),
            isA<Ok<Object?, Failure>>(),
          );
          expect(
            tor.countsForTesting.placesAt[origin],
            lessThanOrEqualTo(maxRobotSessionsPerCoordinator),
          );
        }

        // Beyond the ceiling, each new robot took the place of the least recently used idle session of that coordinator.
        expect(sessions.opened, hasLength(maxRobotSessionsPerCoordinator + 6));
        expect(sessions.closed, {0, 1, 2, 3, 4, 5});
        expect(tor.countsForTesting.places, maxRobotSessionsPerCoordinator);
      },
    );

    test(
      'takes, at the ceiling, only the place of a session of the same coordinator',
      () async {
        final held = _Held();
        final crowded = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        final gates = [Completer<void>(), Completer<void>()];
        // Session 0 is the one of robot 900 on the other coordinator, session 1 the one of robot 1 on the crowded one: both close slowly.
        sessions.closeGates[0] = gates[0].future;
        sessions.closeGates[1] = gates[1].future;
        final tor = transport(
          deadline: const Duration(seconds: 20),
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
              ? _socksRefusal(CommandReplyCode.hostUnreachable)
              : HttpClient(),
        );
        final crowdedOrigin = crowded.url('/').origin;
        // A request that is not retried leaves the session of robot 900 closing on the other coordinator.
        expect(
          await tor.send(
            _post(
              Uri.parse('http://127.0.0.1:1/api/robot/'),
              robot: _robot(900),
            ),
          ),
          _failsWith<CoordinatorUnreachable>(),
        );
        expect(sessions.closing, [0]);
        // The crowded coordinator reaches its ceiling, every place held by a request.
        final requests = [
          for (var robot = 1; robot <= maxRobotSessionsPerCoordinator; robot++)
            tor.send(_get(crowded.url('/held'), robot: _robot(robot))),
        ];
        await held.waiting(maxRobotSessionsPerCoordinator);

        // The closing session of the other coordinator gives it no place.
        expect(
          await tor.send(_get(crowded.url('/api/robot/'), robot: _robot(50))),
          _failsWith<CoordinatorTransportBusy>(),
        );
        expect(sessions.opened, hasLength(1 + maxRobotSessionsPerCoordinator));
        // One of its own sessions closing does: the new robot waits for it to close, then opens.
        final closingRobot = tor.closeRobotSessions(_robot(1));
        final newcomer = tor.send(
          _get(crowded.url('/api/robot/'), robot: _robot(51)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(sessions.closing, [0, 1]);
        expect(sessions.opened, hasLength(1 + maxRobotSessionsPerCoordinator));
        gates[1].complete();
        expect(await newcomer, isA<Ok<Object?, Failure>>());
        await closingRobot;
        expect(sessions.opened, hasLength(2 + maxRobotSessionsPerCoordinator));
        expect(
          tor.countsForTesting.placesAt[crowdedOrigin],
          maxRobotSessionsPerCoordinator,
        );
        expect(sessions.closed, {1});

        gates[0].complete();
        held.release();
        await Future.wait(requests);
      },
    );
  });

  group('the places of the robot sessions', () {
    for (final atTor in [true, false]) {
      final label = atTor
          ? 'Tor gives no session'
          : 'the HTTP client cannot be made';
      test('are given back by a session that fails to open: $label', () async {
        final server = await serve({'/api/robot/': _json('{}')});
        var failing = true;
        final tor = transport(
          placesPerCoordinator: maxRobotSessions,
          openSession: () async {
            if (failing && atTor) throw const SocketException('no Tor');
            return sessions.open();
          },
          createHttpClient: (_) {
            if (failing && !atTor) throw const SocketException('no client');
            return HttpClient();
          },
        );
        // More failed openings than there are places.
        for (var robot = 1; robot <= maxRobotSessions + 8; robot++) {
          final result = await tor.send(
            _get(server.url('/api/robot/'), robot: _robot(robot)),
          );
          expect(result, isA<Err<Object?, Failure>>());
        }
        // A session that Tor gave is closed when no client can be made for it.
        final failed = sessions.opened.length;
        expect(failed, atTor ? 0 : maxRobotSessions + 8);
        expect(sessions.closed, hasLength(failed));

        failing = false;
        // Every place is free again: as many robots as there are places get a session, and none is closed to make room.
        for (var robot = 100; robot < 100 + maxRobotSessions; robot++) {
          final result = await tor.send(
            _get(server.url('/api/robot/'), robot: _robot(robot)),
          );
          expect(result, isA<Ok<Object?, Failure>>());
        }
        expect(sessions.opened, hasLength(failed + maxRobotSessions));
        expect(sessions.closed, hasLength(failed));
      });
    }

    test(
      'go to a new session only once the session they are taken from is closed',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final gate = Completer<void>();
        sessions.closeGates[0] = gate.future;
        final tor = transport(placesPerCoordinator: maxRobotSessions);
        for (var robot = 1; robot <= maxRobotSessions; robot++) {
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(robot)));
        }

        // The session of robot 1, the least recently used, is closed to make room, and takes its time.
        final newcomer = tor.send(
          _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(sessions.closing, [0]);
        expect(sessions.opened, hasLength(maxRobotSessions));
        gate.complete();
        expect(await newcomer, isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(maxRobotSessions + 1));
        expect(sessions.closed, {0});
        expect(sessions.maxOpen, maxRobotSessions);
      },
    );

    test('are handed over once only by a session that is closing', () async {
      final held = _Held();
      final server = await serve({
        '/held': held.handle,
        '/api/robot/': _json('{}'),
      });
      final gate = Completer<void>();
      sessions.closeGates[0] = gate.future;
      final tor = transport(
        placesPerCoordinator: maxRobotSessions,
        deadline: const Duration(seconds: 20),
        // Session 0, the one of robot 1, never connects.
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
            ? _socksRefusal(CommandReplyCode.hostUnreachable)
            : HttpClient(),
      );
      // A request that is not retried leaves session 0 closing, slowly, and every other place is held by a request.
      expect(
        await tor.send(_post(server.url('/api/robot/'), robot: _robot(1))),
        _failsWith<CoordinatorUnreachable>(),
      );
      final requests = [
        for (var robot = 2; robot <= maxRobotSessions; robot++)
          tor.send(_get(server.url('/held'), robot: _robot(robot))),
      ];
      await held.waiting(maxRobotSessions - 1);
      expect(sessions.closing, [0]);
      expect(sessions.closed, isEmpty);

      // Two robots come: the first waits for the place of session 0, the second finds none.
      final first = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
      );
      final second = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 2)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.opened, hasLength(maxRobotSessions));
      gate.complete();

      expect(await first, isA<Ok<Object?, Failure>>());
      expect(await second, _failsWith<CoordinatorTransportBusy>());
      expect(sessions.opened, hasLength(maxRobotSessions + 1));
      expect(sessions.closed, {0});
      // The place counts once: the second robot now gets one only by closing the idle session of the first.
      expect(
        await tor.send(
          _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 2)),
        ),
        isA<Ok<Object?, Failure>>(),
      );
      expect(sessions.closed, {0, maxRobotSessions});
      expect(sessions.maxOpen, maxRobotSessions);
      held.release();
      await Future.wait(requests);
    });

    test('are handed over once only, even after closeRobotSessions', () async {
      final held = _Held();
      final server = await serve({
        '/held': held.handle,
        '/api/robot/': _json('{}'),
      });
      final gate = Completer<void>();
      sessions.closeGates[0] = gate.future;
      sessions.closeGates[1] = gate.future;
      final tor = transport(
        deadline: const Duration(seconds: 20),
        createHttpClient: (_) => _oneConnectionThenRefused(),
      );
      // The robot has two sessions, each held by a request.
      final requests = [
        for (var i = 0; i < 2; i++)
          tor.send(_get(server.url('/held'), robot: _robot(1))),
      ];
      await held.waiting(2).timeout(const Duration(seconds: 5));
      // Both close slowly, each with one of the two places of the robot.
      final firstClose = tor.closeRobotSessions(_robot(1));
      expect(
        await Future.wait(requests),
        everyElement(_failsWith<CoordinatorTransportFailed>()),
      );
      expect(sessions.closing, [0, 1]);

      // A request after the close takes the place of one of them, and waits for it to close.
      final first = tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // A second close drops it while it waits, and the next request takes the place of the other one, not the same one again.
      final secondClose = tor.closeRobotSessions(_robot(1));
      final second = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sessions.opened, hasLength(2));
      gate.complete();

      expect(await first, _failsWith<CoordinatorTransportFailed>());
      expect(await second, isA<Ok<Object?, Failure>>());
      await firstClose;
      await secondClose;
      // One session of the robot is open, and it holds exactly one place.
      final counts = tor.countsForTesting;
      expect(sessions.opened, hasLength(3));
      expect(sessions.closed, {0, 1});
      expect(counts.live, 1);
      expect(counts.places, 1);
      expect(counts.placesOf.values, [1]);
      held.release();
    });

    test('are not taken from an anonymous session that is closing', () async {
      final held = _Held();
      final server = await serve({
        '/held': held.handle,
        '/api/info/': _json('{}'),
        '/api/robot/': _json('{}'),
      });
      final gate = Completer<void>();
      sessions.closeGates[0] = gate.future;
      final tor = transport(
        placesPerCoordinator: maxRobotSessions,
        deadline: const Duration(seconds: 20),
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
            ? _socksRefusal(CommandReplyCode.hostUnreachable)
            : HttpClient(),
      );
      // The first anonymous session fails and closes slowly, and the read is retried on a second one.
      expect(
        await tor.send(_get(server.url('/api/info/'))),
        isA<Ok<Object?, Failure>>(),
      );
      expect(sessions.closing, [0]);
      expect(sessions.closed, isEmpty);
      final requests = [
        for (var robot = 1; robot <= maxRobotSessions; robot++)
          tor.send(_get(server.url('/held'), robot: _robot(robot))),
      ];
      await held.waiting(maxRobotSessions);

      // Every robot place is in use: the anonymous session that is closing has none to give.
      final newcomer = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(maxRobotSessions + 1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      gate.complete();

      expect(await newcomer, _failsWith<CoordinatorTransportBusy>());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.opened, hasLength(2 + maxRobotSessions));
      held.release();
      await Future.wait(requests);
    });
  });

  group('the count of the robot sessions', () {
    test(
      'holds through random requests, connection failures and closes',
      () async {
        final random = Random(41);
        final releases = <Completer<void>>[];
        final server = await serve({
          '/api/robot/': _json('{}'),
          '/held': (request) async {
            final release = Completer<void>();
            releases.add(release);
            await release.future;
            await _json('[]')(request);
          },
        });
        final tor = transport(
          placesPerCoordinator: maxRobotSessions,
          deadline: const Duration(seconds: 4),
          // A third of the sessions lose their coordinator after one connection.
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) % 3 == 0
              ? _oneConnectionThenRefused()
              : HttpClient(),
        );
        final requests = <Future<Object?>>[];
        for (var step = 0; step < 600; step++) {
          final robot = _robot(1 + random.nextInt(45));
          switch (random.nextInt(20)) {
            case < 8:
              requests.add(
                tor.send(_get(server.url('/api/robot/'), robot: robot)),
              );
            case < 13:
              requests.add(tor.send(_get(server.url('/held'), robot: robot)));
            case < 16:
              if (releases.isNotEmpty) {
                releases.removeAt(random.nextInt(releases.length)).complete();
              }
            case < 19:
              unawaited(tor.closeRobotSessions(robot));
            default:
              if (random.nextInt(6) == 0) unawaited(tor.closeSessions());
          }
          await Future<void>.delayed(
            random.nextInt(3) == 0
                ? Duration(milliseconds: random.nextInt(3))
                : Duration.zero,
          );
        }
        for (final release in releases) {
          release.complete();
        }
        releases.clear();
        await Future.wait(requests).timeout(const Duration(seconds: 20));
        await tor.closeSessions();
        await Future<void>.delayed(const Duration(milliseconds: 300));

        // Never more sessions than places, and none left open.
        expect(sessions.opened.length, greaterThan(maxRobotSessions));
        expect(sessions.maxOpen, lessThanOrEqualTo(maxRobotSessions));
        expect(sessions.closed, hasLength(sessions.opened.length));
        // Every place is free, and no more: as many robots as there are places hold a request, and one more finds none.
        final held = [
          for (var robot = 200; robot < 200 + maxRobotSessions; robot++)
            tor.send(_get(server.url('/held'), robot: _robot(robot))),
        ];
        final watch = Stopwatch()..start();
        while (releases.length < maxRobotSessions &&
            watch.elapsed < const Duration(seconds: 3)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(releases, hasLength(maxRobotSessions));
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(300))),
          _failsWith<CoordinatorTransportBusy>(),
        );
        for (final release in releases) {
          release.complete();
        }
        expect(
          await Future.wait(held),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );
  });

  group('the counts of the places', () {
    test('hold after every step of a random run over three coordinators', () async {
      final random = Random(43);
      final releases = <Completer<void>>[];
      Future<void> answer(HttpRequest request) async {
        if (request.uri.path == '/held') {
          final release = Completer<void>();
          releases.add(release);
          await release.future;
        }
        await _json('{}')(request);
      }

      final servers = [
        for (var i = 0; i < 3; i++)
          await serve({'/api/robot/': answer, '/held': answer}),
      ];
      // A fifth of the sessions never finish closing, and another fifth take up to 300 ms.
      sessions.closeGateOf = (index) => switch (index % 5) {
        0 => Completer<void>().future,
        1 => Future<void>.delayed(Duration(milliseconds: index * 37 % 300)),
        _ => Future<void>.value(),
      };
      var opens = 0;
      final tor = transport(
        deadline: const Duration(seconds: 1),
        closeTimeout: const Duration(milliseconds: 200),
        // Some openings never complete, and some complete after they were given up.
        openSession: () => switch (opens++ % 19) {
          5 => Completer<TorSession>().future,
          11 => Future<TorSession>.delayed(
            const Duration(milliseconds: 1500),
            sessions.open,
          ),
          _ => sessions.open(),
        },
        // A third of the sessions lose their coordinator after one connection.
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) % 3 == 0
            ? _oneConnectionThenRefused()
            : HttpClient(),
      );
      final violations = <String>[];
      void check(int step) {
        final counts = tor.countsForTesting;
        final places = counts.placesOf.values;
        final sum = places.fold(0, (total, value) => total + value);
        if (counts.places != sum ||
            counts.places > maxRobotSessions ||
            places.any(
              (value) =>
                  value <= 0 || value > maxSessionsPerRobotAndCoordinator,
            ) ||
            counts.placesAt.values.any(
              (value) => value > maxRobotSessionsPerCoordinator,
            )) {
          violations.add(
            'step $step: ${counts.places} places, per robot $places, per coordinator ${counts.placesAt.values}',
          );
        }
      }

      final requests = <Future<Object?>>[];
      final firstOrigin = servers[0].url('/').origin;
      // The run starts at the ceiling of the first coordinator, whatever the speed of the machine: thirty robots ask it at once, and their places are taken before any of them is answered.
      for (var robot = 1; robot <= 30; robot++) {
        requests.add(
          tor.send(_get(servers[0].url('/held'), robot: _robot(robot))),
        );
      }
      check(-1);
      final atCeiling = tor.countsForTesting.placesAt[firstOrigin];
      for (var step = 0; step < 1500; step++) {
        final robot = _robot(1 + random.nextInt(50));
        // Most requests go to the first coordinator, so that its ceiling is reached.
        final server = random.nextInt(10) < 6
            ? servers[0]
            : servers[1 + random.nextInt(2)];
        switch (random.nextInt(20)) {
          case < 7:
            requests.add(
              tor.send(_get(server.url('/api/robot/'), robot: robot)),
            );
          case < 12:
            requests.add(tor.send(_get(server.url('/held'), robot: robot)));
          case 12:
            requests.add(
              tor.send(_post(server.url('/api/robot/'), robot: robot)),
            );
          case < 16:
            if (releases.isNotEmpty) {
              releases.removeAt(random.nextInt(releases.length)).complete();
            }
          case < 19:
            unawaited(tor.closeRobotSessions(robot));
          default:
            if (random.nextInt(8) == 0) unawaited(tor.closeSessions());
        }
        check(step);
        await Future<void>.delayed(
          random.nextInt(3) == 0
              ? Duration(milliseconds: random.nextInt(4))
              : Duration.zero,
        );
        check(step);
      }
      for (final release in releases) {
        release.complete();
      }
      releases.clear();
      await Future.wait(requests).timeout(const Duration(seconds: 30));
      await tor.closeSessions();
      // The openings that complete late, and the closes they start, end within this.
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(violations, isEmpty, reason: violations.take(5).join('\n'));
      expect(atCeiling, maxRobotSessionsPerCoordinator);
      final counts = tor.countsForTesting;
      expect(counts.places, 0);
      expect(counts.placesOf, isEmpty);
      expect(counts.live, 0);
      expect(counts.waiting, 0);
      expect(counts.robotsWithRequests, 0);
      expect(counts.sessionsGivenUp, greaterThan(0));
    });
  });

  group('a session that never finishes closing', () {
    test(
      'fails the request that waits for its place, and gives the place back',
      () async {
        final held = _Held();
        final server = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        // The session of robot 1 never finishes closing.
        sessions.closeGates[0] = Completer<void>().future;
        final tor = transport(
          placesPerCoordinator: maxRobotSessions,
          deadline: const Duration(seconds: 20),
          closeTimeout: const Duration(milliseconds: 300),
        );
        Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> ask(
          int robot, {
          String path = '/api/robot/',
        }) => tor.send(_get(server.url(path), robot: _robot(robot)));
        for (var robot = 1; robot <= maxRobotSessions; robot++) {
          expect(await ask(robot), isA<Ok<Object?, Failure>>());
        }
        final watch = Stopwatch()..start();

        // The newcomer takes the place of robot 1, whose session does not close.
        final first = await ask(maxRobotSessions + 1);

        expect(first, _failsWith<CoordinatorTransportBusy>());
        expect(
          watch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 250)),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(sessions.closing, [0]);
        // No session opened in a place that was not free.
        expect(sessions.opened, hasLength(maxRobotSessions));

        // The place is free at once for the next request, without closing another session.
        expect(await ask(maxRobotSessions + 1), isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(maxRobotSessions + 1));
        expect(sessions.closing, [0]);
        // And every place is usable: as many robots as there are places hold a request at the same time, and one more finds none.
        final requests = [
          for (var robot = 2; robot <= maxRobotSessions + 1; robot++)
            ask(robot, path: '/held'),
        ];
        await held.waiting(maxRobotSessions);
        expect(
          await ask(maxRobotSessions + 2),
          _failsWith<CoordinatorTransportBusy>(),
        );
        expect(sessions.opened, hasLength(maxRobotSessions + 1));
        held.release();
        expect(
          await Future.wait(requests),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );

    for (final closeRobot in [false, true]) {
      final label = closeRobot
          ? 'closeRobotSessions of its robot'
          : 'closeSessions';
      test(
        'fails, rather than busy, the request that waits for its place when $label runs',
        () async {
          final first = await serve({'/api/robot/': _json('{}')});
          final second = await serve({'/api/robot/': _json('{}')});
          // The session of robot 1 never finishes closing.
          sessions.closeGates[0] = Completer<void>().future;
          final tor = transport(
            deadline: const Duration(seconds: 20),
            closeTimeout: const Duration(milliseconds: 300),
          );
          // The robots are spread over two coordinators, so that only the bound of all the robot sessions applies.
          Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> ask(
            int robot,
          ) => tor.send(
            _get(
              (robot.isEven ? first : second).url('/api/robot/'),
              robot: _robot(robot),
            ),
          );
          for (var robot = 1; robot <= maxRobotSessions; robot++) {
            expect(await ask(robot), isA<Ok<Object?, Failure>>());
          }
          const newcomer = maxRobotSessions + 1;

          // The newcomer takes the place of robot 1, and waits for its session to close.
          final waiting = ask(newcomer);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(sessions.closing, [0]);
          final closing = closeRobot
              ? tor.closeRobotSessions(_robot(newcomer))
              : tor.closeSessions();

          // The session of robot 1 is given up after the close timeout, but the request was stopped by the close.
          expect(await waiting, _failsWith<CoordinatorTransportFailed>());
          await closing.timeout(const Duration(seconds: 5));
          final counts = tor.countsForTesting;
          expect(counts.places, closeRobot ? maxRobotSessions - 1 : 0);
          expect(
            counts.placesOf.values.fold(0, (sum, places) => sum + places),
            counts.places,
          );
          expect(
            counts.placesOf.keys.map((key) => key.robot),
            isNot(contains(_robot(newcomer))),
          );
          expect(sessions.opened, hasLength(maxRobotSessions));
        },
      );
    }

    test('leaves no place to the request whose wait for it timed out', () async {
      final first = await serve({'/api/robot/': _json('{}')});
      final second = await serve({'/api/robot/': _json('{}')});
      // The session of robot 1 never finishes closing.
      sessions.closeGates[0] = Completer<void>().future;
      final tor = transport(
        deadline: const Duration(seconds: 20),
        closeTimeout: const Duration(milliseconds: 300),
      );
      // The robots are spread over two coordinators, so that only the bound of all the robot sessions applies.
      Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> ask(
        int robot,
      ) => tor.send(
        _get(
          (robot.isEven ? first : second).url('/api/robot/'),
          robot: _robot(robot),
        ),
      );
      for (var robot = 1; robot <= maxRobotSessions; robot++) {
        expect(await ask(robot), isA<Ok<Object?, Failure>>());
      }

      // The newcomer takes the place of robot 1, whose session is given up.
      expect(
        await ask(maxRobotSessions + 1),
        _failsWith<CoordinatorTransportBusy>(),
      );

      // Neither the newcomer nor robot 1 holds a place any more, and the others keep theirs.
      final counts = tor.countsForTesting;
      expect(counts.places, maxRobotSessions - 1);
      expect(
        counts.placesOf.values.fold(0, (sum, places) => sum + places),
        maxRobotSessions - 1,
      );
      final robots = counts.placesOf.keys.map((key) => key.robot).toSet();
      expect(robots, isNot(contains(_robot(maxRobotSessions + 1))));
      expect(robots, isNot(contains(_robot(1))));
      expect(counts.sessionsGivenUp, 1);
    });

    test(
      'does not keep a request waiting when no client could be made for it',
      () async {
        sessions.closeGates[0] = Completer<void>().future;
        final tor = transport(
          closeTimeout: const Duration(milliseconds: 300),
          createHttpClient: (_) => throw const SocketException('no client'),
        );
        final watch = Stopwatch()..start();

        final result = await tor.send(
          _get(Uri.parse('http://127.0.0.1:1/api/robot/'), robot: _robot(1)),
        );

        // Answered once the session is given up, well before the deadline of five seconds, and the place is free.
        expect(result, _failsWith<CoordinatorTransportFailed>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
        expect(sessions.closing, [0]);
        expect(tor.countsForTesting.places, 0);
        expect(tor.countsForTesting.sessionsGivenUp, 1);
      },
    );

    test('does not keep closeSessions waiting for an anonymous one', () async {
      final server = await serve({'/api/info/': _json('{}')});
      sessions.closeGates[0] = Completer<void>().future;
      final tor = transport(closeTimeout: const Duration(milliseconds: 300));
      expect(
        await tor.send(_get(server.url('/api/info/'))),
        isA<Ok<Object?, Failure>>(),
      );
      final watch = Stopwatch()..start();

      await tor.closeSessions().timeout(const Duration(seconds: 3));

      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(sessions.closing, [0]);
      expect(sessions.closed, isEmpty);
      expect(tor.countsForTesting.live, 0);
      expect(tor.countsForTesting.sessionsGivenUp, 1);
      // The next read opens a new session.
      expect(
        await tor.send(_get(server.url('/api/info/'))),
        isA<Ok<Object?, Failure>>(),
      );
      expect(sessions.opened, hasLength(2));
    });

    test('does not keep closeRobotSessions or closeSessions waiting', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      sessions.closeGates[0] = Completer<void>().future;
      sessions.closeGates[1] = Completer<void>().future;
      final tor = transport(closeTimeout: const Duration(milliseconds: 300));
      await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));

      await tor
          .closeRobotSessions(_robot(1))
          .timeout(const Duration(seconds: 5));

      // The robot gets a new session, which does not close either.
      expect(
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
        isA<Ok<Object?, Failure>>(),
      );
      await tor.closeSessions().timeout(const Duration(seconds: 5));
      expect(sessions.closing, [0, 1]);
      expect(
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
        isA<Ok<Object?, Failure>>(),
      );
      expect(sessions.opened, hasLength(3));
    });
  });

  group('a Tor session that never finishes opening', () {
    test(
      'answers in time, releases the requests that joined it, and gives the place back',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        var hanging = true;
        final tor = transport(
          deadline: const Duration(milliseconds: 500),
          openSession: () =>
              hanging ? Completer<TorSession>().future : sessions.open(),
        );
        final watch = Stopwatch()..start();

        final first = tor.send(
          _get(server.url('/api/robot/'), robot: _robot(1)),
        );
        // A second request of the same robot joins the same opening a little later.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final joined = tor.send(
          _get(server.url('/api/robot/'), robot: _robot(1)),
        );

        expect(await first, _failsWith<CoordinatorTimedOut>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        // The opening is given up at the deadline of the request that started it, before the deadline of the one that joined it, which would have answered that it timed out.
        expect(await joined, _failsWith<CoordinatorUnreachable>());
        final counts = tor.countsForTesting;
        expect(counts.places, 0);
        expect(counts.placesOf, isEmpty);
        expect(counts.waiting, 0);
        expect(counts.robotsWithRequests, 0);

        hanging = false;
        expect(
          await tor.send(_get(server.url('/api/robot/'), robot: _robot(1))),
          isA<Ok<Object?, Failure>>(),
        );
        expect(tor.countsForTesting.places, 1);
      },
    );

    test(
      'is no longer waited for after a close, and its place is free once its request has failed',
      () async {
        final tor = transport(
          deadline: const Duration(seconds: 20),
          openSession: () => Completer<TorSession>().future,
        );
        final url = Uri.parse('http://127.0.0.1:1/api/robot/');
        final watch = Stopwatch()..start();
        final first = tor.send(_get(url, robot: _robot(1)));
        final second = tor.send(_get(url, robot: _robot(2)));
        final anonymous = tor.send(_get(url));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(tor.countsForTesting.places, 2);

        await tor.closeRobotSessions(_robot(1));

        expect(await first, _failsWith<CoordinatorTransportFailed>());
        expect(tor.countsForTesting.places, 1);
        await tor.closeSessions();
        expect(await second, _failsWith<CoordinatorTransportFailed>());
        expect(await anonymous, _failsWith<CoordinatorTransportFailed>());
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        final counts = tor.countsForTesting;
        expect(counts.places, 0);
        expect(counts.waiting, 0);
        expect(counts.robotsWithRequests, 0);
      },
    );

    test(
      'does not keep the places: thirty-two of them, then Tor works again',
      () async {
        final held = _Held();
        final first = await serve({
          '/held': held.handle,
          '/api/robot/': _json('{}'),
        });
        final second = await serve({'/held': held.handle});
        var hanging = true;
        final tor = transport(
          deadline: const Duration(seconds: 2),
          openSession: () =>
              hanging ? Completer<TorSession>().future : sessions.open(),
        );
        // The robots are spread over two coordinators, so that only the bound of all the robot sessions applies.
        Uri url(int robot, String path) =>
            (robot.isEven ? first : second).url(path);

        final hung = await Future.wait([
          for (var robot = 1; robot <= maxRobotSessions; robot++)
            tor.send(_get(url(robot, '/held'), robot: _robot(robot))),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(hung, everyElement(_failsWith<CoordinatorTimedOut>()));
        expect(tor.countsForTesting.places, 0);
        // Every place is free again: as many new robots as there are places hold a request at the same time, and one more finds none.
        hanging = false;
        final requests = [
          for (var robot = 100; robot < 100 + maxRobotSessions; robot++)
            tor.send(_get(url(robot, '/held'), robot: _robot(robot))),
        ];
        await held.waiting(maxRobotSessions);
        expect(
          await tor.send(_get(first.url('/api/robot/'), robot: _robot(200))),
          _failsWith<CoordinatorTransportBusy>(),
        );
        held.release();
        expect(
          await Future.wait(requests),
          everyElement(isA<Ok<Object?, Failure>>()),
        );
      },
    );

    test('leaves no request waiting for it once it is given up', () async {
      final tor = transport(
        deadline: const Duration(milliseconds: 300),
        openSession: () => Completer<TorSession>().future,
      );
      final url = Uri.parse('http://127.0.0.1:1/api/robot/');

      final requests = [
        for (var i = 0; i < 200; i++) tor.send(_get(url, robot: _robot(1))),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tor.countsForTesting.waiting, 200);
      final results = await Future.wait(requests);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Each request is answered by its own deadline or by the opening given up at the same moment, whichever comes first.
      expect(
        results,
        everyElement(
          anyOf(
            _failsWith<CoordinatorTimedOut>(),
            _failsWith<CoordinatorUnreachable>(),
          ),
        ),
      );
      final counts = tor.countsForTesting;
      expect(counts.waiting, 0);
      expect(counts.robotsWithRequests, 0);
      expect(counts.places, 0);
    });

    test('closes a session that opens after it was given up, unused', () async {
      final raw = await rawServer((socket) async {
        socket.add(_jsonHead(2));
        socket.add(utf8.encode('{}'));
        await socket.flush();
      });
      final opening = Completer<TorSession>();
      final tor = transport(
        deadline: const Duration(milliseconds: 300),
        openSession: () => opening.future,
      );

      final result = await tor.send(
        _get(raw.url('/api/robot/'), robot: _robot(1)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tor.countsForTesting.places, 0);
      opening.complete(await sessions.open());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(result, _failsWith<CoordinatorTimedOut>());
      expect(sessions.closed, {0});
      expect(raw.connections, 0);
      expect(tor.countsForTesting.live, 0);
      expect(tor.countsForTesting.places, 0);
    });
  });

  group('the retry log', () {
    test('names neither the coordinator, nor the robot, nor a header', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final identity = _identity(1);
      final tor = transport(
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
            ? _socksRefusal(CommandReplyCode.hostUnreachable)
            : HttpClient(),
      );
      final printed = <String>[];
      final print = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      final Result<CoordinatorResponse, CoordinatorTransportFailure> result;
      try {
        result = await tor.send(
          _get(
            server.url('/api/robot/'),
            headers: {
              'Accept': 'application/json',
              'Authorization': identity.authorizationHeader(),
              'X-Label': 'a-header-value',
            },
            robot: identity.sessionKey,
          ),
        );
      } finally {
        debugPrint = print;
      }

      expect(result, isA<Ok<Object?, Failure>>());
      expect(sessions.opened, hasLength(2));
      // One line for the retry, and nothing after its fixed text but the padding of the logger.
      final retry = printed.where((line) => line.contains('retrying'));
      expect(retry, hasLength(1));
      expect(
        retry.single,
        matches(
          RegExp(
            r'P2P coordinator connection failed \(hostUnreachable\), retrying on a new Tor session \(1/2\)(\x1B\[0m)?\s*$',
          ),
        ),
      );
      for (final line in printed) {
        for (final secret in [
          '127.0.0.1',
          'http:',
          '/api/robot',
          identity.tokenSha256Base91,
          identity.hashId.hex,
          identity.nickname,
          'Token ',
          'Authorization',
          'a-header-value',
          'X-Label',
          'RobotSessionKey',
        ]) {
          expect(line, isNot(contains(secret)), reason: secret);
        }
      }
    });
  });

  group('the log of a session given up', () {
    test(
      'counts them, and names neither the coordinator, nor the robot, nor the session',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final identity = _identity(1);
        // None of the sessions of this test finishes closing.
        for (var index = 0; index < 3; index++) {
          sessions.closeGates[index] = Completer<void>().future;
        }
        final tor = transport(closeTimeout: const Duration(milliseconds: 200));
        final printed = <String>[];
        final print = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) printed.add(message);
        };
        try {
          for (var round = 0; round < 3; round++) {
            final result = await tor.send(
              _get(
                server.url('/api/robot/'),
                headers: {
                  'Accept': 'application/json',
                  'Authorization': identity.authorizationHeader(),
                },
                robot: identity.sessionKey,
              ),
            );
            expect(result, isA<Ok<Object?, Failure>>());
            await tor.closeRobotSessions(identity.sessionKey);
          }
        } finally {
          debugPrint = print;
        }

        expect(tor.countsForTesting.sessionsGivenUp, 3);
        expect(tor.countsForTesting.places, 0);
        // The first and the second are logged; the third waits for the fourth.
        final givenUp = printed.where((line) => line.contains('given up'));
        expect(givenUp, hasLength(2));
        for (final (line, count) in [(givenUp.first, 1), (givenUp.last, 2)]) {
          expect(
            line,
            matches(
              RegExp(
                'P2P Tor session given up: it did not close in time \\($count so far\\)(\\x1B\\[0m)?\\s*\$',
              ),
            ),
          );
        }
        for (final line in printed) {
          for (final secret in [
            '127.0.0.1',
            'http:',
            '/api/robot',
            'TorSession',
            'TorProxyEndpoint',
            identity.tokenSha256Base91,
            identity.hashId.hex,
            identity.nickname,
            'Token ',
            'Authorization',
            'RobotSessionKey',
          ]) {
            expect(line, isNot(contains(secret)), reason: secret);
          }
        }
      },
    );
  });

  group('headers', () {
    test(
      'that cannot be written as they are fail before any session',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport();

        for (final headers in const [
          {'Authorization': 'Token abc | Public café'},
          {'Authorization': 'Token abc\tdef'},
          {'Authorization': 'Token abc\r\nX-Injected: 1'},
          {'Authorization': 'Token abc\n'},
          {'Authorization': 'Token \u0000'},
          {'Authorization': 'Token \u007f'},
          {'Authorization': 'Token \u{1F916}'},
          {'X-Bad Name': 'value'},
          {'X-Bad:Name': 'value'},
          {'X-Naïve': 'value'},
          {'': 'value'},
        ]) {
          final result = await tor.send(
            _get(server.url('/api/robot/'), headers: headers, robot: _robot(1)),
          );

          expect(
            result,
            _failsWith<CoordinatorTransportFailed>(),
            reason: '${headers.keys}',
          );
        }
        // The same check applies to an anonymous request.
        expect(
          await tor.send(
            _get(server.url('/api/robot/'), headers: const {'Accept': 'café'}),
          ),
          _failsWith<CoordinatorTransportFailed>(),
        );
        expect(sessions.opened, isEmpty);
        expect(server.received, isEmpty);
      },
    );

    test(
      'that are printable ASCII go through, whatever the characters',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        const value = r''' !"#$%&'()*+,-./09:;<=>?@AZ[\]^_`az{|}~''';

        final result = await transport().send(
          _get(
            server.url('/api/robot/'),
            headers: const {'X-Every-Kind': value},
            robot: _robot(1),
          ),
        );

        expect(result, isA<Ok<Object?, Failure>>());
        expect(server.received.single.value('x-every-kind'), value.trim());
      },
    );

    test(
      'go through up to $maxHeaderLength characters, name or value',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final name = 'X-${'n' * (maxHeaderLength - 2)}';
        final value = 'v' * maxHeaderLength;

        final result = await transport().send(
          _get(
            server.url('/api/robot/'),
            headers: {name: value},
            robot: _robot(1),
          ),
        );

        expect(result, isA<Ok<Object?, Failure>>());
        expect(name.length, maxHeaderLength);
        expect(server.received.single.value(name), value);
      },
    );

    test('longer than that fail before any session', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final tor = transport();

      for (final headers in [
        {'Authorization': 'v' * (maxHeaderLength + 1)},
        {'X-${'n' * (maxHeaderLength - 1)}': 'value'},
        {'Accept': 'application/json', 'X-Long': 'v' * 200000},
      ]) {
        final result = await tor.send(
          _get(server.url('/api/robot/'), headers: headers, robot: _robot(1)),
        );

        expect(result, _failsWith<CoordinatorTransportFailed>());
      }
      // The same check applies to an anonymous request.
      expect(
        await tor.send(
          _get(
            server.url('/api/robot/'),
            headers: {'X-Long': 'v' * (maxHeaderLength + 1)},
          ),
        ),
        _failsWith<CoordinatorTransportFailed>(),
      );
      expect(sessions.opened, isEmpty);
      expect(server.received, isEmpty);
    });

    test('go through up to $maxTotalHeaderLength characters in all', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      // Two headers, each within the limit of one header, that bring the names and values to the total limit exactly.
      final headers = {
        'X-A': 'a' * (maxTotalHeaderLength ~/ 2 - 3),
        'X-B': 'b' * (maxTotalHeaderLength ~/ 2 - 3),
      };

      final result = await transport().send(
        _get(server.url('/api/robot/'), headers: headers, robot: _robot(1)),
      );

      expect(result, isA<Ok<Object?, Failure>>());
      expect(
        headers.entries.fold(
          0,
          (sum, header) => sum + header.key.length + header.value.length,
        ),
        maxTotalHeaderLength,
      );
      expect(server.received.single.value('x-a'), headers['X-A']);
      expect(server.received.single.value('x-b'), headers['X-B']);
    });

    test('more than that in all fail before any session', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final tor = transport();
      final oneOver = {
        'X-A': 'a' * (maxTotalHeaderLength ~/ 2 - 3),
        'X-B': 'b' * (maxTotalHeaderLength ~/ 2 - 2),
      };

      for (final headers in [
        oneOver,
        // A hundred headers that are each within the limit of one header.
        {for (var i = 0; i < 100; i++) 'X-H$i': 'v' * 16000},
      ]) {
        final result = await tor.send(
          _get(server.url('/api/robot/'), headers: headers, robot: _robot(1)),
        );

        expect(result, _failsWith<CoordinatorTransportFailed>());
      }
      // The same check applies to an anonymous request.
      expect(
        await tor.send(_get(server.url('/api/robot/'), headers: oneOver)),
        _failsWith<CoordinatorTransportFailed>(),
      );
      expect(sessions.opened, isEmpty);
      expect(server.received, isEmpty);
    });

    test('that dart:io refuses fail at once, without a retry', () async {
      final tor = transport(
        createHttpClient: (_) => HttpClient()
          ..connectionFactory = (uri, proxyHost, proxyPort) async =>
              throw const FormatException(
                'Invalid HTTP header field value: "Token a-credential"',
              ),
      );

      final result = await tor.send(
        _get(Uri.parse('http://127.0.0.1:1/api/robot/'), robot: _robot(1)),
      );

      expect(result, _failsWith<CoordinatorTransportFailed>());
      expect(sessions.opened, hasLength(1));
    });
  });

  group('closeRobotSessions', () {
    test('closes the sessions of that robot only', () async {
      final first = await serve({'/api/robot/': _json('{}')});
      final second = await serve({'/api/robot/': _json('{}')});
      final tor = transport();
      // Sessions 0 and 1: robot 1 on both coordinators; 2: robot 2; 3: anonymous.
      await tor.send(_get(first.url('/api/robot/'), robot: _robot(1)));
      await tor.send(_get(second.url('/api/robot/'), robot: _robot(1)));
      await tor.send(_get(first.url('/api/robot/'), robot: _robot(2)));
      await tor.send(_get(first.url('/api/robot/')));

      await tor.closeRobotSessions(_robot(1));

      expect(sessions.closed, {0, 1});
      await tor.send(_get(first.url('/api/robot/'), robot: _robot(2)));
      await tor.send(_get(first.url('/api/robot/')));
      expect(sessions.opened, hasLength(4));
      // The robot can still be used: its next request opens a new session.
      final result = await tor.send(
        _get(first.url('/api/robot/'), robot: _robot(1)),
      );
      expect(result, isA<Ok<Object?, Failure>>());
      expect(sessions.opened, hasLength(5));
      expect(sessions.closed, {0, 1});
    });

    test(
      'forgets the sessions of that robot: its next request, even one that is never retried, opens a new one',
      () async {
        final server = await serve({'/api/robot/': _json('{}')});
        final tor = transport();
        await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));

        await tor.closeRobotSessions(_robot(1));
        // A `GET` sent on the closed session would fail to connect and be retried on a new one, which would hide a session left behind: a `POST` is not retried.
        final result = await tor.send(
          _post(server.url('/api/robot/'), robot: _robot(1)),
        );

        expect(result, isA<Ok<Object?, Failure>>());
        expect(sessions.opened, hasLength(2));
        expect(sessions.closed, {0});
      },
    );

    test('stops a request on a session that a connection failure replaced', () async {
      final release = Completer<void>();
      final arrivals = [Completer<void>(), Completer<void>()];
      var arrived = 0;
      final server = await serve({
        '/held': _held(
          release.future,
          arrived: () => arrivals[arrived++].complete(),
        ),
      });
      final tor = transport(
        createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
            ? _oneConnectionThenRefused()
            : HttpClient(),
      );
      CoordinatorRequest request() => _get(
        server.url('/held'),
        headers: {
          'Accept': 'application/json',
          'Authorization': _identity(1).authorizationHeader(),
        },
        robot: _robot(1),
      );

      // The first request is in flight on session 0.
      final first = tor.send(request());
      await arrivals[0].future;
      // The second is refused on session 0, which is replaced by session 1, where it waits for its answer.
      final second = tor.send(request());
      await arrivals[1].future;
      expect(sessions.opened, hasLength(2));
      expect(sessions.closed, isEmpty);

      await tor.closeRobotSessions(_robot(1));

      // Both sessions are closed, the replaced one included, and both requests fail without opening another.
      expect(sessions.closed, {0, 1});
      expect(await second, _failsWith<CoordinatorTransportFailed>());
      expect(await first, _failsWith<CoordinatorTransportFailed>());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.opened, hasLength(2));
      // The credential went out twice, and never again after the sessions were closed.
      expect(server.received, hasLength(2));
      release.complete();
    });

    test('lets the requests the robot starts afterwards through', () async {
      final release = Completer<void>();
      final arrived = Completer<void>();
      final server = await serve({
        '/held': _held(release.future, arrived: arrived.complete),
        '/api/robot/': _json('{}'),
      });
      final tor = transport();
      final pending = tor.send(_get(server.url('/held'), robot: _robot(1)));
      await arrived.future;

      // The new request starts while the old one is still failing.
      final closing = tor.closeRobotSessions(_robot(1));
      final next = tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      await closing;

      expect(await pending, _failsWith<CoordinatorTransportFailed>());
      expect(await next, isA<Ok<Object?, Failure>>());
      expect(sessions.opened, hasLength(2));
      expect(sessions.closed, {0});
      release.complete();
    });

    test('leaves the running requests of another robot alone', () async {
      final release = Completer<void>();
      final arrived = Completer<void>();
      final server = await serve({
        '/held': _held(release.future, arrived: arrived.complete),
      });
      final tor = transport();
      final other = tor.send(_get(server.url('/held'), robot: _robot(2)));
      await arrived.future;

      await tor.closeRobotSessions(_robot(1));
      release.complete();

      expect(await other, isA<Ok<Object?, Failure>>());
      expect(sessions.closed, isEmpty);
    });

    test('completes for a robot that has no session', () async {
      final tor = transport();

      await tor.closeRobotSessions(_robot(1));

      expect(sessions.opened, isEmpty);
    });

    test('fails a request in progress without opening a new session', () async {
      final arrived = Completer<void>();
      final server = await serve({
        '/api/robot/': (request) {
          arrived.complete();
          return Completer<void>().future;
        },
      });
      final tor = transport();
      final watch = Stopwatch()..start();

      final pending = tor.send(
        _get(server.url('/api/robot/'), robot: _robot(1)),
      );
      await arrived.future;
      await tor.closeRobotSessions(_robot(1));
      final result = await pending;

      expect(result, _failsWith<CoordinatorTransportFailed>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(sessions.opened, hasLength(1));
      expect(sessions.closed, {0});
    });

    test('closes a session that finishes opening afterwards, unused', () async {
      final raw = await rawServer((socket) async {
        socket.add(_jsonHead(2));
        socket.add(utf8.encode('{}'));
        await socket.flush();
      });
      final opening = Completer<TorSession>();
      final tor = transport(openSession: () => opening.future);

      final pending = tor.send(_get(raw.url('/api/robot/'), robot: _robot(1)));
      await Future<void>.delayed(Duration.zero);
      await tor.closeRobotSessions(_robot(1));
      opening.complete(await sessions.open());

      expect(await pending, _failsWith<CoordinatorTransportFailed>());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.closed, {0});
      expect(raw.connections, 0);
    });
  });

  group('closeSessions', () {
    test(
      'closes a session that a connection failure replaced, and stops its request',
      () async {
        final release = Completer<void>();
        final arrivals = [Completer<void>(), Completer<void>()];
        var arrived = 0;
        final server = await serve({
          '/held': _held(
            release.future,
            arrived: () => arrivals[arrived++].complete(),
          ),
        });
        final tor = transport(
          createHttpClient: (endpoint) => _Sessions.indexOf(endpoint) == 0
              ? _oneConnectionThenRefused()
              : HttpClient(),
        );

        final first = tor.send(_get(server.url('/held')));
        await arrivals[0].future;
        final second = tor.send(_get(server.url('/held')));
        await arrivals[1].future;
        expect(sessions.opened, hasLength(2));

        await tor.closeSessions();

        expect(sessions.closed, {0, 1});
        expect(await first, _failsWith<CoordinatorTransportFailed>());
        expect(await second, _failsWith<CoordinatorTransportFailed>());
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(sessions.opened, hasLength(2));
        expect(server.received, hasLength(2));
        release.complete();
      },
    );

    test('closes the sessions of the robots too', () async {
      final server = await serve({'/api/robot/': _json('{}')});
      final tor = transport();
      await tor.send(_get(server.url('/api/robot/')));
      await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      await tor.send(_get(server.url('/api/robot/'), robot: _robot(2)));

      await tor.closeSessions();

      expect(sessions.closed, {0, 1, 2});
      await tor.send(_get(server.url('/api/robot/'), robot: _robot(1)));
      expect(sessions.opened, hasLength(4));
    });

    test(
      'closes every session, and the next request opens a new one',
      () async {
        final first = await serve({'/api/info/': _json('{}')});
        final second = await serve({'/api/info/': _json('{}')});
        final tor = transport();
        await tor.send(_get(first.url('/api/info/')));
        await tor.send(_get(second.url('/api/info/')));

        await tor.closeSessions();

        expect(sessions.closed, {0, 1});
        final result = await tor.send(_get(first.url('/api/info/')));
        expect(
          result,
          isA<Ok<CoordinatorResponse, CoordinatorTransportFailure>>(),
        );
        expect(sessions.opened, hasLength(3));
      },
    );

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

    test('closes a session that finishes opening afterwards, unused', () async {
      final raw = await rawServer((socket) async {
        socket.add(_jsonHead(2));
        socket.add(utf8.encode('{}'));
        await socket.flush();
      });
      final opening = Completer<TorSession>();
      final tor = transport(openSession: () => opening.future);

      final pending = tor.send(_get(raw.url('/api/info/')));
      await Future<void>.delayed(Duration.zero);
      await tor.closeSessions();
      opening.complete(await sessions.open());

      expect(await pending, _failsWith<CoordinatorTransportFailed>());
      // The request is answered at the close, before the late session opens: that session is closed once it arrives.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sessions.closed, {0});
      expect(raw.connections, 0);
    });
  });
}

Matcher _failsWith<F extends CoordinatorTransportFailure>() =>
    isA<Err<CoordinatorResponse, CoordinatorTransportFailure>>().having(
      (err) => err.failure,
      'failure',
      isA<F>(),
    );
