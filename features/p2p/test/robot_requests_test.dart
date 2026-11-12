import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:p2p/src/domain/robot_on_coordinator_face.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/release_robot_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';

const _testnet = RobosatsNetwork.testnet;
const _mainnet = RobosatsNetwork.mainnet;

/// A Garage Key made for these tests only.
final GarageKey _garageKey = switch (GarageKey.fromBytes(
  utf8.encode('a Garage Key of the p2p tests...'),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

NetworkRobot _robotAt(int index, RobosatsNetwork network) =>
    switch (NetworkGarageKey(network, _garageKey).firstUsableRobot(index)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

RobotPgpKey _pairOf(NetworkRobot robot) =>
    switch (RobotPgpKey.generate(robot.identity)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

/// Lets the futures of the test run: microtasks, the database in memory and the timers of zero.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits, a few seconds at most, until [condition] holds.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 2000 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

/// The time of the limiter: an elapsed time the test moves, every wait recorded, and the draws of the spread in turn.
final class _Time {
  Duration elapsed = Duration.zero;
  final List<Duration> waits = [];
  final List<double> draws;
  int _drawn = 0;

  /// When set, each wait lasts until the test ends it, from [held].
  bool holding = false;
  final List<Completer<void>> held = [];

  _Time([this.draws = const [0.5]]);

  Future<void> delay(Duration wait) {
    waits.add(wait);
    if (!holding) return Future.value();
    final over = Completer<void>();
    held.add(over);
    return over.future;
  }

  double random() => draws[_drawn++ % draws.length];

  RobotRequestLimiter limiter() =>
      RobotRequestLimiter(elapsed: () => elapsed, delay: delay, random: random);
}

/// What the coordinator of the tests does with one request.
enum _Reply {
  /// The transport had no place for it: nothing reaches the coordinator.
  busy,

  /// The coordinator stores the robot of a first contact, as it does, and the transport then gives up with a busy answer, as a `GET` retried after a broken connection that finds no place.
  storedThenBusy,

  /// The deadline of the transport passed.
  timedOut,

  /// The coordinator stores the robot of a first contact, and its answer is lost: the deadline of the transport passes.
  storedThenTimedOut,

  /// The coordinator could not be reached.
  unreachable,

  /// Any other failure of the transport.
  failed,

  /// Error 7004 for a first contact, 7001 for the short header (from the review of step 3).
  takenOrUnknown,

  /// Error 7004: the nickname is taken.
  nicknameTaken,

  /// Error 7001: the robot is unknown, whatever the header.
  unknown,

  /// As the reference coordinator: a first contact creates the robot with its pair and its Nostr key unless the coordinator knows it, every request is answered with what it kept, and a short header for an unknown robot is error 7001.
  keep,
}

/// The coordinators of the tests behind one transport: each request gets the next reply of [script], or [_Reply.keep] once it is empty.
final class _Coordinators implements CoordinatorTransport {
  final Map<RobotSessionKey, RobotIdentity> _robots;
  final List<CoordinatorRequest> requests = [];
  final List<_Reply> script = [];

  /// What each coordinator, by onion host, keeps of each robot: its two key blocks, its Nostr key and any other field.
  final Map<(String, RobotSessionKey), Map<String, Object?>> kept = {};

  /// Runs as each request arrives, before it is answered.
  Future<void> Function(CoordinatorRequest request)? onSend;

  _Coordinators(Iterable<NetworkRobot> robots)
    : _robots = {
        for (final robot in robots) robot.identity.sessionKey: robot.identity,
      };

  /// The requests made for [robot].
  List<CoordinatorRequest> of(NetworkRobot robot) => [
    for (final request in requests)
      if (request.robot == robot.identity.sessionKey) request,
  ];

  /// What [coordinator] on [network] keeps of [robot], to set before a test.
  void keepFor(
    NetworkRobot robot,
    String coordinator,
    RobosatsNetwork network,
    RobotPgpKey pair, {
    Map<String, Object?> fields = const {},
  }) => kept[(hostOf(coordinator, network), robot.identity.sessionKey)] = {
    'public_key': pair.publicKey.armored,
    'encrypted_private_key': pair.encryptedPrivateKeyArmored,
    'nostr_pubkey': robot.identity.nostrKeyPair().publicKeyHex,
    ...fields,
  };

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    await onSend?.call(request);
    final reply = script.isEmpty ? _Reply.keep : script.removeAt(0);
    final key = request.robot;
    final identity = key == null ? null : _robots[key];
    if (key == null || identity == null) {
      throw StateError('a request for no robot of the test');
    }
    final place = (request.url.host, key);
    final parts = (request.headers['Authorization'] ?? '').split(' | ');
    void store() {
      if (parts.length != 4) return;
      kept.putIfAbsent(
        place,
        () => {
          'public_key': pgpArmorFromWire(parts[1].substring('Public '.length)),
          'encrypted_private_key': pgpArmorFromWire(
            parts[2].substring('Private '.length),
          ),
          'nostr_pubkey': parts[3].substring('Nostr '.length),
        },
      );
    }

    switch (reply) {
      case _Reply.busy:
        return const Err(CoordinatorTransportBusy());
      case _Reply.storedThenBusy:
        store();
        return const Err(CoordinatorTransportBusy());
      case _Reply.timedOut:
        return const Err(CoordinatorTimedOut());
      case _Reply.storedThenTimedOut:
        store();
        return const Err(CoordinatorTimedOut());
      case _Reply.unreachable:
        return const Err(CoordinatorUnreachable());
      case _Reply.failed:
        return const Err(CoordinatorTransportFailed());
      case _Reply.takenOrUnknown:
        return parts.length == 4
            ? Ok(_json(409, {'error_code': 7004, 'bad_request': 'taken'}))
            : Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
      case _Reply.nicknameTaken:
        return Ok(_json(409, {'error_code': 7004, 'bad_request': 'taken'}));
      case _Reply.unknown:
        return Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
      case _Reply.keep:
        store();
        final robot = kept[place];
        if (robot == null) {
          return Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
        }
        return Ok(
          _json(200, {
            'nickname': identity.nickname,
            'hash_id': identity.hashId.hex,
            ...robot,
          }),
        );
    }
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

/// [coordinator] as a later list could give it, with no instance on testnet.
Coordinator _withoutTestnet(Coordinator coordinator) => Coordinator(
  shortAlias: coordinator.shortAlias,
  longAlias: coordinator.longAlias,
  identifier: coordinator.identifier,
  description: coordinator.description,
  motto: coordinator.motto,
  color: coordinator.color,
  established: coordinator.established,
  nostrHexPubkey: coordinator.nostrHexPubkey,
  contact: coordinator.contact,
  badges: coordinator.badges,
  policies: coordinator.policies,
  mainnet: coordinator.mainnet,
  testnet: const CoordinatorOrigins(),
  mainnetNodesPubkeys: coordinator.mainnetNodesPubkeys,
  testnetNodesPubkeys: coordinator.testnetNodesPubkeys,
  federated: coordinator.federated,
);

/// [coordinator] as a later list could give it, with another Nostr key.
Coordinator _withNostrKey(Coordinator coordinator, String nostrHexPubkey) =>
    Coordinator(
      shortAlias: coordinator.shortAlias,
      longAlias: coordinator.longAlias,
      identifier: coordinator.identifier,
      description: coordinator.description,
      motto: coordinator.motto,
      color: coordinator.color,
      established: coordinator.established,
      nostrHexPubkey: nostrHexPubkey,
      contact: coordinator.contact,
      badges: coordinator.badges,
      policies: coordinator.policies,
      mainnet: coordinator.mainnet,
      testnet: coordinator.testnet,
      mainnetNodesPubkeys: coordinator.mainnetNodesPubkeys,
      testnetNodesPubkeys: coordinator.testnetNodesPubkeys,
      federated: coordinator.federated,
    );

/// The armored public key a first contact sent, from its header.
String? _sentPublicKey(CoordinatorRequest request) {
  final parts = (request.headers['Authorization'] ?? '').split(' | ');
  return parts.length == 4
      ? pgpArmorFromWire(parts[1].substring('Public '.length))
      : null;
}

/// The key work of the robots on the test's own isolate: each robot gets, in turn, the pairs the test made for it, and the proofs are the package's.
final class _Keys implements RobotKeyComputePort {
  final Map<RobotHashId, List<RobotPgpKey>> _pairs;
  final List<RobotHashId> generated = [];
  final List<RobotHashId> proved = [];
  RobotKeyComputeFailure? generateFailure;

  _Keys(this._pairs);

  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async {
    final made = generated.where((id) => id == identity.hashId).length;
    generated.add(identity.hashId);
    if (generateFailure case final failure?) return Err(failure);
    final pairs = _pairs[identity.hashId] ?? const <RobotPgpKey>[];
    if (pairs.isEmpty) throw StateError('no pair made for this robot');
    return Ok(pairs[made % pairs.length]);
  }

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) async {
    proved.add(robot.hashId);
    return Ok(robot.prove());
  }
}

/// The sessions of the transport, whose closes are noted in [events].
final class _Sessions implements CoordinatorSessionsPort {
  final List<String> events;
  final List<RobotSessionKey> closed = [];

  _Sessions(this.events);

  @override
  Future<void> closeSessions() async => events.add('close all');

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async {
    closed.add(robot);
    events.add('close');
  }
}

typedef _Shown =
    Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>;

RobotOnCoordinatorFace _face(_Shown result) => switch (result) {
  Ok(value: Ok(:final value)) => value,
  Ok(value: Err(:final failure)) => fail('answered ${failure.runtimeType}'),
  Err(:final failure) => fail('refused ${failure.runtimeType}'),
};

CoordinatorRobot _robotOf(
  Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure> result,
) => switch (result) {
  Ok(value: Ok(:final value)) => value,
  Ok(value: Err(:final failure)) => fail('answered ${failure.runtimeType}'),
  Err(:final failure) => fail('refused ${failure.runtimeType}'),
};

Matcher _refused<T>() =>
    isA<Err<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>>()
        .having((err) => err.failure, 'failure', isA<T>());

Matcher _answered<T>() =>
    isA<Ok<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>>()
        .having(
          (ok) => ok.value,
          'answer',
          isA<Err<RobotOnCoordinatorFace, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<T>(),
          ),
        );

Matcher _sent<T>(T value) =>
    isA<Ok<T, P2pFailure>>().having((ok) => ok.value, 'value', value);

Matcher _failed<T, F>() =>
    isA<Err<T, P2pFailure>>().having((err) => err.failure, 'failure', isA<F>());

void main() {
  final robots = [for (var i = 0; i < 5; i++) _robotAt(i, _testnet)];
  final mainnetRobots = [for (var i = 0; i < 5; i++) _robotAt(i, _mainnet)];
  final keyOf = [for (final robot in robots) robot.identity.sessionKey];
  final temple = coordinator('temple');
  final lake = coordinator('lake');
  // Two pairs of robot 0, as two first contacts make them, and one of each other robot, each locked by its own token.
  final firstPair = _pairOf(robots[0]);
  final secondPair = _pairOf(robots[0]);
  final pairs = {
    robots[0].identity.hashId: [firstPair, secondPair],
    for (final robot in robots.skip(1)) robot.identity.hashId: [_pairOf(robot)],
  };

  test('the robots of the tests are five different indexes', () {
    expect(robots.map((robot) => robot.accountIndex).toSet(), hasLength(5));
    expect(
      mainnetRobots.map((robot) => robot.identity),
      robots.map((robot) => robot.identity),
    );
  });

  group('RobotRequestLimiter', () {
    late _Time time;
    late RobotRequestLimiter limiter;

    setUp(() {
      time = _Time();
      limiter = time.limiter();
    });

    bool never(Object? answer) => false;
    bool busyAnswer(String answer) => answer == 'busy';

    test(
      'two requests in flight per coordinator, the others in the order asked',
      () async {
        final started = <int>[];
        final gates = List.generate(5, (_) => Completer<String>());
        final results = [
          for (var i = 0; i < 5; i++)
            limiter.open(keyOf[i]).send(_testnet, temple, () {
              started.add(i);
              return gates[i].future;
            }, isBusy: never),
        ];
        await _settle();
        expect(started, [0, 1]);

        gates[1].complete('1');
        await _settle();
        expect(started, [0, 1, 2]);
        gates[0].complete('0');
        await _settle();
        expect(started, [0, 1, 2, 3]);
        gates[3].complete('3');
        await _settle();
        expect(started, [0, 1, 2, 3, 4]);
        gates[2].complete('2');
        gates[4].complete('4');
        for (var i = 0; i < 5; i++) {
          expect(await results[i], _sent('$i'));
        }
      },
    );

    test(
      'another coordinator, or the same on the other network, has places of its own',
      () async {
        final started = <String>[];
        final hold = Completer<String>();
        for (var i = 0; i < 3; i++) {
          unawaited(
            limiter.open(keyOf[i]).send(_testnet, temple, () {
              started.add('temple $i');
              return hold.future;
            }, isBusy: never),
          );
        }
        unawaited(
          limiter.open(keyOf[3]).send(_testnet, lake, () {
            started.add('lake');
            return hold.future;
          }, isBusy: never),
        );
        unawaited(
          limiter.open(keyOf[4]).send(_mainnet, temple, () {
            started.add('mainnet temple');
            return hold.future;
          }, isBusy: never),
        );
        await _settle();

        expect(started, ['temple 0', 'temple 1', 'lake', 'mainnet temple']);
        hold.complete('done');
        await _settle();
        expect(started, contains('temple 2'));
      },
    );

    test(
      'a request that throws, or ends on a failure, gives its place back',
      () async {
        final requests = limiter.open(keyOf[0]);

        await expectLater(
          requests.send<String>(
            _testnet,
            temple,
            () async => throw StateError('a bug'),
            isBusy: never,
          ),
          throwsStateError,
        );
        expect(
          await requests.send<Result<String, CoordinatorFailure>>(
            _testnet,
            temple,
            () async => const Err(CoordinatorTimedOut()),
            isBusy: never,
          ),
          isA<Ok<Result<String, CoordinatorFailure>, P2pFailure>>(),
        );
        // Both places are free: two requests that never end both start.
        final started = <int>[];
        for (var i = 1; i < 3; i++) {
          unawaited(
            limiter.open(keyOf[i]).send(_testnet, temple, () {
              started.add(i);
              return Completer<String>().future;
            }, isBusy: never),
          );
        }
        await _settle();
        expect(started, [1, 2]);
      },
    );

    test(
      'the waiting requests of a released robot are dropped, and the others keep their turn',
      () async {
        // Robots 1 and 2 hold both places of temple.
        final gates = [Completer<String>(), Completer<String>()];
        final holding = [
          for (var i = 0; i < 2; i++)
            limiter
                .open(keyOf[i + 1])
                .send(_testnet, temple, () => gates[i].future, isBusy: never),
        ];
        final started = <String>[];
        Future<Result<String, P2pFailure>> ask(
          RobotRequests requests,
          String name,
        ) => requests.send(_testnet, temple, () async {
          started.add(name);
          return name;
        }, isBusy: never);
        // Robot 0 waits twice, robot 3 once in between, and a call of robot 0 has not sent yet.
        final first = ask(limiter.open(keyOf[0]), 'robot 0, first');
        final other = ask(limiter.open(keyOf[3]), 'robot 3');
        final second = ask(limiter.open(keyOf[0]), 'robot 0, second');
        final idle = limiter.open(keyOf[0]);
        await _settle();
        expect(limiter.isInUse(keyOf[0]), isTrue);

        final release = limiter.release(keyOf[0]);

        expect(await first, _failed<String, RobotReleasedFailure>());
        expect(await second, _failed<String, RobotReleasedFailure>());
        expect(
          await ask(idle, 'robot 0, after'),
          _failed<String, RobotReleasedFailure>(),
        );
        expect(limiter.isInUse(keyOf[0]), isFalse);
        expect(await release.endedInTime, isTrue);
        gates[0].complete('1');
        expect(await other, _sent('robot 3'));
        // A call opened after the release is not affected.
        gates[1].complete('2');
        expect(
          await ask(limiter.open(keyOf[0]), 'robot 0, again'),
          _sent('robot 0, again'),
        );
        expect(started, ['robot 3', 'robot 0, again']);
        expect(await holding[0], _sent('1'));
        expect(await holding[1], _sent('2'));
      },
    );

    test(
      'no robot starves, however many requests another one keeps asking',
      () async {
        final started = <String>[];
        final gates = <String, Completer<String>>{};
        Future<Result<String, P2pFailure>> ask(int robot, String name) {
          final gate = gates[name] = Completer<String>();
          return limiter.open(keyOf[robot]).send(_testnet, temple, () {
            started.add(name);
            return gate.future;
          }, isBusy: never);
        }

        // Robot 0 keeps two requests in flight and two waiting, and asks again each time one ends.
        for (final name in ['a1', 'a2', 'a3', 'a4']) {
          unawaited(ask(0, name));
        }
        final asked = ask(1, 'b');
        await _settle();
        for (var n = 1; !started.contains('b'); n++) {
          if (n > 3) fail('robot 1 starved: $started');
          gates['a$n']?.complete('a$n');
          unawaited(ask(0, 'a${n + 4}'));
          await _settle();
        }

        expect(started, ['a1', 'a2', 'a3', 'a4', 'b']);
        gates['b']?.complete('b');
        expect(await asked, _sent('b'));
      },
    );

    test(
      'a request answered busy 1, 2 or 3 times is sent again after 2, 4 and 8 s; 4 times, it fails',
      () async {
        for (final busy in [1, 2, 3, 4]) {
          final time = _Time();
          var attempts = 0;

          final result = await time
              .limiter()
              .open(keyOf[0])
              .send(
                _testnet,
                temple,
                () async => ++attempts <= busy ? 'busy' : 'answer',
                isBusy: busyAnswer,
              );

          if (busy < RobotRequestLimiter.maxAttempts) {
            expect(result, _sent('answer'), reason: '$busy');
            expect(attempts, busy + 1);
          } else {
            expect(result, _failed<String, RobotCoordinatorBusyFailure>());
            expect(attempts, 4);
          }
          expect(
            time.waits,
            const [
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
            ].take(busy < 3 ? busy : 3),
            reason: '$busy',
          );
        }
      },
    );

    test('each wait is spread by up to 20 % either way, at random', () async {
      Future<List<Duration>> waitsWith(List<double> draws) async {
        final time = _Time(draws);
        var attempts = 0;
        await time
            .limiter()
            .open(keyOf[0])
            .send(
              _testnet,
              temple,
              () async => ++attempts <= 3 ? 'busy' : 'answer',
              isBusy: busyAnswer,
            );
        return time.waits;
      }

      expect(await waitsWith([0, 0.25, 0.75]), const [
        Duration(milliseconds: 1600),
        Duration(milliseconds: 3600),
        Duration(milliseconds: 8800),
      ]);
      // A draw outside 0 to 1 counts as its nearest end.
      expect(await waitsWith([1, 0.5, 7]), const [
        Duration(milliseconds: 2400),
        Duration(seconds: 4),
        Duration(milliseconds: 9600),
      ]);
      expect(await waitsWith([-1, -1, -1]), const [
        Duration(milliseconds: 1600),
        Duration(milliseconds: 3200),
        Duration(milliseconds: 6400),
      ]);
      for (var i = 0; i < 100; i++) {
        final waits = await waitsWith([i / 100]);
        for (final (index, wait) in waits.indexed) {
          final base = RobotRequestLimiter.busyWaits[index];
          expect(wait, greaterThanOrEqualTo(base * 0.8));
          expect(wait, lessThanOrEqualTo(base * 1.2));
        }
      }
    });

    test(
      'a request answered busy waits holding no place, then queues behind the requests asked meanwhile',
      () async {
        time.holding = true;
        final started = <String>[];
        var attempts = 0;
        final retried = limiter.open(keyOf[0]).send(_testnet, temple, () async {
          started.add('robot 0');
          return ++attempts == 1 ? 'busy' : 'answer';
        }, isBusy: busyAnswer);
        await _settle();
        expect(time.held, hasLength(1));
        final gates = [Completer<String>(), Completer<String>()];
        for (var i = 0; i < 2; i++) {
          unawaited(
            limiter.open(keyOf[i + 1]).send(_testnet, temple, () {
              started.add('robot ${i + 1}');
              return gates[i].future;
            }, isBusy: never),
          );
        }
        await _settle();
        expect(started, ['robot 0', 'robot 1', 'robot 2']);

        time.held.single.complete();
        await _settle();
        expect(started, hasLength(3));
        gates[0].complete('1');
        expect(await retried, _sent('answer'));
        expect(started, ['robot 0', 'robot 1', 'robot 2', 'robot 0']);
      },
    );

    test(
      'a robot released while it waits out a busy answer sends nothing more',
      () async {
        time.holding = true;
        var attempts = 0;
        final retried = limiter.open(keyOf[0]).send(_testnet, temple, () async {
          attempts++;
          return 'busy';
        }, isBusy: busyAnswer);
        await _settle();

        expect(await limiter.release(keyOf[0]).endedInTime, isTrue);
        time.held.single.complete();

        expect(await retried, _failed<String, RobotReleasedFailure>());
        expect(attempts, 1);
      },
    );

    test(
      'more than 12 busy answers in 10 minutes refuse a coordinator at once, until they are older',
      () async {
        var attempts = 0;
        Future<Result<String, P2pFailure>> ask(
          RobosatsNetwork network,
          Coordinator coordinator, {
          String answer = 'busy',
        }) => limiter.open(keyOf[0]).send(network, coordinator, () async {
          attempts++;
          return answer;
        }, isBusy: busyAnswer);

        for (var i = 0; i < 3; i++) {
          expect(
            await ask(_testnet, temple),
            _failed<String, RobotCoordinatorBusyFailure>(),
          );
        }
        expect(attempts, 12);
        final waits = time.waits.length;
        // The 13th busy answer: no wait, no further attempt.
        expect(
          await ask(_testnet, temple),
          _failed<String, RobotCoordinatorBusyFailure>(),
        );
        expect(attempts, 13);
        expect(time.waits, hasLength(waits));
        // Then nothing is sent there at all.
        expect(
          await ask(_testnet, temple, answer: 'answer'),
          _failed<String, RobotCoordinatorBusyFailure>(),
        );
        expect(attempts, 13);
        // Another coordinator, or the same on the other network, is not affected.
        expect(await ask(_testnet, lake, answer: 'answer'), _sent('answer'));
        expect(await ask(_mainnet, temple, answer: 'answer'), _sent('answer'));
        expect(attempts, 15);
        // Until the 13 answers are ten minutes old.
        time.elapsed =
            RobotRequestLimiter.busyWindow - const Duration(microseconds: 1);
        expect(
          await ask(_testnet, temple, answer: 'answer'),
          _failed<String, RobotCoordinatorBusyFailure>(),
        );
        time.elapsed = RobotRequestLimiter.busyWindow;
        expect(await ask(_testnet, temple, answer: 'answer'), _sent('answer'));
        expect(attempts, 16);
      },
    );

    test(
      'a robot released in the instant its request got a place sends nothing',
      () async {
        var sent = false;
        final asked = limiter.open(keyOf[0]).send(_testnet, temple, () async {
          sent = true;
          return 'answer';
        }, isBusy: never);
        // The same turn of the event loop: the place is taken, the request not run yet.
        final release = limiter.release(keyOf[0]);

        expect(await asked, _failed<String, RobotReleasedFailure>());
        expect(sent, isFalse);
        expect(await release.endedInTime, isTrue);
        // Its place was given back.
        final started = <int>[];
        for (var i = 1; i < 3; i++) {
          unawaited(
            limiter.open(keyOf[i]).send(_testnet, temple, () {
              started.add(i);
              return Completer<String>().future;
            }, isBusy: never),
          );
        }
        await _settle();
        expect(started, [1, 2]);
      },
    );

    test(
      'a request that waited while its coordinator turned busy is not sent',
      () async {
        // Twelve busy answers already.
        for (var i = 0; i < 3; i++) {
          await limiter
              .open(keyOf[3])
              .send(_testnet, temple, () async => 'busy', isBusy: busyAnswer);
        }
        final started = <String>[];
        final gates = [Completer<String>(), Completer<String>()];
        final holding = [
          for (var i = 0; i < 2; i++)
            limiter.open(keyOf[i + 1]).send(_testnet, temple, () {
              started.add('robot ${i + 1}');
              return gates[i].future;
            }, isBusy: busyAnswer),
        ];
        final waiting = limiter.open(keyOf[0]).send(_testnet, temple, () async {
          started.add('robot 0');
          return 'answer';
        }, isBusy: busyAnswer);
        await _settle();

        // The 13th busy answer frees a place for robot 0, and refuses the coordinator first.
        gates[0].complete('busy');

        expect(
          await holding[0],
          _failed<String, RobotCoordinatorBusyFailure>(),
        );
        expect(await waiting, _failed<String, RobotCoordinatorBusyFailure>());
        expect(started, ['robot 1', 'robot 2']);
        gates[1].complete('answer');
        expect(await holding[1], _sent('answer'));
      },
    );

    test(
      'first contacts are refused once a coordinator refused three nicknames, there only',
      () {
        for (var i = 0; i < RobotRequestLimiter.maxNicknameRefusals; i++) {
          expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
          limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
        }

        expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        expect(limiter.holdFirstContactSlot(_testnet, temple), isNull);
        expect(limiter.refusesFirstContacts(_testnet, lake), isFalse);
        expect(limiter.refusesFirstContacts(_mainnet, temple), isFalse);
      },
    );

    test('the caps of the two networks are apart, mainnet\'s included', () {
      for (var i = 0; i < RobotRequestLimiter.maxNicknameRefusals; i++) {
        limiter.holdFirstContactSlot(_mainnet, temple)?.end(refused: true);
      }

      expect(limiter.refusesFirstContacts(_mainnet, temple), isTrue);
      expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
      limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
      expect(limiter.refusesFirstContacts(_mainnet, lake), isFalse);
    });

    test(
      'a first contact still running holds its slot of the cap, given back unless refused',
      () {
        final slots = [
          for (var i = 0; i < RobotRequestLimiter.maxNicknameRefusals; i++)
            limiter.holdFirstContactSlot(_testnet, temple),
        ];
        expect(slots, everyElement(isNotNull));
        // Three first contacts running take the three slots.
        expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        expect(limiter.holdFirstContactSlot(_testnet, temple), isNull);
        slots[0]?.end(refused: false);
        // Ending a slot twice changes nothing.
        slots[0]?.end(refused: true);
        expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
        slots[1]?.end(refused: true);
        slots[2]?.end(refused: true);
        limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
        expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
      },
    );

    test(
      'a released call stops waiting at once, a busy wait or the wait before its request',
      () async {
        time.holding = true;
        var attempts = 0;
        final retried = limiter.open(keyOf[0]).send(_testnet, temple, () async {
          attempts++;
          return 'busy';
        }, isBusy: busyAnswer);
        final later = limiter
            .open(keyOf[0])
            .send(
              _testnet,
              temple,
              () async => 'answer',
              isBusy: busyAnswer,
              after: RobotRequestLimiter.nicknameRecheckWait,
            );
        await _until(() => time.held.length == 2);

        limiter.release(keyOf[0]);

        // Neither held wait is over: the release ends them.
        expect(await retried, _failed<String, RobotReleasedFailure>());
        expect(await later, _failed<String, RobotReleasedFailure>());
        expect(attempts, 1);
      },
    );

    test(
      'a busy answer to a call released while in flight counts for its coordinator',
      () async {
        // Twelve busy answers already.
        for (var i = 0; i < 3; i++) {
          await limiter
              .open(keyOf[3])
              .send(_testnet, temple, () async => 'busy', isBusy: busyAnswer);
        }
        final gate = Completer<String>();
        final inFlight = limiter
            .open(keyOf[0])
            .send(_testnet, temple, () => gate.future, isBusy: busyAnswer);
        await _settle();
        final release = limiter.release(keyOf[0]);

        gate.complete('busy');

        expect(await inFlight, _failed<String, RobotCoordinatorBusyFailure>());
        await release.ended;
        // The 13th answer was counted: nothing more is sent there.
        var sent = false;
        expect(
          await limiter.open(keyOf[1]).send(_testnet, temple, () async {
            sent = true;
            return 'answer';
          }, isBusy: busyAnswer),
          _failed<String, RobotCoordinatorBusyFailure>(),
        );
        expect(sent, isFalse);
      },
    );

    test(
      'a second release waits for the requests the first one let run',
      () async {
        time.holding = true;
        final gate = Completer<String>();
        final inFlight = limiter
            .open(keyOf[0])
            .send(_testnet, temple, () => gate.future, isBusy: never);
        await _settle();

        final first = limiter.release(keyOf[0]);
        final second = limiter.release(keyOf[0]);
        var ended = false;
        unawaited(second.ended.then((_) => ended = true));
        await _settle();
        expect(ended, isFalse);
        gate.complete('answer');

        expect(await inFlight, _sent('answer'));
        expect(await first.endedInTime, isTrue);
        expect(await second.endedInTime, isTrue);
        // Once it has ended, a third release has nothing to wait for.
        final third = limiter.release(keyOf[0]);
        expect(await third.endedInTime, isTrue);
        expect(time.waits, hasLength(2));
      },
    );
  });

  group('the robot use cases,', () {
    late _Time time;
    late _Coordinators coordinators;
    late RobotBindingRepositoryImpl bindings;
    late _Keys keys;
    late RobotRequestLimiter limiter;
    late FetchRobotUsecase fetch;
    late PutRobotOnCoordinatorUsecase put;
    late ReadRobotOnCoordinatorUsecase read;

    /// The binding of [robot], as the database has it.
    Future<RobotBinding?> bindingOf(NetworkRobot robot) async =>
        switch (await bindings.standingOf(robot.slot)) {
          Ok(:final value) => value.binding,
          Err(:final failure) => fail('unreadable: ${failure.runtimeType}'),
        };

    setUp(() async {
      time = _Time();
      coordinators = _Coordinators(robots);
      bindings = bindingsInMemory();
      // The test key, as if this device had drawn it for both networks.
      for (final network in RobosatsNetwork.values) {
        expect(
          await bindings.recordGeneratedKey(network, robots[0].keyFingerprint),
          isA<Ok<void, P2pFailure>>(),
        );
      }
      keys = _Keys(pairs);
      limiter = time.limiter();
      fetch = FetchRobotUsecase(
        CoordinatorClient(coordinators),
        bindings,
        keys,
      );
      put = PutRobotOnCoordinatorUsecase(fetch, bindings, limiter);
      read = ReadRobotOnCoordinatorUsecase(
        fetch,
        bindings,
        limiter,
        Federation.robosats,
      );
    });

    group('a first contact,', () {
      test('makes its pair once, and sends it at each of its requests', () async {
        final contact = RobotContact.firstContact(robots[0]);
        coordinators.script.add(_Reply.busy);

        expect(
          FetchRobotUsecase.answeredBusy(await fetch.execute(temple, contact)),
          isTrue,
        );
        final robot = _robotOf(await fetch.execute(temple, contact));

        expect(keys.generated, [robots[0].identity.hashId]);
        expect(
          coordinators.requests.map(_sentPublicKey),
          everyElement(firstPair.publicKey.armored),
        );
        expect(coordinators.requests, hasLength(2));
        expect(contact.sentThePairOf(robot), isTrue);
        expect(robot.pgpKeyProven, isFalse);
        // Another first contact is another request of the user: it makes a pair of its own.
        await fetch.execute(temple, RobotContact.firstContact(robots[0]));
        expect(keys.generated, hasLength(2));
        expect(
          _sentPublicKey(coordinators.requests.last),
          secondPair.publicKey.armored,
        );
      });

      test(
        'a pair that could not be made is made at its next request',
        () async {
          final contact = RobotContact.firstContact(robots[0]);
          keys.generateFailure = const RobotKeyComputeFailure();

          expect(
            await fetch.execute(temple, contact),
            isA<
              Err<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>
            >(),
          );
          expect(coordinators.requests, isEmpty);
          keys.generateFailure = null;
          final robot = _robotOf(await fetch.execute(temple, contact));

          expect(keys.generated, hasLength(2));
          expect(coordinators.requests, hasLength(1));
          expect(contact.sentThePairOf(robot), isTrue);
          // A contact that sent nothing sent no pair.
          expect(
            RobotContact.firstContact(robots[0]).sentThePairOf(robot),
            isFalse,
          );
        },
      );

      test('tells a robot that came back with another pair', () async {
        coordinators.keepFor(robots[0], 'temple', _testnet, secondPair);
        final contact = RobotContact.firstContact(robots[0]);

        final robot = _robotOf(await fetch.execute(temple, contact));

        expect(robot.pgpKeyProven, isTrue);
        expect(contact.sentThePairOf(robot), isFalse);
      });
    });

    group('PutRobotOnCoordinatorUsecase', () {
      test(
        'puts a robot on the coordinator, with the pair it made and the Nostr key of the official client',
        () async {
          final face = _face(await put.execute(robots[0], temple));

          expect(
            face,
            RobotOnCoordinatorFace(
              activeOrderId: null,
              lastOrderId: null,
              earnedRewards: Sats.fromInt(0),
              nostrKey: RobotNostrKeyStatus.current,
              alreadyExisted: false,
            ),
          );
          expect(coordinators.requests, hasLength(1));
          expect(
            _sentPublicKey(coordinators.requests.single),
            firstPair.publicKey.armored,
          );
          expect(
            coordinators.requests.single.url.host,
            hostOf('temple', _testnet),
          );
          expect(keys.proved, isEmpty);
          expect(time.waits, isEmpty);
          expect(limiter.isInUse(keyOf[0]), isFalse);
        },
      );

      test(
        'a robot that already existed there comes back with its own pair, proven',
        () async {
          coordinators.keepFor(
            robots[0],
            'temple',
            _testnet,
            secondPair,
            fields: {'active_order_id': 41, 'earned_rewards': 1200},
          );

          final face = _face(await put.execute(robots[0], temple));

          expect(face.alreadyExisted, isTrue);
          expect(face.activeOrderId, 41);
          expect(face.earnedRewards, Sats.fromInt(1200));
          expect(keys.proved, [robots[0].identity.hashId]);
        },
      );

      test(
        'a busy transport: 1, 2 or 3 busy answers and the robot; 4, a failure',
        () async {
          for (final busy in [1, 2, 3, 4]) {
            final time = _Time();
            final coordinators = _Coordinators(robots)
              ..script.addAll(List.filled(busy, _Reply.busy));
            final keys = _Keys(pairs);
            final put = PutRobotOnCoordinatorUsecase(
              FetchRobotUsecase(
                CoordinatorClient(coordinators),
                bindings,
                keys,
              ),
              bindings,
              time.limiter(),
            );

            final result = await put.execute(robots[busy], temple);

            if (busy < 4) {
              expect(_face(result).alreadyExisted, isFalse, reason: '$busy');
              expect(coordinators.requests, hasLength(busy + 1));
            } else {
              expect(result, _refused<RobotCoordinatorBusyFailure>());
              expect(coordinators.requests, hasLength(4));
            }
            expect(
              time.waits,
              const [
                Duration(seconds: 2),
                Duration(seconds: 4),
                Duration(seconds: 8),
              ].take(busy < 3 ? busy : 3),
            );
            // One pair for the whole call, sent at every attempt.
            expect(keys.generated, [robots[busy].identity.hashId]);
            expect(
              coordinators.requests.map(_sentPublicKey).toSet(),
              hasLength(1),
            );
          }
          // The robot that got no answer is bound all the same: its token hash may have left on an earlier attempt of the transport.
          expect(
            await put.execute(robots[4], lake),
            _refused<RobotBoundToAnotherCoordinatorFailure>(),
          );
        },
      );

      test(
        'a retry sends the pair of the first attempt, which the coordinator may have stored',
        () async {
          // The coordinator stored the first attempt, and the transport gave a busy answer; a second pair would not be the one it holds.
          coordinators.script.addAll([_Reply.storedThenBusy, _Reply.busy]);

          final face = _face(await put.execute(robots[0], temple));

          expect(face.alreadyExisted, isFalse);
          expect(keys.generated, [robots[0].identity.hashId]);
          expect(keys.proved, isEmpty);
          expect(
            coordinators.requests.map(_sentPublicKey),
            everyElement(firstPair.publicKey.armored),
          );
          expect(coordinators.requests, hasLength(3));
        },
      );

      test('a request that timed out is not sent again', () async {
        coordinators.script.add(_Reply.timedOut);

        expect(
          await put.execute(robots[0], temple),
          _answered<CoordinatorTimedOut>(),
        );
        expect(coordinators.requests, hasLength(1));
        expect(time.waits, isEmpty);
        // The robot is bound there: the user's « Retry » reads it back first.
        expect(
          await put.execute(robots[0], lake),
          _refused<RobotBoundToAnotherCoordinatorFailure>(),
        );
      });

      test(
        'a nickname taken (7004) is read again 10 s later: a robot created meanwhile is taken',
        () async {
          // The coordinator created the robot for another copy of this request, and stored its token after the client's own read.
          coordinators.script.addAll([_Reply.nicknameTaken, _Reply.unknown]);
          coordinators.onSend = (request) async {
            if (coordinators.requests.length == 2) {
              coordinators.keepFor(robots[0], 'temple', _testnet, firstPair);
            }
          };

          final face = _face(await put.execute(robots[0], temple));

          expect(face.alreadyExisted, isFalse);
          expect(time.waits, [RobotRequestLimiter.nicknameRecheckWait]);
          expect(coordinators.requests.map(_sentPublicKey), [
            firstPair.publicKey.armored,
            null,
            null,
          ]);
          expect(keys.proved, [robots[0].identity.hashId]);
          expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
        },
      );

      test(
        'a nickname still taken stays bound there, and three refusals close the coordinator to first contacts',
        () async {
          for (var i = 0; i < 3; i++) {
            coordinators.script.addAll([
              _Reply.nicknameTaken,
              _Reply.unknown,
              _Reply.unknown,
            ]);
            expect(
              await put.execute(robots[i], temple),
              _answered<RobotNicknameTaken>(),
            );
            // Nothing moved to another robot, and the index stays bound to that coordinator.
            expect(
              await put.execute(robots[i], lake),
              _refused<RobotBoundToAnotherCoordinatorFailure>(),
            );
          }
          expect(coordinators.requests, hasLength(9));
          expect(
            time.waits,
            List.filled(3, RobotRequestLimiter.nicknameRecheckWait),
          );

          // The fourth robot is neither bound nor sent there.
          expect(
            await put.execute(robots[3], temple),
            _refused<RobotCoordinatorTooManyRefusalsFailure>(),
          );
          expect(coordinators.requests, hasLength(9));
          expect(await bindingOf(robots[3]), isNull);
          expect(
            _face(await put.execute(robots[3], lake)).alreadyExisted,
            isFalse,
          );
          // Reading back a robot bound there still goes.
          expect(await read.execute(robots[0]), _answered<RobotUnknown>());
          // The same coordinator on mainnet is another one.
          expect(
            _face(await put.execute(mainnetRobots[4], temple)).alreadyExisted,
            isFalse,
          );
        },
      );

      test(
        'a read after 7004 that does not answer is reported as such, and the refusal counts',
        () async {
          coordinators.script.addAll([
            _Reply.nicknameTaken,
            _Reply.unknown,
            _Reply.timedOut,
          ]);

          expect(
            await put.execute(robots[0], temple),
            _answered<CoordinatorTimedOut>(),
          );
          // Only a robot found clears a refusal: a coordinator that answered 7004 and then held the read would escape the cap otherwise.
          for (var i = 0; i < 2; i++) {
            expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
            limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
          }
          expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        },
      );

      test('a busy read after 7004 is sent again', () async {
        coordinators.script.addAll([
          _Reply.nicknameTaken,
          _Reply.unknown,
          _Reply.busy,
        ]);
        coordinators.keepFor(robots[0], 'temple', _testnet, secondPair);
        // The first request is answered from the script, then the coordinator answers with what it keeps.

        final face = _face(await put.execute(robots[0], temple));

        expect(face.alreadyExisted, isTrue);
        expect(time.waits, [
          RobotRequestLimiter.nicknameRecheckWait,
          const Duration(seconds: 2),
        ]);
        expect(coordinators.requests, hasLength(4));
      });

      test(
        'a pair that cannot be made sends nothing, and is not tried again',
        () async {
          keys.generateFailure = const RobotKeyComputeFailure();

          expect(
            await put.execute(robots[0], temple),
            _refused<RobotKeyComputeFailure>(),
          );
          expect(coordinators.requests, isEmpty);
          expect(keys.generated, hasLength(1));
          expect(limiter.isInUse(keyOf[0]), isFalse);
        },
      );

      test(
        'a coordinator refused for its busy answers gets neither the robot nor its binding',
        () async {
          for (var i = 0; i < RobotRequestLimiter.maxBusyAnswers + 1; i++) {
            coordinators.script.add(_Reply.busy);
          }
          for (var i = 0; i < 4; i++) {
            await put.execute(robots[i], temple);
          }
          expect(coordinators.requests, hasLength(13));
          expect(keys.generated, hasLength(4));

          expect(
            await put.execute(robots[4], temple),
            _refused<RobotCoordinatorBusyFailure>(),
          );
          expect(coordinators.requests, hasLength(13));
          expect(keys.generated, hasLength(4));
          expect(
            _face(await put.execute(robots[4], lake)).alreadyExisted,
            isFalse,
          );
        },
      );

      test('a robot released during its call sends nothing more', () async {
        time.holding = true;
        coordinators.script.add(_Reply.busy);
        final call = put.execute(robots[0], temple);
        await _until(() => time.held.length == 1);

        expect(await limiter.release(keyOf[0]).endedInTime, isTrue);
        time.held.single.complete();

        expect(await call, _refused<RobotReleasedFailure>());
        expect(coordinators.requests, hasLength(1));
      });

      test(
        'puts a robot of the mainnet key on a mainnet coordinator',
        () async {
          final face = _face(await put.execute(mainnetRobots[0], temple));

          expect(face.alreadyExisted, isFalse);
          expect(
            coordinators.requests.single.url.host,
            hostOf('temple', _mainnet),
          );
        },
      );

      test(
        'a robot bound there and known is read back, and sent no first contact',
        () async {
          // The coordinator stored the first contact, and its answer was lost.
          coordinators.script.add(_Reply.storedThenTimedOut);
          expect(
            await put.execute(robots[0], temple),
            _answered<CoordinatorTimedOut>(),
          );

          final face = _face(await put.execute(robots[0], temple));

          // Found by the read: a pair this call did not send.
          expect(face.alreadyExisted, isTrue);
          expect(coordinators.requests.map(_sentPublicKey), [
            firstPair.publicKey.armored,
            null,
          ]);
          expect(keys.generated, [robots[0].identity.hashId]);
          expect(keys.proved, [robots[0].identity.hashId]);
        },
      );

      test(
        'a robot bound there and unknown is read, then sent one first contact',
        () async {
          coordinators.script.add(_Reply.timedOut);
          await put.execute(robots[0], temple);

          final face = _face(await put.execute(robots[0], temple));

          expect(face.alreadyExisted, isFalse);
          expect(coordinators.requests.map(_sentPublicKey), [
            firstPair.publicKey.armored,
            null,
            secondPair.publicKey.armored,
          ]);
          expect(keys.proved, isEmpty);
        },
      );

      test(
        'the busy and 7004 rules hold on both requests of a robot bound there',
        () async {
          coordinators.script.add(_Reply.timedOut);
          await put.execute(robots[0], temple);
          coordinators.script.addAll([
            _Reply.busy,
            _Reply.unknown,
            _Reply.busy,
            _Reply.nicknameTaken,
            _Reply.unknown,
            _Reply.unknown,
          ]);

          expect(
            await put.execute(robots[0], temple),
            _answered<RobotNicknameTaken>(),
          );
          expect(time.waits, [
            const Duration(seconds: 2),
            const Duration(seconds: 2),
            RobotRequestLimiter.nicknameRecheckWait,
          ]);
          expect(coordinators.requests.map(_sentPublicKey), [
            firstPair.publicKey.armored,
            null,
            null,
            secondPair.publicKey.armored,
            secondPair.publicKey.armored,
            null,
            null,
          ]);
          // The refusal counted.
          for (var i = 0; i < 2; i++) {
            limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
          }
          expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        },
      );

      test(
        'a robot bound there whose read fails is sent no first contact',
        () async {
          _face(await put.execute(robots[0], temple));
          coordinators.script.add(_Reply.timedOut);

          expect(
            await put.execute(robots[0], temple),
            _answered<CoordinatorTimedOut>(),
          );
          expect(coordinators.requests.map(_sentPublicKey), [
            firstPair.publicKey.armored,
            null,
          ]);
          expect(keys.generated, hasLength(1));
        },
      );

      test(
        'a robot bound elsewhere is refused before its binding is asked again',
        () async {
          final recording = RecordingBindings(
            drawnHere: [
              for (final network in RobosatsNetwork.values)
                (network, robots[0].keyFingerprint),
            ],
          );
          expect(
            await recording.bind(
              robots[0].slot,
              CoordinatorIdentity.of(temple, _testnet) ??
                  fail('temple is not on testnet'),
            ),
            isA<Ok<void, P2pFailure>>(),
          );

          expect(
            await PutRobotOnCoordinatorUsecase(
              FetchRobotUsecase(
                CoordinatorClient(coordinators),
                recording,
                keys,
              ),
              recording,
              limiter,
            ).execute(robots[0], lake),
            _refused<RobotBoundToAnotherCoordinatorFailure>(),
          );
          expect(
            recording.calls.where((call) => call.$1 == 'bind'),
            hasLength(1),
          );
          expect(coordinators.requests, isEmpty);
        },
      );

      test(
        'a robot bound to a coordinator that changed since is sent nothing',
        () async {
          _face(await put.execute(robots[0], temple));
          final sent = coordinators.requests.length;
          final changed = _withNostrKey(temple, '1' * 64);

          expect(
            await put.execute(robots[0], changed),
            _refused<RobotCoordinatorChangedFailure>(),
          );
          expect(
            await put.execute(robots[0], lake),
            _refused<RobotBoundToAnotherCoordinatorFailure>(),
          );
          expect(coordinators.requests, hasLength(sent));
        },
      );

      test('a database that cannot be read sends nothing', () async {
        final failing = RecordingBindings()
          ..readFailure = const P2pStorageFailure();

        expect(
          await PutRobotOnCoordinatorUsecase(
            fetch,
            failing,
            limiter,
          ).execute(robots[0], temple),
          _refused<P2pStorageFailure>(),
        );
        expect(coordinators.requests, isEmpty);
        expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
      });

      test(
        'first contacts running at once never pass the cap of 7004 refusals',
        () async {
          for (var i = 0; i < 2; i++) {
            limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
          }
          coordinators.script.addAll(List.filled(6, _Reply.takenOrUnknown));

          final results = await Future.wait([
            put.execute(robots[0], temple),
            put.execute(robots[1], temple),
          ]);

          expect(
            results.where(
              (result) => _answered<RobotNicknameTaken>().matches(result, {}),
            ),
            hasLength(1),
          );
          expect(
            results.where(
              (result) => _refused<RobotCoordinatorTooManyRefusalsFailure>()
                  .matches(result, {}),
            ),
            hasLength(1),
          );
          // The one refused at once was neither bound nor sent.
          final refused =
              _refused<RobotCoordinatorTooManyRefusalsFailure>().matches(
                results[0],
                {},
              )
              ? robots[0]
              : robots[1];
          expect(await bindingOf(refused), isNull);
          expect(coordinators.of(refused), isEmpty);
          expect(coordinators.requests, hasLength(3));
          expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        },
      );

      test(
        'a refusal received counts though the robot is released during the wait, which ends at once',
        () async {
          time.holding = true;
          coordinators.script.addAll(List.filled(2, _Reply.takenOrUnknown));
          final call = put.execute(robots[0], temple);
          await _until(() => time.held.length == 1);
          expect(time.waits, [RobotRequestLimiter.nicknameRecheckWait]);

          limiter.release(keyOf[0]);

          // The wait of 10 s is not over: the release ends it.
          expect(await call, _refused<RobotReleasedFailure>());
          expect(coordinators.requests, hasLength(2));
          expect(await bindingOf(robots[0]), isNotNull);
          for (var i = 0; i < 2; i++) {
            expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
            limiter.holdFirstContactSlot(_testnet, temple)?.end(refused: true);
          }
          expect(limiter.refusesFirstContacts(_testnet, temple), isTrue);
        },
      );

      test(
        'a coordinator of mainnet that refused three robots refuses there only',
        () async {
          for (var i = 0; i < 3; i++) {
            coordinators.script.addAll(List.filled(3, _Reply.takenOrUnknown));
            expect(
              await put.execute(mainnetRobots[i], temple),
              _answered<RobotNicknameTaken>(),
            );
          }

          expect(
            await put.execute(mainnetRobots[3], temple),
            _refused<RobotCoordinatorTooManyRefusalsFailure>(),
          );
          expect(limiter.refusesFirstContacts(_testnet, temple), isFalse);
          expect(
            _face(await put.execute(robots[4], temple)).alreadyExisted,
            isFalse,
          );
        },
      );

      for (final (reply, failure) in [
        (_Reply.unreachable, 'unreachable'),
        (_Reply.failed, 'failed'),
      ]) {
        test('a transport that $failure is not sent again', () async {
          coordinators.script.add(reply);

          expect(
            await put.execute(robots[0], temple),
            reply == _Reply.unreachable
                ? _answered<CoordinatorUnreachable>()
                : _answered<CoordinatorTransportFailed>(),
          );
          expect(coordinators.requests, hasLength(1));
          expect(time.waits, isEmpty);
        });
      }
    });

    group('ReadRobotOnCoordinatorUsecase', () {
      test(
        'reads a robot back from the coordinator its binding names, with nothing held',
        () async {
          _face(await put.execute(robots[0], temple));
          coordinators.keepFor(
            robots[0],
            'temple',
            _testnet,
            firstPair,
            fields: {
              'last_order_id': 12,
              'earned_rewards': 21,
              'nostr_pubkey': robots[0].identity
                  .nostrKeyPair(NostrKeyDerivation.repositoryFixtures)
                  .publicKeyHex,
            },
          );

          final face = _face(await read.execute(robots[0]));

          expect(
            face,
            RobotOnCoordinatorFace(
              activeOrderId: null,
              lastOrderId: 12,
              earnedRewards: Sats.fromInt(21),
              nostrKey: RobotNostrKeyStatus.old,
              alreadyExisted: false,
            ),
          );
          final request = coordinators.requests.last;
          expect(request.url.host, hostOf('temple', _testnet));
          expect(
            request.headers['Authorization'],
            robots[0].identity.authorizationHeader(),
          );
          expect(keys.proved, [robots[0].identity.hashId]);
          expect(keys.generated, hasLength(1));
        },
      );

      test('a Nostr key the robot did not make is unknown', () async {
        _face(await put.execute(robots[0], temple));
        coordinators.keepFor(
          robots[0],
          'temple',
          _testnet,
          firstPair,
          fields: {'nostr_pubkey': '0' * 64},
        );

        expect(
          _face(await read.execute(robots[0])).nostrKey,
          RobotNostrKeyStatus.unknown,
        );
      });

      test(
        'a robot without a binding is not read, and nothing is sent or written',
        () async {
          expect(
            await read.execute(robots[1]),
            _refused<RobotNotBoundFailure>(),
          );
          expect(coordinators.requests, isEmpty);
          expect(keys.generated, isEmpty);
          expect(await bindingOf(robots[1]), isNull);
        },
      );

      test(
        'a robot bound on the other network is not read on this one',
        () async {
          _face(await put.execute(robots[0], temple));
          final sent = coordinators.requests.length;

          expect(
            await read.execute(mainnetRobots[0]),
            _refused<RobotBoundToAnotherCoordinatorFailure>(),
          );
          expect(coordinators.requests, hasLength(sent));
        },
      );

      test(
        'a coordinator the list no longer has on that network is a change, and nothing is sent',
        () async {
          _face(await put.execute(robots[0], temple));
          final sent = coordinators.requests.length;

          for (final federation in [
            // Removed from the list.
            Federation([
              for (final known in Federation.robosats.coordinators)
                if (known.shortAlias != 'temple') known,
            ]),
            // Still listed, without its testnet instance.
            Federation([
              for (final known in Federation.robosats.coordinators)
                known.shortAlias == 'temple' ? _withoutTestnet(known) : known,
            ]),
          ]) {
            expect(
              await ReadRobotOnCoordinatorUsecase(
                fetch,
                bindings,
                limiter,
                federation,
              ).execute(robots[0]),
              _refused<RobotCoordinatorChangedFailure>(),
            );
          }
          expect(coordinators.requests, hasLength(sent));
        },
      );

      test(
        'a robot bound on the other network is refused before its binding is asked again',
        () async {
          final recording = RecordingBindings(
            drawnHere: [
              for (final network in RobosatsNetwork.values)
                (network, robots[0].keyFingerprint),
            ],
          );
          expect(
            await recording.bind(
              robots[0].slot,
              CoordinatorIdentity.of(temple, _testnet) ??
                  fail('temple is not on testnet'),
            ),
            isA<Ok<void, P2pFailure>>(),
          );

          expect(
            await ReadRobotOnCoordinatorUsecase(
              FetchRobotUsecase(
                CoordinatorClient(coordinators),
                recording,
                keys,
              ),
              recording,
              limiter,
              Federation.robosats,
            ).execute(mainnetRobots[0]),
            _refused<RobotBoundToAnotherCoordinatorFailure>(),
          );
          expect(
            recording.calls.where((call) => call.$1 == 'bind'),
            hasLength(1),
          );
          expect(coordinators.requests, isEmpty);
        },
      );

      test('a database that cannot be read sends nothing', () async {
        final failing = RecordingBindings()
          ..readFailure = const P2pStorageFailure();

        expect(
          await ReadRobotOnCoordinatorUsecase(
            fetch,
            failing,
            limiter,
            Federation.robosats,
          ).execute(robots[0]),
          _refused<P2pStorageFailure>(),
        );
        expect(coordinators.requests, isEmpty);
      });

      test(
        'a robot bound there that the coordinator does not know is RobotUnknown',
        () async {
          coordinators.script.add(_Reply.timedOut);
          await put.execute(robots[0], temple);

          expect(await read.execute(robots[0]), _answered<RobotUnknown>());
          expect(keys.proved, isEmpty);
        },
      );

      test('a busy answer is sent again', () async {
        _face(await put.execute(robots[0], temple));
        coordinators.script.add(_Reply.busy);

        expect(_face(await read.execute(robots[0])).alreadyExisted, isFalse);
        expect(time.waits, [const Duration(seconds: 2)]);
      });

      test(
        'reads a robot of the mainnet key from its mainnet coordinator',
        () async {
          _face(await put.execute(mainnetRobots[0], temple));

          expect(
            _face(await read.execute(mainnetRobots[0])).alreadyExisted,
            isFalse,
          );
          expect(
            coordinators.requests.map((request) => request.url.host).toSet(),
            {hostOf('temple', _mainnet)},
          );
        },
      );

      test(
        'reads a robot from the coordinator its binding names, wherever the list puts it',
        () async {
          _face(await put.execute(robots[1], lake));
          _face(await put.execute(mainnetRobots[2], lake));
          final reversed = Federation([
            ...Federation.robosats.coordinators.reversed,
          ]);

          for (final federation in [Federation.robosats, reversed]) {
            final reading = ReadRobotOnCoordinatorUsecase(
              fetch,
              bindings,
              limiter,
              federation,
            );
            for (final (robot, network) in [
              (robots[1], _testnet),
              (mainnetRobots[2], _mainnet),
            ]) {
              _face(await reading.execute(robot));
              final request = coordinators.requests.last;
              expect(request.url.host, hostOf('lake', network));
              expect(
                request.headers['Authorization'],
                robot.identity.authorizationHeader(),
              );
            }
          }
          expect(coordinators.requests, hasLength(6));
        },
      );

      for (final (reply, failure) in [
        (_Reply.unreachable, 'unreachable'),
        (_Reply.failed, 'failed'),
      ]) {
        test('a transport that $failure is not sent again', () async {
          _face(await put.execute(robots[0], temple));
          coordinators.script.add(reply);

          expect(
            await read.execute(robots[0]),
            reply == _Reply.unreachable
                ? _answered<CoordinatorUnreachable>()
                : _answered<CoordinatorTransportFailed>(),
          );
          expect(coordinators.requests, hasLength(2));
          expect(time.waits, isEmpty);
        });
      }
    });

    group('ReleaseRobotUsecase', () {
      late List<String> events;
      late _Sessions sessions;
      late ReleaseRobotUsecase release;

      setUp(() {
        events = [];
        sessions = _Sessions(events);
        release = ReleaseRobotUsecase(
          limiter,
          CloseRobotSessionsUsecase(sessions),
        );
      });

      test(
        'with nothing in flight, closes the sessions of the robot at once',
        () async {
          await release.execute(robots[0]);

          expect(sessions.closed, [keyOf[0]]);
          expect(time.waits, isEmpty);
        },
      );

      test(
        'closes the sessions once the request in flight has ended, whose answer still comes',
        () async {
          _face(await put.execute(robots[0], temple));
          // The bound of the release does not pass in this test.
          time.holding = true;
          final answer = Completer<void>();
          coordinators.onSend = (request) async {
            events.add('sent');
            await answer.future;
            events.add('answered');
          };
          final reading = read.execute(robots[0]);
          await _until(() => events.contains('sent'));

          final releasing = release.execute(robots[0]);
          await _settle();
          expect(sessions.closed, isEmpty);
          answer.complete();
          await releasing;

          expect(events, ['sent', 'answered', 'close']);
          expect(_face(await reading).alreadyExisted, isFalse);
          expect(time.waits, [RobotRequestLimiter.releaseWait]);
        },
      );

      test(
        'drops the requests of the robot still waiting for a place',
        () async {
          // Robots 1 and 2 hold both places of temple.
          final answer = Completer<void>();
          coordinators.onSend = (request) => answer.future;
          final holding = [
            for (var i = 1; i < 3; i++) put.execute(robots[i], temple),
          ];
          await _until(() => coordinators.requests.length == 2);
          final putting = put.execute(robots[0], temple);
          await _settle();

          await release.execute(robots[0]);

          expect(await putting, _refused<RobotReleasedFailure>());
          expect(coordinators.of(robots[0]), isEmpty);
          expect(sessions.closed, [keyOf[0]]);
          answer.complete();
          for (final call in holding) {
            expect(_face(await call).alreadyExisted, isFalse);
          }
          // The robot dropped before its binding is free to go elsewhere.
          expect(
            _face(await put.execute(robots[0], lake)).alreadyExisted,
            isFalse,
          );
        },
      );

      test(
        'closes at the bound, then again once a late request has ended',
        () async {
          _face(await put.execute(robots[0], temple));
          time.holding = true;
          final answer = Completer<void>();
          coordinators.onSend = (request) async {
            events.add('sent');
            await answer.future;
            events.add('answered');
          };
          final reading = read.execute(robots[0]);
          await _until(() => events.contains('sent'));

          final releasing = release.execute(robots[0]);
          await _settle();
          expect(time.waits, [RobotRequestLimiter.releaseWait]);
          time.held.single.complete();
          await _until(() => events.contains('close'));
          expect(events, ['sent', 'close']);
          answer.complete();
          await releasing;

          expect(events, ['sent', 'close', 'answered', 'close']);
          await reading;
        },
      );

      test('leaves the sessions to a call of the robot opened since', () async {
        _face(await put.execute(robots[0], temple));
        time.holding = true;
        final answers = [Completer<void>(), Completer<void>()];
        var sent = 0;
        coordinators.onSend = (request) => answers[sent++].future;
        final first = read.execute(robots[0]);
        await _until(() => sent == 1);

        final releasing = release.execute(robots[0]);
        // The user comes back to the robot at once.
        final second = read.execute(robots[0]);
        await _until(() => sent == 2);
        answers[0].complete();
        await releasing;

        expect(sessions.closed, isEmpty);
        answers[1].complete();
        await first;
        _face(await second);
        await release.execute(robots[0]);
        expect(sessions.closed, [keyOf[0]]);
      });

      test(
        'a second release waits too for the request the first one let run',
        () async {
          _face(await put.execute(robots[0], temple));
          time.holding = true;
          final answer = Completer<void>();
          coordinators.onSend = (request) async {
            events.add('sent');
            await answer.future;
            events.add('answered');
          };
          final reading = read.execute(robots[0]);
          await _until(() => events.contains('sent'));

          final first = release.execute(robots[0]);
          final second = release.execute(robots[0]);
          await _settle();
          expect(events, ['sent']);
          answer.complete();
          await first;
          await second;

          // No close came before the answer: a first contact's answer is never cut off by a second release.
          expect(events, ['sent', 'answered', 'close', 'close']);
          expect(_face(await reading).alreadyExisted, isFalse);
        },
      );
    });

    test(
      'nothing printed or logged on these paths holds a credential or a key',
      () async {
        final identity = robots[0].identity;
        final events = <String>[];
        final output = await captureKeyOutput(() async {
          coordinators.script.addAll([
            _Reply.busy,
            _Reply.nicknameTaken,
            _Reply.unknown,
            _Reply.unknown,
          ]);
          await put.execute(robots[0], temple);
          coordinators.keepFor(robots[0], 'temple', _testnet, firstPair);
          await read.execute(robots[0]);
          await put.execute(robots[1], temple);
          await read.execute(robots[2]);
          await ReleaseRobotUsecase(
            limiter,
            CloseRobotSessionsUsecase(_Sessions(events)),
          ).execute(robots[0]);
        });

        expect(events, ['close']);
        expectNoKeyIn(output, [_garageKey]);
        for (final (index, secret) in [
          identity.token.reveal(),
          identity.tokenSha256Hex,
          identity.tokenSha256Base91,
          identity.authorizationHeader(),
          firstPair.encryptedPrivateKeyArmored.split('\n')[3],
          pgpArmorToWire(firstPair.publicKey.armored),
        ].indexed) {
          expect(output.contains(secret), isFalse, reason: 'form $index');
        }
      },
    );
  });
}
