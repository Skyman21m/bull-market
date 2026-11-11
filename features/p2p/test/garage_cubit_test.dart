import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/key_output.dart';

/// The Garage of one network over the real vault of `package:secrets`, on its in-memory keystore: empty, holding a key, corrupt, locked or unreadable, and the slot of the other network never touched.
///
/// The vault settles an empty slot with its full read budget, so each test that finds a slot empty waits about 4.5 s of real time.
void main() {
  const mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
  const testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';
  const slow = Timeout(Duration(seconds: 120));

  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fixedKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final fixedRobot = switch (fixedKey.firstUsableRobot(0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  // The example key of the RoboSats frontend tests and its first robot, as `packages/robosats` records them.
  final vector =
      (jsonDecode(
                File(
                  '../../packages/robosats/test/fixtures/robot-identity-vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['garage_key']
          as Map<String, dynamic>;
  final exampleText = vector['garage_key'] as String;
  final exampleRobot =
      (vector['derived'] as List).first as Map<String, dynamic>;

  // The fixed key stored in each slot, the way the vault stores it.
  late Map<String, String> storedFixedKeys;

  GarageCubit cubitOver(
    FakeSecureStoragePlatform storage, {
    RobosatsNetwork network = RobosatsNetwork.testnet,
  }) {
    storage.install();
    final repository = GarageKeyRepositoryImpl(
      Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    return GarageCubit(
      network,
      ReadGarageKeyUsecase(repository),
      GenerateGarageKeyUsecase(repository),
      ImportGarageKeyUsecase(repository),
      DeleteGarageKeyUsecase(repository),
    );
  }

  FakeSecureStoragePlatform holding(
    Iterable<String> entries, {
    bool locked = false,
    List<Object?>? scripted,
    List<Object?>? scriptedWrites,
  }) => FakeSecureStoragePlatform(
    entries: {for (final entry in entries) entry: storedFixedKeys[entry] ?? ''},
    // A locked keystore refuses writes and deletes as well as reads.
    locked: locked,
    writesFail: locked,
    scripted: scripted,
    scriptedWrites: scriptedWrites,
  );

  /// The key stored in [slot], read through the vault itself: the test compares it, never shows it.
  Future<GarageKey?> storedIn(GarageKeySlot slot) async =>
      switch (await Secrets(
        scratchDirectory: () async => '.',
      ).garageKeys().read(slot: slot)) {
        Ok(:final value) => switch (GarageKey.fromBytes(
          Uint8List.fromList(value.bytes),
        )) {
          Ok(:final value) => value,
          Err() => null,
        },
        Err() => null,
      };

  setUpAll(() async {
    final storage = FakeSecureStoragePlatform()..install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    for (final slot in GarageKeySlot.values) {
      final result = await vault.import(
        slot: slot,
        bytes: fixedKey.revealBytes(),
      );
      expect(result, isA<Ok<Object?, Failure>>());
    }
    storedFixedKeys = Map.of(storage.entries);
  });

  test('touches nothing until it is loaded', () async {
    final storage = holding([testnetEntry]);
    final cubit = cubitOver(storage);

    expect(cubit.state, isA<GarageWorking>());
    expect(storage.reads, 0);
    expect(storage.readKeys, isEmpty);
    await cubit.close();
  });

  group('an empty slot', () {
    test(
      'shows the welcome, then a generated key, stored in its own slot only',
      () async {
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage);

        await cubit.load();
        expect(cubit.state, isA<GarageWithoutKey>());
        expect(storage.entries, isEmpty);

        await cubit.generate();

        final state = cubit.state;
        expect(state, isA<GarageWithKey>());
        state as GarageWithKey;
        expect(state.isNew, isTrue);
        expect(state.key.network, RobosatsNetwork.testnet);
        expect(state.robot.index, 0);
        expect(storage.entries.keys, [testnetEntry]);
        expect(storage.readKeys.toSet(), {testnetEntry});
        expect(await storedIn(GarageKeySlot.testnet), state.key.key);
        final robot = switch (state.key.firstUsableRobot(0)) {
          Ok(:final value) => value,
          Err() => fail('no robot'),
        };
        expect(state.robot, GarageRobotFace.of(robot));
        expect(state.robot.nickname, robot.identity.nickname);
        await cubit.close();
      },
      timeout: slow,
    );

    test('takes a pasted key, which gives its own robot', () async {
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(storage, network: RobosatsNetwork.mainnet);
      await cubit.load();

      await cubit.import(exampleText);

      final state = cubit.state as GarageWithKey;
      expect(state.isNew, isTrue);
      expect(state.key.network, RobosatsNetwork.mainnet);
      expect(state.robot.index, exampleRobot['account_index']);
      expect(state.robot.nickname, exampleRobot['nickname']);
      expect(state.robot.hashId, exampleRobot['hash_id']);
      expect(storage.entries.keys, [mainnetEntry]);
      await cubit.close();
    }, timeout: slow);

    test('refuses text that is not a key, and keeps none of it', () async {
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(storage);
      await cubit.load();
      final reads = storage.reads;
      final typo = '${exampleText.substring(0, exampleText.length - 1)}q';

      await cubit.import(typo);

      final state = cubit.state;
      expect(
        state,
        isA<GarageWithoutKey>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyInvalidFailure>(),
        ),
      );
      expect(storage.entries, isEmpty);
      expect(storage.reads, reads);
      // A boolean, so that a failure does not print the text.
      expect(
        '$state ${(state as GarageWithoutKey).failure}'.contains('robo1'),
        isFalse,
      );
      await cubit.close();
    }, timeout: slow);
  });

  group('a stored key', () {
    test('goes to the profile, hidden, never as a new key', () async {
      final cubit = cubitOver(holding([testnetEntry]));

      await cubit.load();

      final state = cubit.state as GarageWithKey;
      expect(state.isNew, isFalse);
      expect(state.key.key, fixedKey);
      expect(state.robot.index, fixedRobot.accountIndex);
      expect(state.robot.nickname, fixedRobot.identity.nickname);
      expect('$state', 'GarageWithKey(testnet)');
      await cubit.close();
    });

    test('is never replaced by a generate or an import', () async {
      final storage = holding([testnetEntry]);
      final cubit = cubitOver(storage);
      await cubit.load();
      final reads = storage.reads;

      await cubit.generate();
      await cubit.import(exampleText);

      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      final state = cubit.state as GarageWithKey;
      expect(state.key.key, fixedKey);
      // Neither reached the vault, whose refusal would have been reported.
      expect(storage.reads, reads);
      expect(state.failure, isNull);
      await cubit.close();
    });

    test('« Generate new » deletes it, then draws another', () async {
      final storage = holding([testnetEntry, mainnetEntry]);
      final cubit = cubitOver(storage);
      await cubit.load();

      await cubit.replace();

      final state = cubit.state as GarageWithKey;
      expect(state.isNew, isTrue);
      expect(state.key.key, isNot(fixedKey));
      expect(await storedIn(GarageKeySlot.testnet), state.key.key);
      expect(storage.entries[mainnetEntry], storedFixedKeys[mainnetEntry]);
      await cubit.close();
    }, timeout: slow);

    test('moves from robot to robot, and not below robot 0', () async {
      final cubit = cubitOver(holding([testnetEntry]));
      await cubit.load();

      cubit
        ..next()
        ..next();
      expect((cubit.state as GarageWithKey).robot.index, 2);
      cubit.previous();
      final state = cubit.state as GarageWithKey;
      expect(state.robot.index, 1);
      expect(state.robot.nickname, switch (fixedKey.deriveIdentity(1)) {
        Ok(:final value) => value.nickname,
        Err() => fail('no robot 1'),
      });
      cubit
        ..previous()
        ..previous();
      expect(
        cubit.state,
        isA<GarageWithKey>()
            .having((state) => state.robot.index, 'index', 0)
            .having(
              (state) => state.failure,
              'failure',
              isA<GarageRobotUnavailableFailure>(),
            ),
      );
      await cubit.close();
    });

    test('is deleted, its slot only, back to the welcome', () async {
      final storage = holding([testnetEntry, mainnetEntry]);
      final cubit = cubitOver(storage);
      await cubit.load();

      await cubit.delete();

      expect(cubit.state, isA<GarageWithoutKey>());
      expect(storage.entries, {mainnetEntry: storedFixedKeys[mainnetEntry]});
      await cubit.close();
    });

    test('that cannot be deleted stays, and the failure is said', () async {
      final storage = holding(
        [testnetEntry],
        scriptedWrites: [PlatformException(code: 'delete failed')],
      );
      final cubit = cubitOver(storage);
      await cubit.load();

      await cubit.delete();

      expect(
        cubit.state,
        isA<GarageWithKey>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyNotDeletedFailure>(),
        ),
      );
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      await cubit.close();
    });
  });

  group('the other network', () {
    test('is never read, written or deleted', () async {
      final storage = holding([testnetEntry]);
      final cubit = cubitOver(storage, network: RobosatsNetwork.mainnet);

      await cubit.load();
      expect(cubit.state, isA<GarageWithoutKey>());
      await cubit.generate();
      await cubit.delete();

      expect(storage.readKeys.toSet(), {mainnetEntry});
      expect(storage.entries[testnetEntry], storedFixedKeys[testnetEntry]);
      expect(storage.entries.containsKey(mainnetEntry), isFalse);
      await cubit.close();
    }, timeout: slow);
  });

  group('a slot the vault cannot read', () {
    test('that is corrupt offers only retry and delete', () async {
      final storage = FakeSecureStoragePlatform(
        entries: {testnetEntry: 'not json at all'},
      );
      final cubit = cubitOver(storage);

      await cubit.load();
      expect(
        cubit.state,
        isA<GarageUnknown>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyUnusableFailure>(),
        ),
      );
      await cubit.generate();
      await cubit.import(exampleText);
      expect(storage.entries, {testnetEntry: 'not json at all'});

      await cubit.delete();
      expect(cubit.state, isA<GarageWithoutKey>());
      expect(storage.entries, isEmpty);
      await cubit.close();
    });

    test('that keeps failing to read is unreadable', () async {
      final storage = holding([
        testnetEntry,
      ], scripted: List.generate(5, (_) => PlatformException(code: 'read')));
      final cubit = cubitOver(storage);

      await cubit.load();

      expect(
        cubit.state,
        isA<GarageUnknown>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyUnreadableFailure>(),
        ),
      );
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      await cubit.close();
    }, timeout: slow);

    test(
      'that is locked is said so, and nothing is written or deleted',
      () async {
        final storage = holding([testnetEntry], locked: true);
        final cubit = cubitOver(storage);

        await cubit.load();
        await cubit.generate();
        await cubit.delete();

        expect(
          cubit.state,
          isA<GarageUnknown>()
              .having(
                (state) => state.failure,
                'failure',
                isA<GarageKeyLockedFailure>(),
              )
              .having(
                (state) => state.actionFailure,
                'actionFailure',
                isA<GarageKeyLockedFailure>(),
              ),
        );
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
        await cubit.close();
      },
    );
  });

  test(
    'nothing printed or logged while the Garage is used holds a key',
    () async {
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(storage);
      final seen = <GarageKey>[];

      final output = await captureKeyOutput(() async {
        await cubit.load();
        await cubit.generate();
        seen.add((cubit.state as GarageWithKey).key.key);
        cubit
          ..next()
          ..previous();
        await cubit.replace();
        seen.add((cubit.state as GarageWithKey).key.key);
        await cubit.delete();
        await cubit.import(exampleText);
        await cubit.delete();
        await cubit.import('${exampleText.substring(0, 20)}x');
      });

      expect(seen, hasLength(2));
      final example = switch (GarageKey.parse(exampleText)) {
        Ok(:final value) => value,
        Err() => fail('not a key'),
      };
      expectNoKeyIn(output, [...seen, example]);
      await cubit.close();
    },
    timeout: slow,
  );
}
