import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bull_tor/tor.dart';
import 'package:p2p/src/data/tor_coordinator_transport.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The relay calls of the recovery note (#81) on a Tor session of their own, against a relay played on the loopback by `dart:io`: a read with one `REQ` per filter, its bounds (events, messages, bytes, time), its `CLOSE`, and a publication; each call on a session opened for it and closed after it.
void main() {
  late List<TorSession> opened;
  late List<TorSession> closed;
  final relays = <_NoteRelay>[];
  final transports = <TorCoordinatorTransport>[];

  setUp(() {
    opened = [];
    closed = [];
  });

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
    late final TorSession session;
    session = TorSession(
      TorProxyEndpoint(host: '127.0.0.1', port: 9000 + opened.length),
      TorTransport.direct,
      () async => closed.add(session),
    );
    opened.add(session);
    return session;
  }

  TorCoordinatorTransport transport({
    Duration readDeadline = const Duration(seconds: 3),
    int? ownPlaces,
  }) {
    final transport = TorCoordinatorTransport.withSeams(
      openSession: openSession,
      createHttpClient: (_) => HttpClient(),
      deadline: const Duration(seconds: 3),
      attemptTimeout: const Duration(seconds: 2),
      acceptsHost: (host) => host == '127.0.0.1',
      readDeadline: readDeadline,
      ownPlaces: ownPlaces,
    );
    transports.add(transport);
    return transport;
  }

  Future<_NoteRelay> relay(_Behaviour behaviour) async {
    final relay = await _NoteRelay.start(behaviour);
    relays.add(relay);
    return relay;
  }

  final key = switch (GarageKey.fromBytes(List.filled(32, 7))) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final filters = GarageRecoveryNote.filters(key);
  final note = switch (GarageRecoveryNote.compose(
    key,
    accountIndex: 3,
    now: DateTime.utc(2026, 11, 27),
    random: Random(1),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final event = (jsonDecode(note.relayMessages.single) as List<Object?>)[1];

  test(
    'a read sends one REQ per filter under the official client\'s ids, keeps the events of its subscriptions until each EOSE, sends a CLOSE for each, and closes its own session',
    () async {
      final fake = await relay(_Behaviour.answer)..events = [event];
      final read = await transport().readOnOwnSession(fake.url, filters);
      expect(read.complete, isTrue);
      expect(read.events, [jsonEncode(event), jsonEncode(event)]);
      final requests = [
        for (final text in fake.received)
          if ((jsonDecode(text) as List<Object?>)[0] == 'REQ')
            jsonDecode(text) as List<Object?>,
      ];
      expect(requests, hasLength(2));
      expect(
        [for (final request in requests) jsonEncode(request[2])],
        [for (final filter in filters) filter.toJson()],
      );
      final ids = {for (final request in requests) request[1] as String};
      expect(ids, hasLength(2));
      expect(ids.every((id) => id.startsWith('accountRecovery_')), isTrue);
      await fake.closed.future.timeout(const Duration(seconds: 2));
      expect(
        {
          for (final text in fake.received)
            if ((jsonDecode(text) as List<Object?>)[0] == 'CLOSE')
              (jsonDecode(text) as List<Object?>)[1],
        },
        ids,
      );
      await _until(() => closed.length == opened.length);
      expect(opened, hasLength(1));
    },
  );

  test('every call opens a session of its own, never shared', () async {
    final fake = await relay(_Behaviour.answer);
    final calls = transport();
    await calls.readOnOwnSession(fake.url, filters);
    await calls.readOnOwnSession(fake.url, filters);
    await calls.publishOnOwnSession(fake.url, note);
    expect(opened, hasLength(3));
    await _until(() => closed.length == 3);
    expect(calls.ownSessionsForTesting, (inUse: 0, waiting: 0, open: 0));
  });

  test('a publication on its own session sends the event and awaits its OK', () async {
    final fake = await relay(_Behaviour.answer);
    expect(
      await transport().publishOnOwnSession(fake.url, note),
      isA<NostrRelayAccepted>(),
    );
    expect(fake.received, note.relayMessages);
  });

  test(
    'a relay that never ends its subscriptions gives what it sent, incomplete, by the deadline',
    () async {
      final fake = await relay(_Behaviour.noEose)..events = [event];
      final waited = Stopwatch()..start();
      final read = await transport(
        readDeadline: const Duration(milliseconds: 500),
      ).readOnOwnSession(fake.url, filters);
      expect(waited.elapsed, lessThan(const Duration(seconds: 2)));
      expect(read.complete, isFalse);
      expect(read.events, isNotEmpty);
    },
  );

  test('a relay that sends without end is cut at the bound of events', () async {
    final fake = await relay(_Behaviour.flood)..events = [event];
    final read = await transport(
      readDeadline: const Duration(seconds: 20),
    ).readOnOwnSession(fake.url, filters);
    expect(read.complete, isFalse);
    expect(read.events.length, lessThanOrEqualTo(maxRelayReadEvents));
  });

  test('a relay that cuts the connection gives what it sent, incomplete', () async {
    final fake = await relay(_Behaviour.cut)..events = [event];
    final read = await transport().readOnOwnSession(fake.url, filters);
    expect(read.complete, isFalse);
    expect(read.events, [jsonEncode(event)]);
  });

  test('a subscription the relay closes makes the read incomplete', () async {
    final fake = await relay(_Behaviour.closeSubscriptions);
    final read = await transport().readOnOwnSession(fake.url, filters);
    expect(read.complete, isFalse);
    expect(read.label, 'closedByRelay');
  });

  test(
    'messages of other subscriptions, notices, binary and over-long messages are ignored',
    () async {
      final fake = await relay(_Behaviour.noisy)..events = [event];
      final read = await transport().readOnOwnSession(fake.url, filters);
      expect(read.complete, isTrue);
      expect(read.events, [jsonEncode(event), jsonEncode(event)]);
    },
  );

  test('a relay past the bound of bytes is cut', () async {
    final fake = await relay(_Behaviour.bigEvents);
    final read = await transport(
      readDeadline: const Duration(seconds: 20),
    ).readOnOwnSession(fake.url, filters);
    expect(read.complete, isFalse);
  });

  test('an address that is not a coordinator relay opens no session', () async {
    final calls = transport();
    for (final url in [
      Uri.parse('wss://127.0.0.1/relay/'),
      Uri.parse('ws://127.0.0.1/other/'),
      Uri.parse('ws://example.com/relay/'),
    ]) {
      expect(
        (await calls.readOnOwnSession(url, filters)).label,
        'failed',
        reason: '$url',
      );
    }
    expect(opened, isEmpty);
  });

  test('no relay listening: unreachable, and the session is closed', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final read = await transport().readOnOwnSession(
      Uri.parse('ws://127.0.0.1:$port/relay/'),
      filters,
    );
    expect(read.complete, isFalse);
    expect(read.events, isEmpty);
    await _until(() => closed.length == opened.length);
  });

  test(
    'calls beyond the places wait for one; one whose deadline passes first gives busy',
    () async {
      final fake = await relay(_Behaviour.noEose);
      final calls = transport(
        readDeadline: const Duration(milliseconds: 600),
        ownPlaces: 1,
      );
      final first = calls.readOnOwnSession(fake.url, filters);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls.ownSessionsForTesting.inUse, 1);
      final second = await calls.readOnOwnSession(fake.url, filters);
      expect(second.label, anyOf('busy', 'timedOut'));
      expect((await first).complete, isFalse);
      expect(opened, hasLength(1));
    },
  );
}

Future<void> _until(bool Function() done) async {
  final waited = Stopwatch()..start();
  while (!done() && waited.elapsed < const Duration(seconds: 3)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

enum _Behaviour {
  answer,
  noEose,
  flood,
  cut,
  closeSubscriptions,
  noisy,
  bigEvents,
}

/// A relay on the loopback: it answers each `REQ` as [_behaviour] says, with [events] for each subscription, and an `OK` to each event published.
final class _NoteRelay {
  final HttpServer _server;
  final _Behaviour _behaviour;
  final List<String> received = [];
  final Completer<void> closed = Completer<void>();
  List<Object?> events = [];

  _NoteRelay._(this._server, this._behaviour) {
    _server.listen(_serve);
  }

  static Future<_NoteRelay> start(_Behaviour behaviour) async => _NoteRelay._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    behaviour,
  );

  Uri get url => Uri.parse('ws://127.0.0.1:${_server.port}/relay/');

  Future<void> _serve(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    var flooding = false;
    socket.listen(
      (Object? frame) {
        final text = frame as String;
        received.add(text);
        final message = jsonDecode(text) as List<Object?>;
        switch (message[0]) {
          case 'EVENT':
            final id = (message[1] as Map<String, Object?>)['id'];
            socket.add(jsonEncode(['OK', id, true, '']));
          case 'REQ':
            final id = message[1] as String;
            void send(Object? event) =>
                socket.add(jsonEncode(['EVENT', id, event]));
            switch (_behaviour) {
              case _Behaviour.answer:
                events.forEach(send);
                socket.add(jsonEncode(['EOSE', id]));
              case _Behaviour.noEose:
                events.forEach(send);
              case _Behaviour.flood:
                if (flooding) return;
                flooding = true;
                Future<void> flood() async {
                  for (var i = 0; i < 5000; i++) {
                    if (socket.readyState != WebSocket.open) return;
                    send({...events.first as Map<String, Object?>, 'n': i});
                    if (i % 100 == 0) await Future<void>.delayed(Duration.zero);
                  }
                }
                unawaited(flood());
              case _Behaviour.cut:
                if (flooding) return;
                flooding = true;
                send(events.first);
                unawaited(socket.close());
              case _Behaviour.closeSubscriptions:
                socket.add(jsonEncode(['CLOSED', id, 'auth-required: no']));
              case _Behaviour.noisy:
                socket
                  ..add(jsonEncode(['NOTICE', 'hello']))
                  ..add(jsonEncode(['EVENT', 'other_1', events.first]))
                  ..add([1, 2, 3])
                  ..add('not json')
                  ..add(
                    jsonEncode([
                      'EVENT',
                      id,
                      {'content': 'x' * (maxRelayReadFrameLength + 1)},
                    ]),
                  );
                events.forEach(send);
                socket.add(jsonEncode(['EOSE', id]));
              case _Behaviour.bigEvents:
                if (flooding) return;
                flooding = true;
                Future<void> big() async {
                  for (var i = 0; i < 400; i++) {
                    if (socket.readyState != WebSocket.open) return;
                    send({'content': 'y' * 60000, 'n': i});
                    await Future<void>.delayed(Duration.zero);
                  }
                }
                unawaited(big());
            }
        }
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
  }

  Future<void> close() => _server.close(force: true);
}
