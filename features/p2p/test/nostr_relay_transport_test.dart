import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bull_tor/tor.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:p2p/src/data/tor_coordinator_transport.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:socks5_proxy/enums.dart';
import 'package:socks5_proxy/exceptions.dart';
import 'package:socks5_proxy/socks_server.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show coordinator;
import 'support/trade_orders.dart';

/// The publication of a chat message on a Nostr relay through the Tor transport (#94), against a relay played on the loopback by `dart:io` and, once, through a real SOCKS5 proxy with the client factory of the app.
void main() {
  late List<TorSession> opened;
  final relays = <_FakeRelay>[];
  final transports = <TorCoordinatorTransport>[];

  setUp(() => opened = []);

  tearDown(() async {
    for (final transport in transports) {
      await transport.closeSessions();
    }
    transports.clear();
    for (final relay in relays) {
      await relay.close();
    }
    relays.clear();
  });

  Future<TorSession> openSession() async {
    final session = TorSession(
      TorProxyEndpoint(host: '127.0.0.1', port: 9000 + opened.length),
      TorTransport.direct,
      () async {},
    );
    opened.add(session);
    return session;
  }

  TorCoordinatorTransport transport({
    HttpClient Function(TorProxyEndpoint endpoint)? createHttpClient,
    Duration deadline = const Duration(seconds: 5),
    Duration attemptTimeout = const Duration(seconds: 2),
  }) {
    final transport = TorCoordinatorTransport.withSeams(
      openSession: openSession,
      createHttpClient: createHttpClient ?? (_) => HttpClient(),
      deadline: deadline,
      attemptTimeout: attemptTimeout,
      acceptsHost: (host) => host == '127.0.0.1',
    );
    transports.add(transport);
    return transport;
  }

  Future<_FakeRelay> relay(_RelayBehaviour behaviour) async {
    final relay = await _FakeRelay.start(behaviour);
    relays.add(relay);
    return relay;
  }

  late OutgoingNostrChatMessage message;
  setUpAll(() async {
    final order = await readOrder(
      orderJson(
        9,
        changes: {
          'maker_nostr_pubkey': peer.nostrKeyPair().publicKeyHex,
          'taker_nostr_pubkey': us.nostrKeyPair().publicKeyHex,
        },
      ),
    );
    message = switch (OutgoingNostrChatMessage.compose(
      identity: us,
      order: order,
      coordinator: coordinator('temple'),
      network: RobosatsNetwork.mainnet,
      text: 'a text that never reaches a log',
      now: DateTime.now(),
      random: Random.secure(),
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  });

  test(
    'sends the two events in order on /relay/, waits for their OK, and closes',
    () async {
      final fake = await relay(_RelayBehaviour.accept);
      final outcome = await transport().publish(
        fake.url,
        message,
        robot: us.sessionKey,
      );
      expect(outcome, isA<NostrRelayAccepted>());
      expect(fake.received, message.relayMessages);
      expect(fake.paths, ['/relay/']);
      await fake.closed.future.timeout(const Duration(seconds: 2));
      expect(opened, hasLength(1));
    },
  );

  test('a relay that refuses an event gives refused', () async {
    final fake = await relay(_RelayBehaviour.refuseSecond);
    expect(
      await transport().publish(fake.url, message, robot: us.sessionKey),
      isA<NostrRelayRefused>(),
    );
  });

  test(
    'a silent relay gives timed out, within the bound, and the websocket is closed',
    () async {
      final fake = await relay(_RelayBehaviour.silent);
      final watch = Stopwatch()..start();
      final outcome = await transport(
        attemptTimeout: const Duration(milliseconds: 500),
      ).publish(fake.url, message, robot: us.sessionKey);
      expect(outcome, isA<NostrRelayTimedOut>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
      await fake.closed.future.timeout(const Duration(seconds: 2));
    },
  );

  test(
    'the overall deadline answers timed out whatever the relay does',
    () async {
      final fake = await relay(_RelayBehaviour.silent);
      final outcome = await transport(
        deadline: const Duration(milliseconds: 300),
        attemptTimeout: const Duration(seconds: 10),
      ).publish(fake.url, message, robot: us.sessionKey);
      expect(outcome, isA<NostrRelayTimedOut>());
    },
  );

  test('a relay that closes before answering gives failed', () async {
    final fake = await relay(_RelayBehaviour.closeAtOnce);
    expect(
      await transport().publish(fake.url, message, robot: us.sessionKey),
      isA<NostrRelayFailed>(),
    );
  });

  test(
    'other messages of the relay, OKs for other events and long frames are ignored',
    () async {
      final fake = await relay(_RelayBehaviour.noisy);
      expect(
        await transport().publish(fake.url, message, robot: us.sessionKey),
        isA<NostrRelayAccepted>(),
      );
    },
  );

  test(
    'a service that does not take the websocket gives unreachable, without a retry',
    () async {
      final fake = await relay(_RelayBehaviour.notWebsocket);
      expect(
        await transport().publish(fake.url, message, robot: us.sessionKey),
        isA<NostrRelayUnreachable>(),
      );
      expect(opened, hasLength(1));
    },
  );

  test(
    'a connection failure is retried once on a new session, and logged with its reason only',
    () async {
      final fake = await relay(_RelayBehaviour.accept);
      final printed = <String>[];
      final print = debugPrint;
      debugPrint = (String? line, {int? wrapWidth}) {
        if (line != null) printed.add(line);
      };
      final NostrRelayOutcome outcome;
      try {
        outcome = await transport(
          createHttpClient: (endpoint) => endpoint.port == 9000
              ? _socksRefusal(CommandReplyCode.hostUnreachable)
              : HttpClient(),
        ).publish(fake.url, message, robot: us.sessionKey);
      } finally {
        debugPrint = print;
      }
      expect(outcome, isA<NostrRelayAccepted>());
      expect(opened, hasLength(2));
      expect(
        printed.where((line) => line.contains('retrying')).single,
        matches(
          RegExp(
            r'P2P Nostr relay connection failed \(hostUnreachable\), retrying on a new Tor session(\x1B\[0m)?\s*$',
          ),
        ),
      );
      _expectNothingTelling(printed, fake, message);
    },
  );

  test(
    'two connection failures give unreachable, logged as a fixed word',
    () async {
      final fake = await relay(_RelayBehaviour.accept);
      final printed = <String>[];
      final print = debugPrint;
      debugPrint = (String? line, {int? wrapWidth}) {
        if (line != null) printed.add(line);
      };
      final NostrRelayOutcome outcome;
      try {
        outcome = await transport(
          createHttpClient: (_) =>
              _socksRefusal(CommandReplyCode.hostUnreachable),
        ).publish(fake.url, message, robot: us.sessionKey);
      } finally {
        debugPrint = print;
      }
      expect(outcome, isA<NostrRelayUnreachable>());
      expect(opened, hasLength(2));
      expect(
        printed.where((line) => line.contains('publication')).single,
        matches(
          RegExp(r'P2P Nostr chat publication: unreachable(\x1B\[0m)?\s*$'),
        ),
      );
      _expectNothingTelling(printed, fake, message);
    },
  );

  test('only a ws URL to an accepted host, on /relay/, is opened', () async {
    final tor = transport();
    for (final url in [
      'wss://127.0.0.1:1/relay/',
      'http://127.0.0.1:1/relay/',
      'ws://127.0.0.1:1/other/',
      'ws://127.0.0.1:1/relay/?token=x',
      'ws://user@127.0.0.1:1/relay/',
      'ws://example.com/relay/',
    ]) {
      expect(
        await tor.publish(Uri.parse(url), message, robot: us.sessionKey),
        isA<NostrRelayFailed>(),
        reason: url,
      );
    }
    expect(opened, isEmpty);
  });

  test(
    'closing the robot\'s sessions ends a publication in progress',
    () async {
      final fake = await relay(_RelayBehaviour.silent);
      final tor = transport(attemptTimeout: const Duration(seconds: 10));
      final publication = tor.publish(fake.url, message, robot: us.sessionKey);
      await fake.connected.future.timeout(const Duration(seconds: 2));
      await tor.closeRobotSessions(us.sessionKey);
      expect(
        await publication.timeout(const Duration(seconds: 3)),
        isNot(isA<NostrRelayAccepted>()),
      );
    },
  );

  test(
    'the websocket goes through a real SOCKS5 proxy with the client factory of the Tor sessions',
    () async {
      final fake = await relay(_RelayBehaviour.accept);
      final proxy = SocksServer();
      final forwarded = <String>[];
      final subscription = proxy.connections.listen((connection) async {
        forwarded.add(
          '${connection.desiredAddress.address}:${connection.desiredPort}',
        );
        await connection.forward();
      });
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(proxy.addServerSocket(socket));
      try {
        final outcome = await transport(
          createHttpClient: (_) => const TorHttpClientFactory().create(
            TorProxyEndpoint(host: '127.0.0.1', port: socket.port),
          ),
        ).publish(fake.url, message, robot: us.sessionKey);
        expect(outcome, isA<NostrRelayAccepted>());
        expect(fake.received, message.relayMessages);
        // The proxy was asked for the relay by name, as Tor is asked for an onion service.
        expect(forwarded, ['127.0.0.1:${fake.url.port}']);
      } finally {
        await subscription.cancel();
        await proxy.closeAll();
      }
    },
  );
}

void _expectNothingTelling(
  List<String> printed,
  _FakeRelay relay,
  OutgoingNostrChatMessage message,
) {
  for (final line in printed) {
    for (final secret in [
      '127.0.0.1',
      '${relay.url.port}',
      'ws:',
      '/relay',
      'a text',
      ...message.eventIds,
      us.nostrKeyPair().publicKeyHex,
      us.hashId.hex,
      'temple',
      '$tradeOrderId',
      'RobotSessionKey',
    ]) {
      expect(line, isNot(contains(secret)), reason: secret);
    }
  }
}

HttpClient _socksRefusal(CommandReplyCode code) =>
    HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) async =>
          throw SocksClientConnectionCommandFailedException(code);

enum _RelayBehaviour {
  accept,
  refuseSecond,
  silent,
  closeAtOnce,
  noisy,
  notWebsocket,
}

/// A Nostr relay on the loopback, as strfry answers: `["OK", id, true, ""]` to each `["EVENT", event]`.
final class _FakeRelay {
  final HttpServer _server;
  final _RelayBehaviour _behaviour;
  final List<String> received = [];
  final List<String> paths = [];
  final Completer<void> connected = Completer<void>();
  final Completer<void> closed = Completer<void>();

  _FakeRelay._(this._server, this._behaviour) {
    _server.listen(_serve);
  }

  static Future<_FakeRelay> start(_RelayBehaviour behaviour) async =>
      _FakeRelay._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        behaviour,
      );

  Uri get url => Uri.parse('ws://127.0.0.1:${_server.port}/relay/');

  Future<void> _serve(HttpRequest request) async {
    paths.add(request.uri.path);
    if (_behaviour == _RelayBehaviour.notWebsocket ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    if (!connected.isCompleted) connected.complete();
    if (_behaviour == _RelayBehaviour.closeAtOnce) {
      await socket.close();
      return;
    }
    var count = 0;
    socket.listen(
      (Object? frame) {
        final text = frame as String;
        received.add(text);
        final event =
            (jsonDecode(text) as List<dynamic>)[1] as Map<String, dynamic>;
        final id = event['id'] as String;
        count++;
        switch (_behaviour) {
          case _RelayBehaviour.accept:
            socket.add(jsonEncode(['OK', id, true, '']));
          case _RelayBehaviour.refuseSecond:
            socket.add(
              jsonEncode([
                'OK',
                id,
                count == 1,
                count == 1 ? '' : 'blocked: no',
              ]),
            );
          case _RelayBehaviour.noisy:
            socket
              ..add(jsonEncode(['NOTICE', 'hello']))
              ..add(jsonEncode(['OK', 'f' * 64, false, 'not yours']))
              ..add('x' * (maxRelayFrameLength + 1))
              ..add([1, 2, 3])
              ..add('not json')
              ..add(
                jsonEncode([
                  'OK',
                  id,
                  true,
                  'duplicate: already have this event',
                ]),
              );
          case _RelayBehaviour.silent ||
              _RelayBehaviour.closeAtOnce ||
              _RelayBehaviour.notWebsocket:
            break;
        }
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
  }

  Future<void> close() => _server.close(force: true);
}
