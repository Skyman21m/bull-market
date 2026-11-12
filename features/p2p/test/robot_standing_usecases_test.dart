import 'dart:typed_data';

import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_standing_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// The Garage's local reads and records of a robot: where it stands, and the user's acknowledgement of a key of unknown history.
void main() {
  const testnet = RobosatsNetwork.testnet;
  const mainnet = RobosatsNetwork.mainnet;

  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final garageKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  NetworkGarageKey keyOn(RobosatsNetwork network) =>
      NetworkGarageKey(network, garageKey);
  NetworkRobot robotOf(NetworkGarageKey key, int index) =>
      switch (key.firstUsableRobot(index)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
  final fingerprint = switch (keyOn(testnet).fingerprint) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };
  final passes = isA<Ok<void, P2pFailure>>();

  Matcher standing(RobotStanding expected) =>
      isA<Ok<RobotStanding, P2pFailure>>().having(
        (ok) => ok.value,
        'standing',
        expected,
      );

  group('ReadRobotStandingUsecase', () {
    test(
      'reads the slot of the robot, on the network of its key, and nothing else',
      () async {
        final recording = RecordingBindings();
        final robot = robotOf(keyOn(mainnet), 4);

        final read = await ReadRobotStandingUsecase(recording).execute(robot);

        expect(
          read,
          standing(
            const RobotStanding(
              network: mainnet,
              binding: null,
              history: GarageKeyHistory.unknown,
            ),
          ),
        );
        expect(recording.calls, [
          ('standingOf', RobotSlot(mainnet, fingerprint, 4), null),
        ]);
      },
    );

    test('a database that cannot be read is a storage failure', () async {
      final recording = RecordingBindings()
        ..readFailure = const P2pStorageFailure();

      expect(
        await ReadRobotStandingUsecase(
          recording,
        ).execute(robotOf(keyOn(testnet), 0)),
        isA<Err<RobotStanding, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pStorageFailure>(),
        ),
      );
    });

    test('over the database: a robot bound, and one not yet', () async {
      final bindings = bindingsInMemory();
      final temple = identityOf('temple', testnet);
      expect(await bindings.recordGeneratedKey(testnet, fingerprint), passes);
      expect(
        await bindings.bind(robotOf(keyOn(testnet), 0).slot, temple),
        passes,
      );
      final read = ReadRobotStandingUsecase(bindings);

      expect(
        await read.execute(robotOf(keyOn(testnet), 0)),
        standing(
          RobotStanding(
            network: testnet,
            binding: RobotBinding(temple, testNow, BindingProvenance.drawnHere),
            history: GarageKeyHistory.drawnHere,
          ),
        ),
      );
      expect(
        await read.execute(robotOf(keyOn(testnet), 1)),
        standing(
          const RobotStanding(
            network: testnet,
            binding: null,
            history: GarageKeyHistory.drawnHere,
          ),
        ),
      );
      // The same key in the mainnet slot: robot 0 is bound there too, to a testnet coordinator, and the key has no history on mainnet.
      final onMainnet = await read.execute(robotOf(keyOn(mainnet), 0));
      expect(
        onMainnet,
        standing(
          RobotStanding(
            network: mainnet,
            binding: RobotBinding(temple, testNow, BindingProvenance.drawnHere),
            history: GarageKeyHistory.unknown,
          ),
        ),
      );
      expect(
        (onMainnet as Ok<RobotStanding, P2pFailure>)
            .value
            .isBoundOnOtherNetwork,
        isTrue,
      );
    });
  });

  group('AcknowledgeGarageKeyHistoryUsecase', () {
    test(
      'records the acknowledgement of the key on the network of its slot',
      () async {
        final recording = RecordingBindings();

        expect(
          await AcknowledgeGarageKeyHistoryUsecase(
            recording,
          ).execute(keyOn(mainnet)),
          passes,
        );

        expect(recording.calls, [
          ('recordAcknowledgedKey', mainnet, fingerprint),
        ]);
      },
    );

    test('a record that cannot be written is a failure', () async {
      final recording = RecordingBindings(failure: const P2pStorageFailure());

      expect(
        await AcknowledgeGarageKeyHistoryUsecase(
          recording,
        ).execute(keyOn(testnet)),
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pStorageFailure>(),
        ),
      );
    });

    test(
      'over the database: the robots of an imported key may be bound once acknowledged, with that provenance',
      () async {
        final bindings = bindingsInMemory();
        final temple = identityOf('temple', mainnet);
        final read = ReadRobotStandingUsecase(bindings);
        final acknowledge = AcknowledgeGarageKeyHistoryUsecase(bindings);
        expect(await bindings.recordImportedKey(mainnet, fingerprint), passes);
        final robot = robotOf(keyOn(mainnet), 2);
        expect(
          (await read.execute(robot) as Ok<RobotStanding, P2pFailure>)
              .value
              .needsAcknowledgement,
          isTrue,
        );
        expect(
          await bindings.bind(robot.slot, temple),
          isA<Err<void, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<RobotHistoryUnknownFailure>(),
          ),
        );

        expect(await acknowledge.execute(keyOn(mainnet)), passes);

        expect(
          await read.execute(robot),
          standing(
            const RobotStanding(
              network: mainnet,
              binding: null,
              history: GarageKeyHistory.acknowledged,
            ),
          ),
        );
        expect(await bindings.bind(robot.slot, temple), passes);
        expect(
          await read.execute(robot),
          standing(
            RobotStanding(
              network: mainnet,
              binding: RobotBinding(
                temple,
                testNow,
                BindingProvenance.acknowledged,
              ),
              history: GarageKeyHistory.acknowledged,
            ),
          ),
        );
        // The acknowledgement is for mainnet only.
        expect(
          (await read.execute(robotOf(keyOn(testnet), 3))
                  as Ok<RobotStanding, P2pFailure>)
              .value
              .needsAcknowledgement,
          isTrue,
        );
      },
    );

    test('over the database: a key drawn here stays drawn here', () async {
      final bindings = bindingsInMemory();
      expect(await bindings.recordGeneratedKey(testnet, fingerprint), passes);

      expect(
        await AcknowledgeGarageKeyHistoryUsecase(
          bindings,
        ).execute(keyOn(testnet)),
        passes,
      );

      expect(
        await ReadRobotStandingUsecase(
          bindings,
        ).execute(robotOf(keyOn(testnet), 0)),
        standing(
          const RobotStanding(
            network: testnet,
            binding: null,
            history: GarageKeyHistory.drawnHere,
          ),
        ),
      );
    });
  });
}
