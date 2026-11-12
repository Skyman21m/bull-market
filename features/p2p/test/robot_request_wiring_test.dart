import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart';

/// A coordinator that keeps the pair of the first contact of each robot, as the reference coordinator does, and answers every later request with it.
///
/// It knows the robot it serves ([identity]) so that its answers carry the right hash id and nickname; it reads the keys from the first-contact header.
final class _KeepingCoordinator implements CoordinatorTransport {
  final List<CoordinatorRequest> requests = [];
  RobotIdentity? identity;
  ({String publicKey, String privateKey})? _kept;

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    final parts = (request.headers['Authorization'] ?? '').split(' | ');
    if (parts.length == 4) {
      _kept ??= (
        publicKey: pgpArmorFromWire(parts[1].substring('Public '.length)),
        privateKey: pgpArmorFromWire(parts[2].substring('Private '.length)),
      );
    }
    final kept = _kept;
    if (kept == null) {
      return Ok(_json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
    }
    final robot = identity;
    if (robot == null) return const Err(CoordinatorTransportFailed());
    return Ok(
      _json(200, {
        'nickname': robot.nickname,
        'hash_id': robot.hashId.hex,
        'public_key': kept.publicKey,
        'encrypted_private_key': kept.privateKey,
      }),
    );
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

/// The robot path as the feature registers it, run offline end to end: the real vault on its in-memory keystore, the database in memory, the real isolate port, `FetchRobotUsecase` as the locator builds it.
///
/// The live test cannot take this path: the only vault a test can make replaces the keystore of the whole process, which the other integration tests run in after it.
void main() {
  const network = RobosatsNetwork.testnet;
  late GetIt locator;
  late _KeepingCoordinator coordinator;

  setUp(() {
    FakeSecureStoragePlatform().install();
    coordinator = _KeepingCoordinator();
    locator = GetIt.asNewInstance();
    setUpP2pForTesting(
      locator,
      transport: coordinator,
      torStates: () => Stream.value(P2pTorState.ready),
      clock: () => testNow,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
  });

  tearDown(() => locator.reset());

  test(
    'creates a robot, then reads it back with nothing held, its pair proven in an isolate',
    () async {
      final temple = Federation.robosats
          .on(network)
          .firstWhere((candidate) => candidate.shortAlias == 'temple');
      final lake = Federation.robosats
          .on(network)
          .firstWhere((candidate) => candidate.shortAlias == 'lake');
      // « Generate Garage Key », then robot number 0, as the Garage gets them.
      expect(
        await locator<GenerateGarageKeyUsecase>().execute(network),
        isA<Ok<GarageKeyHistory, P2pFailure>>().having(
          (ok) => ok.value,
          'history',
          GarageKeyHistory.drawnHere,
        ),
      );
      final robot = switch (await locator<DeriveFirstRobotUsecase>().execute(
        network,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      coordinator.identity = robot.identity;
      final fetch = locator<FetchRobotUsecase>();

      CoordinatorRobot robotOf(
        Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure> result,
      ) => switch (result) {
        Ok(value: Ok(:final value)) => value,
        Ok(value: Err(failure: final Object failure)) ||
        Err(failure: final Object failure) => fail('$failure'),
      };

      // The coordinator does not know the robot yet.
      expect(
        await fetch.execute(temple, robot, createIfUnknown: false),
        isA<Ok<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>()
            .having(
              (ok) => ok.value,
              'answer',
              isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
                (err) => err.failure,
                'failure',
                isA<RobotUnknown>(),
              ),
            ),
      );
      final created = robotOf(
        await fetch.execute(temple, robot, createIfUnknown: true),
      );
      final readBack = robotOf(
        await fetch.execute(temple, robot, createIfUnknown: false),
      );

      expect(created.pgpKeyProven, isFalse);
      expect(created.pgpKey.isNamedAfter(robot.identity), isTrue);
      expect(readBack.pgpKeyProven, isTrue);
      expect(readBack.pgpKey, created.pgpKey);
      expect(readBack.hashId, robot.identity.hashId);
      // One robot, one coordinator: the binding was written before the first request.
      expect(
        await fetch.execute(lake, robot, createIfUnknown: true),
        isA<Err<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>()
            .having(
              (err) => err.failure,
              'failure',
              isA<RobotBoundToAnotherCoordinatorFailure>(),
            ),
      );
      expect(coordinator.requests, hasLength(3));
      expect(coordinator.requests.map((request) => request.url.host).toSet(), {
        Uri.parse(temple.testnet.onion ?? '').host,
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
