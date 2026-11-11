import 'dart:async';

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:test/test.dart';

/// A Tor that never gives a session, with the states the test chooses.
final class _FakeTor implements Tor {
  @override
  final EmbeddedTor embedded;

  _FakeTor(this.embedded);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeEmbeddedTor implements EmbeddedTor {
  final List<TorConnectionState> _states;
  int openedSessions = 0;

  _FakeEmbeddedTor(this._states);

  @override
  Stream<TorConnectionState> get states => Stream.fromIterable(_states);

  @override
  TorSessions get sessions => _FakeSessions(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeSessions implements TorSessions {
  final _FakeEmbeddedTor _tor;

  _FakeSessions(this._tor);

  @override
  Future<TorSession> open() async {
    _tor.openedSessions++;
    throw const TorBackendException(TorBootstrapFailure('offline'));
  }
}

final _route = TorRoute(
  source: TorSource.embedded,
  endpoint: TorProxyEndpoint(host: '127.0.0.1', port: 9050),
  evidence: TorReadinessEvidence.embeddedBootstrap,
);

void main() {
  late GetIt locator;
  late _FakeEmbeddedTor tor;

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = _FakeEmbeddedTor([
      const TorUninitialized(),
      const TorConnecting(source: TorSource.embedded),
      const TorConnecting(source: TorSource.embedded, progress: 0.5),
      TorReady(_route),
      const TorUnavailable(
        source: TorSource.embedded,
        failure: TorBootstrapTimeoutFailure(),
      ),
      const TorStopped(TorSource.embedded),
    ]);
    locator
      ..registerSingleton<Tor>(_FakeTor(tor))
      ..registerSingleton<TorHttpClientFactory>(const TorHttpClientFactory());
    const P2pFeature().setup(locator);
  });

  tearDown(() => locator.reset());

  test('setup does not touch Tor until a request', () {
    locator<P2pFacade>();

    expect(tor.openedSessions, 0);
  });

  test(
    'a book request fails per coordinator when Tor gives no session',
    () async {
      final books = locator<P2pFacade>().requestBooks(RobosatsNetwork.testnet);

      final outcomes = await Future.wait(books.values);

      expect(outcomes.map((o) => o.coordinator.shortAlias), ['temple', 'lake']);
      for (final outcome in outcomes) {
        expect(
          outcome.result,
          isA<Err<OrderBook, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<CoordinatorUnreachable>(),
          ),
        );
      }
    },
  );

  test('an info request fails as a value when Tor gives no session', () async {
    final facade = locator<P2pFacade>();
    final books = facade.requestBooks(RobosatsNetwork.mainnet);

    final result = await facade.fetchInfo(
      books.keys.first,
      RobosatsNetwork.mainnet,
    );

    expect(
      result,
      isA<Err<CoordinatorInfo, CoordinatorFailure>>().having(
        (err) => err.failure,
        'failure',
        isA<CoordinatorUnreachable>(),
      ),
    );
    await Future.wait(books.values);
  });

  test('the Tor state comes in four steps, without repeats', () async {
    final states = await locator<P2pFacade>().watchTorState().toList();

    expect(states, [
      P2pTorState.notStarted,
      P2pTorState.connecting,
      P2pTorState.ready,
      P2pTorState.failed,
      P2pTorState.notStarted,
    ]);
  });

  test('closing the sessions with none open completes', () async {
    await locator<P2pFacade>().closeSessions();
  });

  group('a robot', () {
    final garageKey = GarageKey.generate();
    final identity = switch (garageKey.firstUsableRobot(0)) {
      Ok(:final value) => value.identity,
      Err(:final failure) => throw StateError('$failure'),
    };
    final pgpKey = switch (RobotPgpKey.generate(identity)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

    test('request fails as a value when Tor gives no session', () async {
      final facade = locator<P2pFacade>();
      final temple = facade.requestBooks(RobosatsNetwork.testnet).keys.first;

      for (final createIfUnknown in [true, false]) {
        final result = await facade.fetchRobot(
          temple,
          RobosatsNetwork.testnet,
          identity: identity,
          pgpKey: pgpKey,
          createIfUnknown: createIfUnknown,
        );

        expect(
          result,
          isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<CoordinatorUnreachable>(),
          ),
        );
      }
    });

    test('asks Tor for a session of its own', () async {
      final facade = locator<P2pFacade>();
      final temple = facade.requestBooks(RobosatsNetwork.testnet).keys.first;
      await facade.fetchInfo(temple, RobosatsNetwork.testnet);
      final afterAnonymous = tor.openedSessions;

      await facade.fetchRobot(
        temple,
        RobosatsNetwork.testnet,
        identity: identity,
        pgpKey: pgpKey,
      );

      // The anonymous reads of temple already asked for a session: the robot does not wait for it or reuse it.
      expect(tor.openedSessions, greaterThan(afterAnonymous));
    });

    test('is not sent to a coordinator that is not on the network', () async {
      final facade = locator<P2pFacade>();
      final bazaar = facade
          .requestBooks(RobosatsNetwork.mainnet)
          .keys
          .firstWhere((coordinator) => coordinator.shortAlias == 'bazaar');
      final before = tor.openedSessions;

      final result = await facade.fetchRobot(
        bazaar,
        RobosatsNetwork.testnet,
        identity: identity,
        pgpKey: pgpKey,
      );

      expect(
        result,
        isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<CoordinatorNotOnNetwork>(),
        ),
      );
      expect(tor.openedSessions, before);
    });

    test('sessions close with none open', () async {
      await locator<P2pFacade>().closeRobotSessions(identity);
    });
  });
}
