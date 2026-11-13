import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_on_coordinator_face.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/list_robot_hosts_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_standing_usecase.dart';
import 'package:p2p/src/domain/usecases/release_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'package:p2p/src/presentation/robot_coordinator_cubit.dart';
import 'package:p2p/src/presentation/robot_coordinator_state.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';
import 'support/robot_coordinators.dart';

const _testnet = RobosatsNetwork.testnet;
const _mainnet = RobosatsNetwork.mainnet;

/// Lets the futures of the test run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The robot panel of the Garage over the real robot use cases, the bindings of `RecordingBindings`, fake coordinators behind the transport, a fake Tor, and the key work on the test's own isolate.
void main() {
  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fixedKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  NetworkRobot robotAt(int index, [RobosatsNetwork network = _testnet]) =>
      switch (NetworkGarageKey(network, fixedKey).firstUsableRobot(index)) {
        Ok(:final value) when value.accountIndex == index => value,
        _ => throw StateError('no robot $index'),
      };
  final robots = [for (var i = 0; i < 5; i++) robotAt(i)];
  // One pair per robot, each locked by its own token: a read back proves it.
  final pairs = {
    for (final robot in robots.take(3))
      robot.identity.hashId: pairOf(robot.identity),
  };
  final temple = coordinator('temple');
  final lake = coordinator('lake');

  late FakeRobotCoordinators coordinators;
  late RecordingBindings bindings;
  late PairsByRobot keys;
  late RobotRequestLimiter limiter;
  late FakeTor tor;
  late RecordingSessions sessions;
  late List<RobotCoordinatorCubit> cubits;
  late bool holdTenSeconds;

  setUp(() {
    coordinators = FakeRobotCoordinators([
      for (final robot in robots) robot.identity,
    ]);
    bindings = RecordingBindings(
      drawnHere: [
        for (final network in RobosatsNetwork.values) (network, fingerprint),
      ],
    );
    keys = PairsByRobot(pairs);
    // Every wait of the limiter ends at once, but, when a test holds them, the waits of 10 s, the bound of a release among them, which then lasts until the requests of the robot end.
    holdTenSeconds = false;
    limiter = RobotRequestLimiter(
      elapsed: () => Duration.zero,
      delay: (wait) => holdTenSeconds && wait == RobotRequestLimiter.releaseWait
          ? Completer<void>().future
          : Future<void>.value(),
      random: () => 0.5,
    );
    tor = FakeTor();
    sessions = RecordingSessions();
    cubits = [];
  });

  tearDown(() async {
    for (final cubit in cubits) {
      if (!cubit.isClosed) await cubit.close();
    }
  });

  RobotCoordinatorCubit cubitAt(
    int index, {
    RobosatsNetwork network = _testnet,
    Duration stillWaitingAfter = RobotCoordinatorCubit.stillWaitingAfter,
  }) {
    final fetch = FetchRobotUsecase(
      CoordinatorClient(coordinators, clock: () => testNow),
      bindings,
      keys,
    );
    final cubit = RobotCoordinatorCubit(
      NetworkGarageKey(network, fixedKey),
      index,
      ReadRobotStandingUsecase(bindings),
      PutRobotOnCoordinatorUsecase(fetch, bindings, limiter),
      ReadRobotOnCoordinatorUsecase(
        fetch,
        bindings,
        limiter,
        Federation.robosats,
      ),
      ReleaseRobotUsecase(limiter, CloseRobotSessionsUsecase(sessions)),
      WatchP2pTorStateUsecase(() => tor),
      ListRobotHostsUsecase(Federation.robosats, limiter),
      stillWaitingAfter: stillWaitingAfter,
    );
    cubits.add(cubit);
    return cubit;
  }

  /// Binds [robot] to [alias] on its network and has the coordinator keep it with its pair, as after a first contact in an earlier run.
  Future<void> bound(NetworkRobot robot, Coordinator coordinator) async {
    final identity = CoordinatorIdentity.of(coordinator, robot.network);
    if (identity == null) fail('no instance');
    expect(
      await bindings.bind(robot.slot, identity),
      isA<Ok<void, P2pFailure>>(),
    );
    final pair = pairs[robot.identity.hashId];
    if (pair != null) {
      coordinators.keepFor(
        robot.identity,
        coordinator.shortAlias,
        robot.network,
        pair,
      );
    }
  }

  /// Waits, a few seconds at most, until [cubit] is in a state [matches] accepts.
  Future<RobotCoordinatorState> until(
    RobotCoordinatorCubit cubit,
    bool Function(RobotCoordinatorState state) matches,
  ) async {
    for (var i = 0; i < 3000 && !matches(cubit.state); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(matches(cubit.state), isTrue, reason: '${cubit.state}');
    return cubit.state;
  }

  bool known(RobotCoordinatorState state) =>
      state is RobotOnCoordinator && state.activity is RobotKnown;

  bool failed(RobotCoordinatorState state) =>
      state is RobotOnCoordinator && state.activity is RobotFailed;

  RobotOnCoordinatorFace faceOf(RobotCoordinatorState state) => switch (state) {
    RobotOnCoordinator(activity: RobotKnown(:final face)) => face,
    _ => fail('no robot shown: $state'),
  };

  RobotRequestProblem problemOf(RobotCoordinatorState state) => switch (state) {
    RobotOnCoordinator(activity: RobotFailed(:final problem)) => problem,
    _ => fail('no failure shown: $state'),
  };

  List<String> paths() => [
    for (final request in coordinators.requests)
      '${request.url.host == FakeRobotCoordinators.hostOf('temple', _testnet)
              ? 'temple'
              : request.url.host == FakeRobotCoordinators.hostOf('lake', _testnet)
              ? 'lake'
              : 'other'}'
          ' ${coordinators.firstContacts.contains(request) ? 'create' : 'read'}',
  ];

  group('a robot without a coordinator', () {
    test('waits for Tor before « Select Host », and follows it', () async {
      final cubit = cubitAt(0);
      await cubit.load();
      var state = cubit.state;
      expect(state, isA<RobotWithoutCoordinator>());
      state as RobotWithoutCoordinator;
      expect(state.tor, TorWait.initializing);
      expect(state.mayChooseHost, isFalse);
      expect(state.needsAcknowledgement, isFalse);

      tor.embedded.connecting(0.3);
      await _settle();
      expect((cubit.state as RobotWithoutCoordinator).tor, TorWait.connecting);
      tor.embedded.failed();
      await _settle();
      expect((cubit.state as RobotWithoutCoordinator).tor, TorWait.failed);
      tor.embedded.ready();
      await _settle();
      state = cubit.state as RobotWithoutCoordinator;
      expect(state.tor, TorWait.ready);
      expect(state.mayChooseHost, isTrue);
      // Ready stays ready, as for the book.
      tor.embedded.connecting();
      await _settle();
      expect((cubit.state as RobotWithoutCoordinator).tor, TorWait.ready);
      expect(coordinators.requests, isEmpty);
    });

    test(
      'sends nothing before Tor is ready, whatever the screen asks',
      () async {
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.connecting();
        await _settle();

        await cubit.putOn(temple);
        await _settle();

        expect(cubit.state, isA<RobotWithoutCoordinator>());
        expect(coordinators.requests, isEmpty);
        expect(bindings.calls.where((call) => call.$1 == 'bind'), isEmpty);
      },
    );

    test(
      'of a key whose history must be acknowledged: disabled, nothing sent',
      () async {
        bindings = RecordingBindings();
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await _settle();
        final state = cubit.state as RobotWithoutCoordinator;
        expect(state.needsAcknowledgement, isTrue);
        expect(state.mayChooseHost, isFalse);

        await cubit.putOn(temple);
        await _settle();

        expect(cubit.state, isA<RobotWithoutCoordinator>());
        expect(coordinators.requests, isEmpty);
        expect(bindings.calls.where((call) => call.$1 == 'bind'), isEmpty);
      },
    );

    test(
      'goes to the coordinator chosen, only on putOn, and shows it',
      () async {
        final cubit = cubitAt(0);
        final seen = <RobotCoordinatorState>[];
        final subscription = cubit.stream.listen(seen.add);
        addTearDown(subscription.cancel);
        tor.embedded.ready();
        await cubit.load();
        tor.embedded.ready();
        await _settle();
        expect(coordinators.requests, isEmpty);

        await cubit.putOn(temple);
        final face = faceOf(await until(cubit, known));

        expect(paths(), ['temple create']);
        expect((cubit.state as RobotOnCoordinator).coordinator, temple);
        expect(face.activeOrderId, isNull);
        expect(face.lastOrderId, isNull);
        expect(face.earnedRewards, Sats.fromInt(0));
        expect(face.nostrKey, RobotNostrKeyStatus.current);
        expect(face.alreadyExisted, isFalse);
        expect(
          seen.whereType<RobotOnCoordinator>().map((state) => state.activity),
          [
            isA<RobotContacting>()
                .having((a) => a.kind, 'kind', RobotContactKind.create)
                .having((a) => a.slow, 'slow', isFalse),
            isA<RobotKnown>(),
          ],
        );
        final binding =
            (await bindings.standingOf(robots[0].slot))
                as Ok<RobotStanding, P2pFailure>;
        expect(binding.value.binding?.coordinator.alias, 'temple');
      },
    );

    test(
      'says it is still waiting after a while, then shows the answer',
      () async {
        coordinators.hold = Completer<void>();
        final cubit = cubitAt(
          0,
          stillWaitingAfter: const Duration(milliseconds: 30),
        );
        await cubit.load();
        tor.embedded.ready();
        await _settle();

        unawaited(cubit.putOn(temple));
        await until(
          cubit,
          (state) =>
              state is RobotOnCoordinator &&
              state.activity is RobotContacting &&
              !(state.activity as RobotContacting).slow,
        );
        await until(
          cubit,
          (state) =>
              state is RobotOnCoordinator &&
              state.activity is RobotContacting &&
              (state.activity as RobotContacting).slow,
        );
        coordinators.hold?.complete();
        coordinators.hold = null;
        await until(cubit, known);
      },
    );

    test(
      'a coordinator that answers with another pair of the robot: it already existed',
      () async {
        // The pair the coordinator keeps is the robot's own, made elsewhere; this first contact sends another one.
        coordinators.keepFor(
          robots[1].identity,
          'temple',
          _testnet,
          pairOf(robots[1].identity),
        );
        final cubit = cubitAt(1);
        await cubit.load();
        tor.embedded.ready();
        await _settle();

        await cubit.putOn(temple);

        expect(faceOf(await until(cubit, known)).alreadyExisted, isTrue);
        expect(keys.proved, [robots[1].identity.hashId]);
      },
    );

    test('the orders, rewards and Nostr key the coordinator holds', () async {
      coordinators.fields[robots[0].identity.sessionKey] = {
        'active_order_id': null,
        'last_order_id': 4321,
        'earned_rewards': 3500,
        'nostr_pubkey': robots[0].identity
            .nostrKeyPair(NostrKeyDerivation.repositoryFixtures)
            .publicKeyHex,
      };
      final cubit = cubitAt(0);
      await cubit.load();
      tor.embedded.ready();
      await _settle();

      await cubit.putOn(temple);
      final face = faceOf(await until(cubit, known));

      expect(face.lastOrderId, 4321);
      expect(face.activeOrderId, isNull);
      expect(face.earnedRewards, Sats.fromInt(3500));
      expect(face.nostrKey, RobotNostrKeyStatus.old);
    });
  });

  group('a first contact that fails', () {
    Future<RobotCoordinatorCubit> sentToTemple(
      int index,
      List<RobotReply> replies,
    ) async {
      coordinators.script.addAll(replies);
      final cubit = cubitAt(index);
      await cubit.load();
      tor.embedded.ready();
      await _settle();
      await cubit.putOn(temple);
      await until(
        cubit,
        (state) =>
            failed(state) ||
            state is RobotWithoutCoordinator && state.lastAttempt != null,
      );
      return cubit;
    }

    test('offline: the robot is bound, and « Retry » reads it back', () async {
      final cubit = await sentToTemple(0, [RobotReply.unreachable]);
      final problem = problemOf(cubit.state);
      expect(
        problem,
        isA<RobotRequestAnswered>().having(
          (p) => p.failure,
          'failure',
          isA<CoordinatorUnreachable>(),
        ),
      );
      expect(problem.wayOut, RobotWayOut.readBack);
      expect((cubit.state as RobotOnCoordinator).coordinator, temple);

      await cubit.retry();
      await until(cubit, (state) => known(state) || failed(state));

      // The coordinator never created it: the read back says so, with a first contact as the way out.
      expect(paths(), ['temple create', 'temple read']);
      expect(problemOf(cubit.state).wayOut, RobotWayOut.firstContact);
      await cubit.retry();
      await until(cubit, known);
      // The put reads the bound robot back first, then makes its first contact.
      expect(paths(), [
        'temple create',
        'temple read',
        'temple read',
        'temple create',
      ]);
    });

    test(
      'a nickname taken: bound there, no way out but the next robot',
      () async {
        final cubit = await sentToTemple(0, [RobotReply.nicknameTaken]);
        final problem = problemOf(cubit.state);
        expect(
          problem,
          isA<RobotRequestAnswered>().having(
            (p) => p.failure,
            'failure',
            isA<RobotNicknameTaken>(),
          ),
        );
        expect(problem.wayOut, RobotWayOut.none);
        expect((cubit.state as RobotOnCoordinator).coordinator, temple);
        final sent = coordinators.requests.length;

        await cubit.retry();
        await _settle();
        expect(coordinators.requests, hasLength(sent));
      },
    );

    test(
      'a key too recent: « Retry » is a new first contact to the same coordinator',
      () async {
        final cubit = await sentToTemple(0, [RobotReply.keyTooRecent]);
        expect(problemOf(cubit.state).wayOut, RobotWayOut.firstContact);

        await cubit.retry();
        await until(cubit, known);
        expect(paths(), ['temple create', 'temple read', 'temple create']);
      },
    );

    test('keys refused otherwise: no way out', () async {
      final cubit = await sentToTemple(0, [RobotReply.keysRefused]);
      expect(
        problemOf(cubit.state),
        isA<RobotRequestAnswered>().having(
          (p) => p.failure,
          'failure',
          isA<RobotKeysRefused>(),
        ),
      );
      expect(problemOf(cubit.state).wayOut, RobotWayOut.none);
    });

    test('another robot answered: no way out', () async {
      final cubit = await sentToTemple(0, [RobotReply.otherRobot]);
      expect(
        problemOf(cubit.state),
        isA<RobotRequestAnswered>().having(
          (p) => p.failure,
          'failure',
          isA<RobotHashIdMismatch>(),
        ),
      );
      expect(problemOf(cubit.state).wayOut, RobotWayOut.none);
    });

    test('an unreadable answer: « Retry » reads back', () async {
      final cubit = await sentToTemple(0, [RobotReply.notJson]);
      expect(
        problemOf(cubit.state),
        isA<RobotRequestAnswered>().having(
          (p) => p.failure,
          'failure',
          isA<CoordinatorNotJson>(),
        ),
      );
      expect(problemOf(cubit.state).wayOut, RobotWayOut.readBack);
    });

    test('busy after the backoff: « Retry » reads back', () async {
      final cubit = await sentToTemple(
        0,
        List.filled(RobotRequestLimiter.maxAttempts, RobotReply.busy),
      );
      expect(
        problemOf(cubit.state),
        isA<RobotRequestRefused>().having(
          (p) => p.failure,
          'failure',
          isA<RobotCoordinatorBusyFailure>(),
        ),
      );
      expect(problemOf(cubit.state).wayOut, RobotWayOut.readBack);
    });

    test(
      'a key pair this device could not make: bound, « Retry » reads back',
      () async {
        keys.generateFailure = const RobotKeyComputeFailure();
        final cubit = await sentToTemple(0, const []);
        expect(
          problemOf(cubit.state),
          isA<RobotRequestRefused>().having(
            (p) => p.failure,
            'failure',
            isA<RobotKeyComputeFailure>(),
          ),
        );
        expect(problemOf(cubit.state).wayOut, RobotWayOut.readBack);
        expect(coordinators.requests, isEmpty);
      },
    );

    test(
      'a coordinator that refused too many robots: listed so, nothing bound or sent',
      () async {
        // Three first contacts the coordinator refused with a nickname taken, in this run.
        for (var i = 0; i < RobotRequestLimiter.maxNicknameRefusals; i++) {
          limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
        }
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await _settle();
        expect(
          cubit.hosts().map(
            (host) => (host.coordinator.shortAlias, host.refusesFirstContacts),
          ),
          [('temple', true), ('lake', false)],
        );

        await cubit.putOn(temple);
        final state =
            await until(
                  cubit,
                  (state) =>
                      state is RobotWithoutCoordinator &&
                      state.lastAttempt != null,
                )
                as RobotWithoutCoordinator;

        expect(state.lastAttempt?.coordinator, temple);
        expect(
          state.lastAttempt?.problem,
          isA<RobotRequestRefused>().having(
            (p) => p.failure,
            'failure',
            isA<RobotCoordinatorTooManyRefusalsFailure>(),
          ),
        );
        expect(state.mayChooseHost, isTrue);
        expect(coordinators.requests, isEmpty);
        expect(bindings.calls.where((call) => call.$1 == 'bind'), isEmpty);
      },
    );
  });

  group('a robot bound to a coordinator of its network', () {
    test(
      'is read back once Tor is ready, from that coordinator only',
      () async {
        await bound(robots[0], temple);
        final cubit = cubitAt(0);
        await cubit.load();
        expect(
          cubit.state,
          isA<RobotOnCoordinator>()
              .having((s) => s.coordinator, 'coordinator', temple)
              .having(
                (s) => s.activity,
                'activity',
                isA<RobotWaitingForTor>().having(
                  (a) => a.tor,
                  'tor',
                  TorWait.initializing,
                ),
              ),
        );
        tor.embedded.connecting();
        await _settle();
        expect(
          ((cubit.state as RobotOnCoordinator).activity as RobotWaitingForTor)
              .tor,
          TorWait.connecting,
        );
        tor.embedded.failed();
        await _settle();
        expect(
          ((cubit.state as RobotOnCoordinator).activity as RobotWaitingForTor)
              .tor,
          TorWait.failed,
        );
        expect(coordinators.requests, isEmpty);

        coordinators.hold = Completer<void>();
        tor.embedded.ready();
        await until(
          cubit,
          (state) =>
              state is RobotOnCoordinator && state.activity is RobotContacting,
        );
        expect(
          ((cubit.state as RobotOnCoordinator).activity as RobotContacting)
              .kind,
          RobotContactKind.read,
        );
        coordinators.hold?.complete();
        coordinators.hold = null;
        final face = faceOf(await until(cubit, known));

        expect(paths(), ['temple read']);
        expect(face.alreadyExisted, isFalse);
        expect(keys.generated, isEmpty);
      },
    );

    test('is read back at once when Tor is already ready', () async {
      await bound(robots[0], temple);
      tor.embedded.ready();
      final cubit = cubitAt(0);
      await cubit.load();
      tor.embedded.ready();
      await until(cubit, known);
      expect(paths(), ['temple read']);
    });

    test('is never put on the coordinator a screen gives', () async {
      await bound(robots[0], temple);
      final cubit = cubitAt(0);
      await cubit.load();
      tor.embedded.ready();
      await until(cubit, known);
      final shown = cubit.state;
      final reads = bindings.calls.length;

      await cubit.putOn(lake);
      await _settle();

      expect(paths(), ['temple read']);
      // The cubit itself asks nothing: not even the use case, which would refuse it too.
      expect(identical(cubit.state, shown), isTrue);
      expect(bindings.calls, hasLength(reads));
    });

    test(
      'unknown there: « Retry » is a first contact to that coordinator',
      () async {
        await bound(robots[0], temple);
        coordinators.kept.clear();
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await until(cubit, failed);
        expect(
          problemOf(cubit.state),
          isA<RobotRequestAnswered>().having(
            (p) => p.failure,
            'failure',
            isA<RobotUnknown>(),
          ),
        );

        await cubit.retry();
        await until(cubit, known);

        // The put reads it back first, then makes the first contact the coordinator needs.
        expect(paths(), ['temple read', 'temple read', 'temple create']);
        expect((cubit.state as RobotOnCoordinator).coordinator, temple);
        // The first contact got back the pair it sent.
        expect(
          ((cubit.state as RobotOnCoordinator).activity as RobotKnown)
              .face
              .alreadyExisted,
          isFalse,
        );
      },
    );

    test(
      'unknown, then a first contact at « Retry » answered with another pair: it already existed',
      () async {
        await bound(robots[0], temple);
        coordinators.kept.clear();
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await until(cubit, failed);
        // Another device creates the robot there with its own pair, just before this first contact arrives.
        final other = pairOf(robots[0].identity);
        coordinators.onSend = (request) {
          if (coordinators.firstContacts.contains(request)) {
            coordinators.keepFor(robots[0].identity, 'temple', _testnet, other);
          }
        };

        await cubit.retry();
        final state = await until(cubit, known) as RobotOnCoordinator;

        expect(paths(), ['temple read', 'temple read', 'temple create']);
        expect((state.activity as RobotKnown).face.alreadyExisted, isTrue);
      },
    );


    test(
      'unknown, then known at « Retry »: no first contact, and no « already existed »',
      () async {
        await bound(robots[0], temple);
        final kept = Map.of(coordinators.kept);
        coordinators.kept.clear();
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await until(cubit, failed);
        // The coordinator knows the robot again, as after a first contact whose answer was lost.
        coordinators.kept.addAll(kept);

        await cubit.retry();
        final state = await until(cubit, known) as RobotOnCoordinator;

        expect(paths(), ['temple read', 'temple read']);
        // Found by the read, with no first contact sent: this device put it there before.
        expect((state.activity as RobotKnown).face.alreadyExisted, isFalse);
      },
    );

    test('offline, then « Retry » reads it back again', () async {
      await bound(robots[0], temple);
      coordinators.script.add(RobotReply.unreachable);
      final cubit = cubitAt(0);
      await cubit.load();
      tor.embedded.ready();
      await until(cubit, failed);
      expect(problemOf(cubit.state).wayOut, RobotWayOut.readBack);

      await cubit.retry();
      await until(cubit, known);
      expect(paths(), ['temple read', 'temple read']);
    });

    test(
      'whose coordinator changed its keys: nothing sent, no way out',
      () async {
        final identity = CoordinatorIdentity.of(temple, _testnet);
        if (identity == null) fail('no instance');
        await bindings.bind(
          robots[0].slot,
          CoordinatorIdentity(
            network: _testnet,
            alias: 'temple',
            onion: identity.onion,
            nodeKeys: identity.nodeKeys,
            nostrKey: '00${identity.nostrKey.substring(2)}',
          ),
        );
        tor.embedded.ready();
        final cubit = cubitAt(0);
        final seen = <RobotCoordinatorState>[];
        final subscription = cubit.stream.listen(seen.add);
        addTearDown(subscription.cancel);
        await cubit.load();
        tor.embedded.ready();
        await _settle();

        // Said at once, from the binding and the list: the coordinator is never shown as the robot's.
        expect(seen.whereType<RobotOnCoordinator>(), isEmpty);
        expect(
          cubit.state,
          isA<RobotCoordinatorChanged>()
              .having((s) => s.alias, 'alias', 'temple')
              .having((s) => s.listed, 'listed', temple),
        );
        expect(coordinators.requests, isEmpty);
        await cubit.retry();
        await cubit.putOn(lake);
        await _settle();
        expect(coordinators.requests, isEmpty);
      },
    );

    test('bound on the other network: said so, nothing sent', () async {
      await bound(robotAt(0, _mainnet), coordinator('temple'));
      tor.embedded.ready();
      final cubit = cubitAt(0);
      await cubit.load();
      tor.embedded.ready();
      await _settle();

      expect(
        cubit.state,
        isA<RobotOnOtherNetwork>().having(
          (s) => s.network,
          'network',
          _mainnet,
        ),
      );
      expect(coordinators.requests, isEmpty);
    });
  });

  test(
    'a database that cannot be read: said so, and « Retry » reads it again',
    () async {
      bindings.readFailure = const P2pStorageFailure();
      final cubit = cubitAt(0);
      await cubit.load();
      expect(
        cubit.state,
        isA<RobotStandingUnreadable>().having(
          (s) => s.failure,
          'failure',
          isA<P2pStorageFailure>(),
        ),
      );

      bindings.readFailure = null;
      await cubit.retry();
      expect(cubit.state, isA<RobotWithoutCoordinator>());
      expect(coordinators.requests, isEmpty);
    },
  );

  group('the coordinator of a binding, as the list gives it now', () {
    final hosts = ListRobotHostsUsecase(
      Federation.robosats,
      RobotRequestLimiter(
        elapsed: () => Duration.zero,
        delay: (_) => Future<void>.value(),
        random: () => 0.5,
      ),
    ).execute(_testnet);
    final identity = switch (CoordinatorIdentity.of(temple, _testnet)) {
      final identity? => identity,
      null => throw StateError('no testnet instance'),
    };
    RobotBinding boundTo(CoordinatorIdentity coordinator) =>
        RobotBinding(coordinator, testNow, BindingProvenance.drawnHere);
    Matcher refused<T>() => isA<Err<Coordinator, P2pFailure>>().having(
      (err) => err.failure,
      'failure',
      isA<T>(),
    );

    test('is the listed coordinator when nothing changed', () {
      expect(
        hosts.boundTo(boundTo(identity)),
        isA<Ok<Coordinator, P2pFailure>>().having(
          (ok) => ok.value,
          'value',
          temple,
        ),
      );
    });

    test('changed, when its keys or its address differ', () {
      for (final changed in [
        CoordinatorIdentity(
          network: _testnet,
          alias: 'temple',
          onion: identity.onion,
          nodeKeys: identity.nodeKeys,
          nostrKey: '00${identity.nostrKey.substring(2)}',
        ),
        CoordinatorIdentity(
          network: _testnet,
          alias: 'temple',
          onion: identity.onion,
          nodeKeys: const [],
          nostrKey: identity.nostrKey,
        ),
        CoordinatorIdentity(
          network: _testnet,
          alias: 'temple',
          onion: 'http://${'a' * 56}.onion',
          nodeKeys: identity.nodeKeys,
          nostrKey: identity.nostrKey,
        ),
      ]) {
        expect(
          hosts.boundTo(boundTo(changed)),
          refused<RobotCoordinatorChangedFailure>(),
        );
      }
    });

    test('changed, when the list no longer has it on the network', () {
      final gone = CoordinatorIdentity(
        network: _testnet,
        alias: 'gone',
        onion: identity.onion,
        nodeKeys: identity.nodeKeys,
        nostrKey: identity.nostrKey,
      );
      expect(
        hosts.boundTo(boundTo(gone)),
        refused<RobotCoordinatorChangedFailure>(),
      );
      expect(hosts.listed('gone'), isNull);
      // Ammanaya has no testnet instance.
      expect(hosts.listed('ammanaya'), isNull);
    });

    test('another coordinator, when the binding is of the other network', () {
      final mainnetTemple = switch (CoordinatorIdentity.of(temple, _mainnet)) {
        final identity? => identity,
        null => throw StateError('no mainnet instance'),
      };
      expect(
        hosts.boundTo(boundTo(mainnetTemple)),
        refused<RobotBoundToAnotherCoordinatorFailure>(),
      );
    });
  });

  test('the hosts of each network, in the order of the federation', () {
    expect(cubitAt(0).hosts().map((host) => host.coordinator.shortAlias), [
      'temple',
      'lake',
    ]);
    expect(
      cubitAt(
        0,
        network: _mainnet,
      ).hosts().map((host) => host.coordinator.shortAlias),
      [
        for (final coordinator in Federation.robosats.on(_mainnet))
          coordinator.shortAlias,
      ],
    );
    expect(Federation.robosats.on(_mainnet).map((c) => c.shortAlias), [
      'temple',
      'lake',
      'bazaar',
      'freeport',
      'ammanaya',
      'gumpellite',
    ]);
  });

  group('closing the panel', () {
    test('releases the robot: its sessions are closed', () async {
      final cubit = cubitAt(0);
      await cubit.load();
      await cubit.close();
      expect(sessions.closed, [robots[0].identity.sessionKey]);
    });

    test(
      'while a request is in flight: it ends, and its answer is ignored',
      () async {
        holdTenSeconds = true;
        await bound(robots[0], temple);
        coordinators.hold = Completer<void>();
        final cubit = cubitAt(0);
        await cubit.load();
        tor.embedded.ready();
        await until(cubit, (state) => coordinators.requests.isNotEmpty);
        final shown = cubit.state;

        final closing = cubit.close();
        await _settle();
        expect(sessions.closed, isEmpty);
        coordinators.hold?.complete();
        await closing;

        expect(identical(cubit.state, shown), isTrue);
        expect(sessions.closed, [robots[0].identity.sessionKey]);
      },
    );

    test(
      'drops a request still waiting for its place: it never leaves',
      () async {
        // Robots 1 and 2 hold the two places of temple; robot 0 waits behind them.
        for (final index in [1, 2, 0]) {
          await bound(robots[index], temple);
        }
        coordinators.hold = Completer<void>();
        tor.embedded.ready();
        final others = [cubitAt(1), cubitAt(2)];
        for (final cubit in others) {
          await cubit.load();
        }
        tor.embedded.ready();
        await until(others[1], (state) => coordinators.requests.length == 2);
        final waiting = cubitAt(0);
        await waiting.load();
        tor.embedded.ready();
        await _settle();
        expect(
          waiting.state,
          isA<RobotOnCoordinator>().having(
            (s) => s.activity,
            'activity',
            isA<RobotContacting>(),
          ),
        );

        await waiting.close();
        coordinators.hold?.complete();
        for (final cubit in others) {
          await until(cubit, known);
        }

        final robot0 = robots[0].identity.sessionKey;
        expect(
          coordinators.requests.where((request) => request.robot == robot0),
          isEmpty,
        );
        expect(sessions.closed, contains(robot0));
      },
    );

    test(
      'a robot shown again at once gets a cubit of its own, which reads it',
      () async {
        await bound(robots[0], temple);
        tor.embedded.ready();
        final first = cubitAt(0);
        await first.load();
        tor.embedded.ready();
        await until(first, known);
        await first.close();
        final again = cubitAt(0);
        await again.load();
        tor.embedded.ready();
        await until(again, known);
        expect(paths(), ['temple read', 'temple read']);
      },
    );
  });

  test('nothing printed or logged over every path holds the key', () async {
    final output = await captureKeyOutput(() async {
      await bound(robots[1], temple);
      coordinators.script.addAll([
        RobotReply.unreachable,
        RobotReply.nicknameTaken,
      ]);
      tor.embedded.ready();
      for (final index in [0, 1, 2]) {
        final cubit = cubitAt(index);
        await cubit.load();
        tor.embedded.ready();
        await _settle();
        await cubit.putOn(temple);
        await cubit.retry();
        await _settle();
        await cubit.close();
      }
    });
    expectNoKeyIn(output, [fixedKey]);
    for (final robot in robots) {
      expect(output.contains(robot.identity.tokenSha256Hex), isFalse);
    }
  });
}
