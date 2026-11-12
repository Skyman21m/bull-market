import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// Whether deleting a Garage Key asks the wallet's PIN, read from the feature's database (design note of #29, § 2.5): only a key drawn here, recorded so, with no robot bound, is deleted on the confirmation alone, as in RoboSats.
void main() {
  const testnet = RobosatsNetwork.testnet;
  const mainnet = RobosatsNetwork.mainnet;

  // Fixed test bytes: not keys anyone uses.
  GarageKey keyOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final keyA = keyOf(1);
  final keyB = keyOf(2);
  GarageKeyFingerprint fingerprintOf(GarageKey key) =>
      switch (GarageKeyFingerprint.of(key)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
  final fingerprintA = fingerprintOf(keyA);
  final fingerprintB = fingerprintOf(keyB);
  // The key of the testnet slot.
  final slotKey = NetworkGarageKey(testnet, keyA);

  CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };
  final passes = isA<Ok<void, P2pFailure>>();

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late NeedsPinToDeleteGarageKeyUsecase needsPin;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
    needsPin = NeedsPinToDeleteGarageKeyUsecase(bindings);
  });

  tearDown(() => database.close());

  group('a key that can be read', () {
    test('drawn here, with no robot bound: no PIN, as in RoboSats', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      // Robots of another key, bound: not this key's.
      expect(await bindings.recordGeneratedKey(testnet, fingerprintB), passes);
      expect(
        await bindings.bind(
          RobotSlot(testnet, fingerprintB, 0),
          identityOf('temple', testnet),
        ),
        passes,
      );

      expect(await needsPin.execute(slotKey), isFalse);
    });

    test('with a robot bound on its network: the PIN', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.bind(
          RobotSlot(testnet, fingerprintA, 7),
          identityOf('temple', testnet),
        ),
        passes,
      );

      expect(await needsPin.execute(slotKey), isTrue);
    });

    test('with a robot bound on the other network: the PIN', () async {
      // The same key in both slots, drawn here on each, robot 0 sent to a mainnet coordinator.
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintA), passes);
      expect(
        await bindings.bind(
          RobotSlot(mainnet, fingerprintA, 0),
          identityOf('lake', mainnet),
        ),
        passes,
      );

      expect(await needsPin.execute(slotKey), isTrue);
    });

    test('imported: the PIN', () async {
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

      expect(await needsPin.execute(slotKey), isTrue);
    });

    test('drawn here, then imported again: the PIN', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

      expect(await needsPin.execute(slotKey), isTrue);
    });

    test(
      'never recorded, as a key drawn before the records or whose record failed: the PIN',
      () async {
        expect(await needsPin.execute(slotKey), isTrue);
      },
    );

    test('drawn here for the other network only: the PIN', () async {
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintA), passes);

      expect(await needsPin.execute(slotKey), isTrue);
      expect(await needsPin.execute(NetworkGarageKey(mainnet, keyA)), isFalse);
    });
  });

  group('a slot that cannot be read', () {
    test('with no robot bound at all: no PIN', () async {
      // Histories bind nothing.
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintB), passes);

      expect(await needsPin.execute(null), isFalse);
    });

    test('with a robot of any key bound, on any network: the PIN', () async {
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintB), passes);
      expect(
        await bindings.bind(
          RobotSlot(mainnet, fingerprintB, 3),
          identityOf('temple', mainnet),
        ),
        passes,
      );

      expect(await needsPin.execute(null), isTrue);
    });
  });

  group('a database that cannot be read asks the PIN', () {
    test('that cannot be opened', () async {
      final broken = P2pDatabase.forTesting(
        NativeDatabase.memory(
          setup: (_) => throw const FileSystemException('no file'),
        ),
      );
      final unreadable = NeedsPinToDeleteGarageKeyUsecase(
        bindingsInMemory(database: broken),
      );

      expect(await unreadable.execute(slotKey), isTrue);
      expect(await unreadable.execute(null), isTrue);
      await broken.close();
    });

    test('whatever it answers', () async {
      final failing = RecordingBindings()
        ..readFailure = const P2pStorageFailure();
      final unreadable = NeedsPinToDeleteGarageKeyUsecase(failing);

      expect(await unreadable.execute(slotKey), isTrue);
      expect(await unreadable.execute(null), isTrue);
    });
  });

  test('reads the bindings of its key only, and writes nothing', () async {
    final recording = RecordingBindings();
    final reader = NeedsPinToDeleteGarageKeyUsecase(recording);

    expect(await reader.execute(slotKey), isFalse);
    expect(await reader.execute(null), isFalse);

    expect(recording.calls, [
      ('exposureOf', testnet, fingerprintA),
      ('hasAnyBinding', null, null),
    ]);
  });

  test('follows the rule of the exposure it reads', () async {
    final recording = RecordingBindings();
    final reader = NeedsPinToDeleteGarageKeyUsecase(recording);
    for (final (history, hasBinding, expected) in [
      (GarageKeyHistory.drawnHere, false, false),
      (GarageKeyHistory.drawnHere, true, true),
      (GarageKeyHistory.unknown, false, true),
      (GarageKeyHistory.unknown, true, true),
    ]) {
      recording.exposure = GarageKeyExposure(
        history: history,
        hasBinding: hasBinding,
      );
      expect(
        await reader.execute(slotKey),
        expected,
        reason: '$history, $hasBinding',
      );
    }
    recording.anyBinding = true;
    expect(await reader.execute(null), isTrue);
  });
}
