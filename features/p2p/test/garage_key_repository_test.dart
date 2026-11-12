import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

/// The Garage Keys of P2P, through the real vault of `package:secrets` over its in-memory keystore.
///
/// The vault settles an empty slot with its full read budget, so each test that reads, creates or imports into an empty slot waits about 4.5 s of real time.
void main() {
  // The names the vault files the two keys under, frozen in `packages/secrets`.
  const mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
  const testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';
  const slow = Timeout(Duration(seconds: 90));

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

  // The example key of the RoboSats frontend tests, and its first robot, as `packages/robosats` records them (tests run in the package directory).
  final vectors =
      jsonDecode(
            File(
              '../../packages/robosats/test/fixtures/robot-identity-vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final exampleVector = vectors['garage_key'] as Map<String, dynamic>;
  final exampleRobot =
      (exampleVector['derived'] as List).first as Map<String, dynamic>;
  final exampleKey = switch (GarageKey.parse(
    exampleVector['garage_key'] as String,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  GarageKeyRepositoryImpl repositoryOver(FakeSecureStoragePlatform storage) {
    storage.install();
    return GarageKeyRepositoryImpl(
      Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
  }

  T ok<T>(Result<T, P2pFailure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('expected a value, got $failure'),
  };

  P2pFailure err<T>(Result<T, P2pFailure> result) => switch (result) {
    Ok() => fail('expected a failure, got a value'),
    Err(:final failure) => failure,
  };

  // The fixed key stored in each slot, the way the vault stores it: by an import through its public handle.
  late Map<String, String> storedFixedKeys;

  setUpAll(() async {
    final storage = FakeSecureStoragePlatform();
    final repository = repositoryOver(storage);
    ok(await repository.import(RobosatsNetwork.mainnet, fixedKey));
    ok(await repository.import(RobosatsNetwork.testnet, fixedKey));
    storedFixedKeys = Map.of(storage.entries);
    expect(storedFixedKeys.keys, unorderedEquals([mainnetEntry, testnetEntry]));
  });

  FakeSecureStoragePlatform storageHolding(
    Iterable<String> entries, {
    bool locked = false,
    List<Object?>? scripted,
    List<Object?>? scriptedWrites,
  }) => FakeSecureStoragePlatform(
    entries: {for (final entry in entries) entry: storedFixedKeys[entry] ?? ''},
    locked: locked,
    scripted: scripted,
    scriptedWrites: scriptedWrites,
  );

  group('an empty slot', () {
    test(
      'reads as no key, after the full budget, and nothing is written',
      () async {
        final storage = FakeSecureStoragePlatform();
        final repository = repositoryOver(storage);

        expect(ok(await repository.exists(RobosatsNetwork.mainnet)), isFalse);
        expect(storage.reads, 5);
        expect(
          err(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
          isA<GarageKeyMissingFailure>(),
        );
        expect(storage.entries, isEmpty);
      },
      timeout: slow,
    );

    test('takes a new key, in the slot of its own network only', () async {
      final storage = FakeSecureStoragePlatform();
      final repository = repositoryOver(storage);

      ok(await repository.create(RobosatsNetwork.testnet));

      expect(storage.entries.keys, [testnetEntry]);
      expect(storage.readKeys.toSet(), {testnetEntry});
      expect(ok(await repository.exists(RobosatsNetwork.testnet)), isTrue);
      final robot = ok(
        await repository.firstUsableRobot(RobosatsNetwork.testnet),
      );
      expect(robot.accountIndex, 0);
    }, timeout: slow);

    test('takes an imported key, which gives its own robots back', () async {
      final storage = FakeSecureStoragePlatform();
      final repository = repositoryOver(storage);

      ok(await repository.import(RobosatsNetwork.mainnet, exampleKey));

      expect(storage.entries.keys, [mainnetEntry]);
      final robot = ok(
        await repository.firstUsableRobot(RobosatsNetwork.mainnet),
      );
      expect(robot.accountIndex, exampleRobot['account_index']);
      expect(robot.identity.hashId.hex, exampleRobot['hash_id']);
      expect(robot.identity.nickname, exampleRobot['nickname']);
    }, timeout: slow);
  });

  group('a stored key', () {
    test('is found, and gives the robots of its own bytes', () async {
      final repository = repositoryOver(storageHolding([mainnetEntry]));

      expect(ok(await repository.exists(RobosatsNetwork.mainnet)), isTrue);
      expect(
        ok(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
        isA<NetworkRobot>()
            .having(
              (robot) => robot.network,
              'network',
              RobosatsNetwork.mainnet,
            )
            .having((robot) => robot.robot, 'robot', fixedRobot),
      );
    });

    test('is read with the network of its slot, never the other', () async {
      final storage = storageHolding([testnetEntry]);
      final repository = repositoryOver(storage);

      expect(
        ok(await repository.read(RobosatsNetwork.testnet)),
        NetworkGarageKey(RobosatsNetwork.testnet, fixedKey),
      );
      expect(
        err(await repository.read(RobosatsNetwork.mainnet)),
        isA<GarageKeyMissingFailure>(),
      );
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
    }, timeout: slow);

    test('gives robots tagged with the network of its slot', () async {
      final repository = repositoryOver(
        storageHolding([mainnetEntry, testnetEntry]),
      );

      for (final network in RobosatsNetwork.values) {
        final key = ok(await repository.read(network));
        expect(key.network, network);
        expect(
          ok(key.firstUsableRobot(0)),
          ok(await repository.firstUsableRobot(network)),
        );
        expect(ok(key.firstUsableRobot(0)).network, network);
      }
    });

    test('is never replaced: create and import are refused', () async {
      final storage = storageHolding([mainnetEntry]);
      final repository = repositoryOver(storage);

      expect(
        err(await repository.create(RobosatsNetwork.mainnet)),
        isA<GarageKeyAlreadyStoredFailure>(),
      );
      expect(
        err(await repository.import(RobosatsNetwork.mainnet, exampleKey)),
        isA<GarageKeyAlreadyStoredFailure>(),
      );

      expect(storage.entries, {mainnetEntry: storedFixedKeys[mainnetEntry]});
      expect(
        ok(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
        isA<NetworkRobot>()
            .having(
              (robot) => robot.network,
              'network',
              RobosatsNetwork.mainnet,
            )
            .having((robot) => robot.robot, 'robot', fixedRobot),
      );
    });

    test('of one network is never reached from the other', () async {
      final storage = storageHolding([testnetEntry]);
      final repository = repositoryOver(storage);

      expect(
        ok(await repository.firstUsableRobot(RobosatsNetwork.testnet)),
        isA<NetworkRobot>()
            .having(
              (robot) => robot.network,
              'network',
              RobosatsNetwork.testnet,
            )
            .having((robot) => robot.robot, 'robot', fixedRobot),
      );
      ok(await repository.delete(RobosatsNetwork.mainnet));

      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      expect(storage.readKeys.toSet(), {testnetEntry});
    });
  });

  group('an entry that cannot be used', () {
    test(
      'is reported as such, refused as a slot, and kept until deleted',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetEntry: 'not json at all'},
        );
        final repository = repositoryOver(storage);

        expect(
          err(await repository.exists(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnusableFailure>(),
        );
        expect(
          err(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnusableFailure>(),
        );
        expect(
          err(await repository.read(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnusableFailure>(),
        );
        expect(
          err(await repository.create(RobosatsNetwork.mainnet)),
          isA<GarageKeyAlreadyStoredFailure>(),
        );
        expect(
          err(await repository.import(RobosatsNetwork.mainnet, exampleKey)),
          isA<GarageKeyAlreadyStoredFailure>(),
        );
        expect(storage.entries, {mainnetEntry: 'not json at all'});

        ok(await repository.delete(RobosatsNetwork.mainnet));

        expect(storage.entries, isEmpty);
        expect(ok(await repository.exists(RobosatsNetwork.mainnet)), isFalse);
      },
      timeout: slow,
    );

    test(
      'that keeps failing to read is unreadable, and nothing is written over it',
      () async {
        PlatformException failing() => PlatformException(code: 'read failed');
        final storage = storageHolding([
          mainnetEntry,
        ], scripted: List.generate(20, (_) => failing()));
        final repository = repositoryOver(storage);

        expect(
          err(await repository.exists(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnreadableFailure>(),
        );
        expect(
          err(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnreadableFailure>(),
        );
        expect(
          err(await repository.read(RobosatsNetwork.mainnet)),
          isA<GarageKeyUnreadableFailure>(),
        );
        expect(
          err(await repository.create(RobosatsNetwork.mainnet)),
          isA<GarageKeyNotSavedFailure>(),
        );
        expect(storage.entries, {mainnetEntry: storedFixedKeys[mainnetEntry]});
      },
      timeout: slow,
    );
  });

  group('a locked keystore', () {
    test('is reported as locked, and nothing is written or deleted', () async {
      final storage = storageHolding([mainnetEntry], locked: true);
      final repository = repositoryOver(storage);

      for (final failure in [
        err(await repository.exists(RobosatsNetwork.mainnet)),
        err(await repository.firstUsableRobot(RobosatsNetwork.mainnet)),
        err(await repository.read(RobosatsNetwork.mainnet)),
        err(await repository.create(RobosatsNetwork.mainnet)),
        err(await repository.import(RobosatsNetwork.mainnet, exampleKey)),
      ]) {
        expect(failure, isA<GarageKeyLockedFailure>());
      }
      storage
        ..locked = false
        ..writesFail = true;
      expect(
        err(await repository.delete(RobosatsNetwork.mainnet)),
        isA<GarageKeyLockedFailure>(),
      );

      expect(storage.entries, {mainnetEntry: storedFixedKeys[mainnetEntry]});
    });
  });

  group('a keystore that refuses a change', () {
    test('keeps the key when a delete fails, and says so', () async {
      final storage = storageHolding(
        [mainnetEntry],
        scriptedWrites: [PlatformException(code: 'delete failed')],
      );
      final repository = repositoryOver(storage);

      expect(
        err(await repository.delete(RobosatsNetwork.mainnet)),
        isA<GarageKeyNotDeletedFailure>(),
      );
      expect(storage.entries, {mainnetEntry: storedFixedKeys[mainnetEntry]});
    });

    test('stores no key when a write fails, and says so', () async {
      final storage = FakeSecureStoragePlatform(
        scriptedWrites: [PlatformException(code: 'write failed')],
      );
      final repository = repositoryOver(storage);

      expect(
        err(await repository.create(RobosatsNetwork.mainnet)),
        isA<GarageKeyNotSavedFailure>(),
      );
      expect(storage.entries, isEmpty);
    }, timeout: slow);
  });

  test('two simultaneous creates on an empty slot store one key', () async {
    final storage = _SlowWrites();
    final first = repositoryOver(storage);
    final second = repositoryOver(storage);

    final (a, b) = await (
      first.create(RobosatsNetwork.mainnet),
      second.create(RobosatsNetwork.mainnet),
    ).wait;

    expect([a, b].whereType<Ok<void, P2pFailure>>(), hasLength(1));
    expect(
      [a, b].whereType<Err<void, P2pFailure>>().single.failure,
      isA<GarageKeyAlreadyStoredFailure>(),
    );
    expect(storage.entries.keys, [mainnetEntry]);
  }, timeout: slow);

  test('the failures carry nothing but their type', () {
    for (final failure in <P2pFailure>[
      const GarageKeyMissingFailure(),
      const GarageKeyAlreadyStoredFailure(),
      const GarageKeyLockedFailure(),
      const GarageKeyUnreadableFailure(),
      const GarageKeyUnusableFailure(),
      const GarageKeyNotSavedFailure(),
      const GarageKeyNotDeletedFailure(),
      const GarageKeyInvalidFailure(GarageKeyBadChecksum()),
      const GarageRobotUnavailableFailure(),
    ]) {
      expect(failure.logMessage, isNull);
      expect(failure.toString(), '${failure.runtimeType}');
    }
  });
}

/// A keystore whose writes take time, as a real one's do: in memory, a write would land before the second caller's last read, and the race would never interleave.
final class _SlowWrites extends FakeSecureStoragePlatform {
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await super.write(key: key, value: value, options: options);
  }
}
