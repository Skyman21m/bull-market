import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/tor_coordinator_transport.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/p2p_shuffle.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:robosats/robosats.dart'
    show CoordinatorClient, CoordinatorRobot, GarageKey, RobotPgpKey;
import 'package:test/test.dart';

import 'support/robot_bindings.dart';
import 'support/robot_keys.dart';

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
    // Without the Garage Key handle and the database, as the WorkManager isolate composes it: `garage_key_setup_test.dart` covers both compositions.
    const P2pFeature().setup(
      locator,
      garageKeys: null,
      databaseDirectory: null,
    );
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

  test('the app draws the phrases of the Tor wait in a random order', () {
    expect(locator<P2pShuffle>(), same(P2pShuffle.random));
  });

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

  group('a robot, through the transport of the feature,', () {
    // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
    final garageKey = switch (GarageKey.fromBytes(
      Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    NetworkRobot robotOn(RobosatsNetwork network) =>
        switch (NetworkGarageKey(network, garageKey).firstUsableRobot(0)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
    final testnetRobot = robotOn(RobosatsNetwork.testnet);
    final identity = testnetRobot.identity;
    final pgpKey = switch (RobotPgpKey.generate(identity)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

    // The request of a robot is registered with the Garage only (`garage_key_setup_test.dart`): here it is made over the transport this setup registered, with bindings in memory where the test key is recorded as drawn on this device.
    late FetchRobotUsecase fetchRobot;

    setUp(() async {
      final bindings = bindingsInMemory();
      expect(
        await bindings.recordGeneratedKey(
          RobosatsNetwork.testnet,
          testnetRobot.keyFingerprint,
        ),
        isA<Ok<void, P2pFailure>>(),
      );
      fetchRobot = FetchRobotUsecase(
        CoordinatorClient(locator<TorCoordinatorTransport>()),
        bindings,
        RecordingRobotKeys(pgpKey),
      );
    });

    Matcher answeredWith<T>() =>
        isA<Ok<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>()
            .having(
              (ok) => ok.value,
              'answer',
              isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
                (err) => err.failure,
                'failure',
                isA<T>(),
              ),
            );

    test('request fails as a value when Tor gives no session', () async {
      final temple = locator<P2pFacade>()
          .requestBooks(RobosatsNetwork.testnet)
          .keys
          .first;

      for (final createIfUnknown in [true, false]) {
        final result = await fetchRobot.execute(
          temple,
          testnetRobot,
          createIfUnknown: createIfUnknown,
        );

        expect(result, answeredWith<CoordinatorUnreachable>());
      }
    });

    test('asks Tor for a session of its own', () async {
      final facade = locator<P2pFacade>();
      final temple = facade.requestBooks(RobosatsNetwork.testnet).keys.first;
      await facade.fetchInfo(temple, RobosatsNetwork.testnet);
      final afterAnonymous = tor.openedSessions;

      await fetchRobot.execute(temple, testnetRobot, createIfUnknown: false);

      // The anonymous reads of temple already asked for a session: the robot does not wait for it or reuse it.
      expect(tor.openedSessions, greaterThan(afterAnonymous));
    });

    test(
      'is not sent to a coordinator that is not on the network of its key',
      () async {
        final bazaar = locator<P2pFacade>()
            .requestBooks(RobosatsNetwork.mainnet)
            .keys
            .firstWhere((coordinator) => coordinator.shortAlias == 'bazaar');
        final before = tor.openedSessions;

        final result = await fetchRobot.execute(
          bazaar,
          testnetRobot,
          createIfUnknown: true,
        );

        expect(result, answeredWith<CoordinatorNotOnNetwork>());
        expect(tor.openedSessions, before);
      },
    );

    test('sessions close with none open', () async {
      await locator<CloseRobotSessionsUsecase>().execute(identity);
    });
  });

  group('the app-facing library', () {
    // Tests run with the package directory as working directory.
    final library = File('lib/p2p.dart').readAsStringSync();
    final facade = File('lib/public/p2p_facade.dart').readAsStringSync();

    /// Every identifier a source names, comments included.
    Set<String> identifiers(String source) =>
        RegExp(r'\w+').allMatches(source).map((m) => m[0] ?? '').toSet();

    test('exports nothing that makes, holds or reveals a robot', () {
      // The shell could otherwise generate and reveal Garage Keys outside the reach of the custody gate.
      for (final name in [
        'GarageKey',
        'GarageRobot',
        'RobotIdentity',
        'RobotToken',
        'RobotPgpKey',
        'UnlockedRobotPgpKey',
        'NostrKeyPair',
        'NostrKeyDerivation',
        'CoordinatorClient',
        'CoordinatorRobot',
        'CoordinatorRobotAnswer',
        'UnprovenCoordinatorRobot',
        'CoordinatorTransport',
        'CoordinatorRequest',
        'RobotSessionKey',
        // The bindings of the robots: the shell gives the directory of their database, and nothing else.
        'GarageKeyFingerprint',
        'RobotSlot',
        'RobotBinding',
        'CoordinatorIdentity',
        'RobotBindingRepository',
        'P2pDatabase',
      ]) {
        expect(identifiers(library), isNot(contains(name)), reason: name);
        expect(identifiers(facade), isNot(contains(name)), reason: name);
      }
      expect(library, isNot(contains('testing.dart')));
      // Only the named types of `robosats` are exported, never the whole library.
      expect(
        RegExp(r"export 'package:robosats/[^']+'(?!\s+show)").hasMatch(library),
        isFalse,
      );
    });

    test('has no robot method on its facade', () {
      expect(facade, isNot(contains('Robot(')));
      expect(facade, isNot(contains('RobotUsecase')));
    });
  });
}
