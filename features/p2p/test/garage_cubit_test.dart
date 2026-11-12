import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';

/// The keystore of the tests, counting the writes and the deletes that reach it.
final class _CountingStorage extends FakeSecureStoragePlatform {
  int writes = 0;
  int deletes = 0;

  _CountingStorage({super.entries});

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    writes++;
    return super.write(key: key, value: value, options: options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) {
    deletes++;
    return super.delete(key: key, options: options);
  }
}

/// A stand-in for the wallet's re-authentication: it records, each time it is asked, whether the slot still held a key then, and answers [answer], or waits for [pending] when it is set.
final class _Gate {
  final FakeSecureStoragePlatform storage;
  final String entry;
  bool answer;
  Completer<bool>? pending;
  final List<bool> heldKeyWhenAsked = [];

  _Gate(this.storage, this.entry, {this.answer = true});

  int get asked => heldKeyWhenAsked.length;

  Future<bool> call() {
    heldKeyWhenAsked.add(storage.entries.containsKey(entry));
    return pending?.future ?? Future.value(answer);
  }
}

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
  final fixedFingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
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
    UnacknowledgedGarageKeys? unacknowledged,
    RobotBindingRepository? bindings,
  }) {
    storage.install();
    final repository = GarageKeyRepositoryImpl(
      Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    // The cubit's own tests: what the use cases record of a key is `garage_key_usecases_test.dart`'s; by default the fixed key the tests store counts as drawn here on both networks, so its delete asks no PIN, and a key drawn by the cubit is recorded so.
    final recorded =
        bindings ??
        RecordingBindings(
          drawnHere: [
            for (final network in RobosatsNetwork.values)
              (network, fixedFingerprint),
          ],
        );
    return GarageCubit(
      network,
      ReadGarageKeyUsecase(repository),
      GenerateGarageKeyUsecase(repository, recorded),
      ImportGarageKeyUsecase(repository, recorded),
      DeleteGarageKeyUsecase(repository),
      NeedsPinToDeleteGarageKeyUsecase(recorded),
      unacknowledged ?? UnacknowledgedGarageKeys(),
    );
  }

  /// The re-authentication of a delete that must not ask it: a key drawn here, with no robot bound.
  Future<bool> neverAsked() async => fail('the PIN was asked');

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

      await cubit.replace(reauthenticate: neverAsked);

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

      await cubit.delete(reauthenticate: neverAsked);

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

      await cubit.delete(reauthenticate: neverAsked);

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

  group('a key drawn and not acknowledged', () {
    test(
      'is shown without the PIN only by the cubit that drew it, until the app is hidden',
      () async {
        final unacknowledged = UnacknowledgedGarageKeys();
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, unacknowledged: unacknowledged);
        await cubit.load();

        await cubit.generate();
        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isTrue,
              ),
        );
        cubit.next();
        expect((cubit.state as GarageWithKey).showWithoutPin, isTrue);

        cubit.conceal();
        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isFalse,
              ),
        );
        expect(unacknowledged.waits(RobosatsNetwork.testnet), isTrue);

        cubit.acknowledgeBackup();
        expect((cubit.state as GarageWithKey).awaitsBackup, isFalse);
        expect(unacknowledged.waits(RobosatsNetwork.testnet), isFalse);
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'drawn while the user left, is not read back, and awaits its backup behind the PIN',
      () async {
        final unacknowledged = UnacknowledgedGarageKeys();
        // How many reads a draw and its read-back take, the user staying.
        final stayed = FakeSecureStoragePlatform();
        final staying = cubitOver(stayed, unacknowledged: unacknowledged);
        await staying.load();
        final beforeStaying = stayed.reads;
        await staying.generate();
        final readsStaying = stayed.reads - beforeStaying;
        staying.acknowledgeBackup();
        await staying.close();

        final left = FakeSecureStoragePlatform();
        final leaving = cubitOver(left, unacknowledged: unacknowledged);
        await leaving.load();
        final beforeLeaving = left.reads;
        final drawing = leaving.generate();
        await leaving.close();
        await drawing;

        expect(left.entries.keys, [testnetEntry]);
        // The draw only: no read-back from the closed cubit.
        expect(left.reads - beforeLeaving, readsStaying - 1);
        expect(unacknowledged.waits(RobosatsNetwork.testnet), isTrue);

        for (var visit = 0; visit < 2; visit++) {
          final next = cubitOver(left, unacknowledged: unacknowledged);
          await next.load();
          expect(
            next.state,
            isA<GarageWithKey>()
                .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
                .having((state) => state.isNew, 'isNew', isTrue)
                .having(
                  (state) => state.showWithoutPin,
                  'showWithoutPin',
                  isFalse,
                ),
          );
          await next.close();
        }

        final acknowledging = cubitOver(left, unacknowledged: unacknowledged);
        await acknowledging.load();
        acknowledging.acknowledgeBackup();
        await acknowledging.close();
        final after = cubitOver(left, unacknowledged: unacknowledged);
        await after.load();
        expect(
          after.state,
          isA<GarageWithKey>()
              .having((state) => state.awaitsBackup, 'awaitsBackup', isFalse)
              .having((state) => state.isNew, 'isNew', isFalse),
        );
        await after.close();
      },
      timeout: slow,
    );

    test('hidden while the vault draws, arrives behind the PIN', () async {
      final cubit = cubitOver(FakeSecureStoragePlatform());
      await cubit.load();

      final drawing = cubit.generate();
      expect(cubit.state, isA<GarageWorking>());
      cubit.conceal();
      await drawing;

      expect(
        cubit.state,
        isA<GarageWithKey>()
            .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
            .having((state) => state.showWithoutPin, 'showWithoutPin', isFalse),
      );
      await cubit.close();
    }, timeout: slow);

    test('counts a hide from the tap on « Generate », not one before', () async {
      final cubit = cubitOver(FakeSecureStoragePlatform());
      await cubit.load();
      // The app was hidden before the user asked for a key: that hide is over.
      cubit.conceal();

      await cubit.generate();

      expect((cubit.state as GarageWithKey).showWithoutPin, isTrue);
      await cubit.close();
    }, timeout: slow);

    test(
      '« Generate new » counts a hide from its tap, the delete included',
      () async {
        final cubit = cubitOver(holding([testnetEntry]));
        await cubit.load();
        cubit.conceal();

        await cubit.replace(reauthenticate: neverAsked);
        expect((cubit.state as GarageWithKey).showWithoutPin, isTrue);

        final replacing = cubit.replace(reauthenticate: neverAsked);
        // The old key is being deleted: the new one is not drawn yet.
        cubit.conceal();
        await replacing;

        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.isNew, 'isNew', isTrue)
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isFalse,
              ),
        );
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'hidden while the database is read after the draw, arrives behind the PIN',
      () async {
        final bindings = RecordingBindings();
        final cubit = cubitOver(
          FakeSecureStoragePlatform(),
          bindings: bindings,
        );
        await cubit.load();
        final reading = Completer<void>();
        final started = Completer<void>();
        bindings
          ..readsWait = reading.future
          ..onRead = () {
            if (!started.isCompleted) started.complete();
          };

        final drawing = cubit.generate();
        // The key is drawn and read back; the database is read for the delete before the state is built.
        await started.future;
        cubit.conceal();
        reading.complete();
        await drawing;

        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isFalse,
              ),
        );
        await cubit.close();
      },
      timeout: slow,
    );

    test('pasted, is never shown without the PIN', () async {
      final cubit = cubitOver(FakeSecureStoragePlatform());
      await cubit.load();

      await cubit.import(exampleText);

      expect(
        cubit.state,
        isA<GarageWithKey>()
            .having((state) => state.awaitsBackup, 'awaitsBackup', isFalse)
            .having((state) => state.showWithoutPin, 'showWithoutPin', isFalse),
      );
      await cubit.close();
    }, timeout: slow);

    test('is forgotten once deleted', () async {
      final unacknowledged = UnacknowledgedGarageKeys();
      final cubit = cubitOver(
        FakeSecureStoragePlatform(),
        unacknowledged: unacknowledged,
      );
      await cubit.load();
      await cubit.generate();
      expect(unacknowledged.waits(RobosatsNetwork.testnet), isTrue);

      await cubit.delete(reauthenticate: neverAsked);

      expect(unacknowledged.waits(RobosatsNetwork.testnet), isFalse);
      await cubit.close();
    }, timeout: slow);

    test('of the other network gives no alert here', () async {
      final unacknowledged = UnacknowledgedGarageKeys();
      final storage = FakeSecureStoragePlatform();
      final mainnet = cubitOver(
        storage,
        network: RobosatsNetwork.mainnet,
        unacknowledged: unacknowledged,
      );
      await mainnet.load();
      await mainnet.generate();
      await mainnet.close();
      expect(unacknowledged.waits(RobosatsNetwork.mainnet), isTrue);

      storage.entries[testnetEntry] = storedFixedKeys[testnetEntry] ?? '';
      final testnet = cubitOver(storage, unacknowledged: unacknowledged);
      await testnet.load();

      expect((testnet.state as GarageWithKey).awaitsBackup, isFalse);
      expect(unacknowledged.waits(RobosatsNetwork.mainnet), isTrue);
      await testnet.close();
    }, timeout: slow);
  });

  group('the other network', () {
    test('is never read, written or deleted', () async {
      final storage = holding([testnetEntry]);
      final cubit = cubitOver(storage, network: RobosatsNetwork.mainnet);

      await cubit.load();
      expect(cubit.state, isA<GarageWithoutKey>());
      await cubit.generate();
      await cubit.delete(reauthenticate: neverAsked);

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

      // A slot that cannot be read always asks the PIN.
      var asked = 0;
      await cubit.delete(
        reauthenticate: () async {
          asked++;
          return true;
        },
      );
      expect(asked, 1);
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
        // The screens offer no delete then; the cubit asks the PIN, and the vault refuses.
        await cubit.delete(reauthenticate: () async => true);

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

  group('the PIN before a delete', () {
    final fingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    // Another key's fingerprint: fixed test bytes, 0x02 to 0x21.
    final otherFingerprint = switch (GarageKey.fromBytes(
      Uint8List.fromList(List<int>.generate(32, (i) => i + 2)),
    )) {
      Ok(:final value) => switch (GarageKeyFingerprint.of(value)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      },
      Err(:final failure) => throw StateError('$failure'),
    };
    CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
        switch (CoordinatorIdentity.of(coordinator(alias), network)) {
          final identity? => identity,
          null => throw StateError('$alias is not on $network'),
        };
    final passes = isA<Ok<void, P2pFailure>>();

    late RobotBindingRepositoryImpl bindings;

    setUp(() => bindings = bindingsInMemory());

    /// Records the fixed key as drawn here on [network], then binds its robot [index] to temple there.
    Future<void> bindFixedRobot(
      RobosatsNetwork network, {
      int index = 0,
    }) async {
      expect(await bindings.recordGeneratedKey(network, fingerprint), passes);
      expect(
        await bindings.bind(
          RobotSlot(network, fingerprint, index),
          identityOf('temple', network),
        ),
        passes,
      );
    }

    /// Loads the Garage of the testnet slot holding the fixed key, over the bindings in memory.
    Future<(GarageCubit, _CountingStorage)> loaded({
      RobotBindingRepository? over,
    }) async {
      final storage = _CountingStorage(
        entries: {testnetEntry: storedFixedKeys[testnetEntry] ?? ''},
      );
      final cubit = cubitOver(storage, bindings: over ?? bindings);
      await cubit.load();
      return (cubit, storage);
    }

    Matcher shows({required bool needsPin}) => isA<GarageWithKey>().having(
      (state) => state.deletionNeedsPin,
      'deletionNeedsPin',
      needsPin,
    );

    test(
      'a key drawn here, with no robot bound, is deleted on the confirmation alone',
      () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            fingerprint,
          ),
          passes,
        );
        // A robot of another key is bound: not this key's.
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            otherFingerprint,
          ),
          passes,
        );
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.testnet, otherFingerprint, 0),
            identityOf('temple', RobosatsNetwork.testnet),
          ),
          passes,
        );
        final (cubit, storage) = await loaded();
        expect(cubit.state, shows(needsPin: false));

        await cubit.delete(reauthenticate: neverAsked);

        expect(cubit.state, isA<GarageWithoutKey>());
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    for (final (rule, prepare) in <(String, Future<void> Function())>[
      (
        'a robot bound on its network',
        () => bindFixedRobot(RobosatsNetwork.testnet, index: 5),
      ),
      (
        'a robot bound on the other network',
        () async {
          expect(
            await bindings.recordGeneratedKey(
              RobosatsNetwork.testnet,
              fingerprint,
            ),
            passes,
          );
          await bindFixedRobot(RobosatsNetwork.mainnet);
        },
      ),
      (
        'an imported key',
        () async => expect(
          await bindings.recordImportedKey(
            RobosatsNetwork.testnet,
            fingerprint,
          ),
          passes,
        ),
      ),
      ('a key never recorded, as one drawn before the records', () async {}),
    ]) {
      test(
        '$rule: the PIN after the confirmation, before anything is deleted',
        () async {
          await prepare();
          final (cubit, storage) = await loaded();
          expect(cubit.state, shows(needsPin: true));
          final gate = _Gate(storage, testnetEntry);

          await cubit.delete(reauthenticate: gate.call);

          // Asked once, while the key was still stored.
          expect(gate.heldKeyWhenAsked, [true]);
          expect(storage.deletes, 1);
          expect(cubit.state, isA<GarageWithoutKey>());
          expect(storage.entries, isEmpty);
          await cubit.close();
        },
      );
    }

    group('a slot that cannot be read', () {
      Future<(GarageCubit, _CountingStorage)> unreadable() async {
        final storage = _CountingStorage(
          entries: {testnetEntry: 'not json at all'},
        );
        final cubit = cubitOver(storage, bindings: bindings);
        await cubit.load();
        expect(cubit.state, isA<GarageUnknown>());
        return (cubit, storage);
      }

      test(
        'with no robot of any key bound, nor any history: the PIN all the same',
        () async {
          final (cubit, storage) = await unreadable();
          expect((cubit.state as GarageUnknown).deletionNeedsPin, isTrue);
          final gate = _Gate(storage, testnetEntry, answer: false);

          await cubit.delete(reauthenticate: gate.call);
          expect(gate.heldKeyWhenAsked, [true]);
          expect(storage.deletes, 0);
          expect(cubit.state, isA<GarageUnknown>());

          await cubit.delete(reauthenticate: null);
          expect(storage.deletes, 0);

          gate.answer = true;
          await cubit.delete(reauthenticate: gate.call);
          expect(gate.asked, 2);
          expect(storage.entries, isEmpty);
          expect(cubit.state, isA<GarageWithoutKey>());
          await cubit.close();
        },
      );

      test('with a robot of any key bound: the PIN', () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.mainnet,
            otherFingerprint,
          ),
          passes,
        );
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.mainnet, otherFingerprint, 1),
            identityOf('lake', RobosatsNetwork.mainnet),
          ),
          passes,
        );
        final (cubit, storage) = await unreadable();
        final gate = _Gate(storage, testnetEntry);

        await cubit.delete(reauthenticate: gate.call);
        expect(gate.heldKeyWhenAsked, [true]);
        expect(storage.entries, isEmpty);
        await cubit.close();
      });

      test(
        '« Retry » while its delete asks the PIN reads nothing, and the PIN decides',
        () async {
          // An intact key, imported, that the keystore fails to read for a while: no robot of any key is bound.
          expect(
            await bindings.recordImportedKey(
              RobosatsNetwork.testnet,
              fingerprint,
            ),
            passes,
          );
          final storage = _CountingStorage(
            entries: {testnetEntry: storedFixedKeys[testnetEntry] ?? ''},
          );
          storage.scripted.addAll(
            List.generate(5, (_) => PlatformException(code: 'read')),
          );
          final cubit = cubitOver(storage, bindings: bindings);
          await cubit.load();
          expect(cubit.state, isA<GarageUnknown>());
          final gate = _Gate(storage, testnetEntry, answer: false)
            ..pending = Completer();

          final deleting = cubit.delete(reauthenticate: gate.call);
          await pumpEventQueue();
          expect(gate.asked, 1);
          // The user taps « Retry »: the keystore has recovered, but the delete under way is not swapped for another key.
          final reads = storage.reads;
          await cubit.load();
          expect(storage.reads, reads);
          expect(cubit.state, isA<GarageUnknown>());
          gate.pending?.complete(false);
          await deleting;

          expect(storage.deletes, 0);
          expect(storage.entries, {
            testnetEntry: storedFixedKeys[testnetEntry],
          });
          // Once the delete is over, « Retry » reads the key, which asks the PIN as imported.
          await cubit.load();
          expect(
            cubit.state,
            isA<GarageWithKey>().having(
              (state) => state.deletionNeedsPin,
              'deletionNeedsPin',
              isTrue,
            ),
          );
          await cubit.close();
        },
        timeout: slow,
      );
    });

    test(
      'a database that cannot be read: the PIN, and none without the gate',
      () async {
        final broken = RecordingBindings()
          ..readFailure = const P2pStorageFailure();
        final (cubit, storage) = await loaded(over: broken);
        expect(cubit.state, shows(needsPin: true));

        await cubit.delete(reauthenticate: null);
        expect(storage.deletes, 0);
        expect(cubit.state, shows(needsPin: true));

        final gate = _Gate(storage, testnetEntry);
        await cubit.delete(reauthenticate: gate.call);
        expect(gate.asked, 1);
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    test(
      'without the gate, nothing is deleted or replaced, and the screen stays',
      () async {
        await bindFixedRobot(RobosatsNetwork.testnet);
        final (cubit, storage) = await loaded();
        cubit.next();
        final before = cubit.state;
        final reads = storage.reads;

        await cubit.delete(reauthenticate: null);
        await cubit.replace(reauthenticate: null);

        expect(cubit.state, same(before));
        expect(storage.deletes, 0);
        expect(storage.reads, reads);
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
        await cubit.close();
      },
    );

    test(
      'a PIN the user leaves deletes nothing and leaves the screen as it was',
      () async {
        await bindFixedRobot(RobosatsNetwork.testnet);
        final (cubit, storage) = await loaded();
        cubit
          ..next()
          ..next();
        final before = cubit.state;
        final reads = storage.reads;
        final gate = _Gate(storage, testnetEntry, answer: false);

        await cubit.delete(reauthenticate: gate.call);
        await cubit.replace(reauthenticate: gate.call);

        expect(gate.asked, 2);
        expect(cubit.state, same(before));
        expect((cubit.state as GarageWithKey).robot.index, 2);
        expect(storage.deletes, 0);
        expect(storage.writes, 0);
        expect(storage.reads, reads);
        await cubit.close();
      },
    );

    test('« Generate new » asks the PIN once, then deletes and draws', () async {
      await bindFixedRobot(RobosatsNetwork.testnet);
      final (cubit, storage) = await loaded();
      final gate = _Gate(storage, testnetEntry);

      await cubit.replace(reauthenticate: gate.call);

      expect(gate.heldKeyWhenAsked, [true]);
      expect(storage.deletes, 1);
      final state = cubit.state as GarageWithKey;
      expect(state.key.key, isNot(fixedKey));
      expect(await storedIn(GarageKeySlot.testnet), state.key.key);
      // The new key was drawn here and recorded so: its own delete asks nothing.
      expect(state.deletionNeedsPin, isFalse);
      expect(state.historyNotRecorded, isFalse);
      await cubit.delete(reauthenticate: neverAsked);
      expect(cubit.state, isA<GarageWithoutKey>());
      await cubit.close();
    }, timeout: slow);

    test(
      'decides from the database when the user deletes, not when the key was read',
      () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            fingerprint,
          ),
          passes,
        );
        final (cubit, storage) = await loaded();
        expect(cubit.state, shows(needsPin: false));
        // A robot of the key is bound while the Garage shows it.
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.testnet, fingerprint, 0),
            identityOf('temple', RobosatsNetwork.testnet),
          ),
          passes,
        );

        await cubit.delete(reauthenticate: null);
        expect(storage.deletes, 0);
        // The state now says so, which greys the delete without the gate.
        expect(cubit.state, shows(needsPin: true));

        final gate = _Gate(storage, testnetEntry);
        await cubit.delete(reauthenticate: gate.call);
        expect(gate.asked, 1);
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    test('a second tap while the PIN is asked is ignored', () async {
      await bindFixedRobot(RobosatsNetwork.testnet);
      final (cubit, storage) = await loaded();
      final gate = _Gate(storage, testnetEntry)..pending = Completer();

      final first = cubit.delete(reauthenticate: gate.call);
      // Lets the first tap read the database and open the PIN.
      await pumpEventQueue();
      expect(gate.asked, 1);
      final second = cubit.delete(reauthenticate: gate.call);
      final third = cubit.replace(reauthenticate: gate.call);
      await pumpEventQueue();
      gate.pending?.complete(true);
      await Future.wait([first, second, third]);

      expect(gate.asked, 1);
      expect(storage.deletes, 1);
      expect(storage.writes, 0);
      expect(cubit.state, isA<GarageWithoutKey>());
      await cubit.close();
    });

    test(
      'a cubit closed while the database is read for a delete asks nothing and deletes nothing',
      () async {
        final slowReads = RecordingBindings(
          drawnHere: [(RobosatsNetwork.testnet, fingerprint)],
        );
        final (cubit, storage) = await loaded(over: slowReads);
        final reading = Completer<void>();
        final started = Completer<void>();
        slowReads
          ..readsWait = reading.future
          ..onRead = () {
            if (!started.isCompleted) started.complete();
          }
          // The read now says the key has a robot bound: the PIN would be asked.
          ..exposure = const GarageKeyExposure(
            history: GarageKeyHistory.drawnHere,
            hasBinding: true,
          );
        final gate = _Gate(storage, testnetEntry);

        final deleting = cubit.delete(reauthenticate: gate.call);
        await started.future;
        await cubit.close();
        reading.complete();
        await deleting;

        expect(gate.asked, 0);
        expect(storage.deletes, 0);
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      },
    );

    test('a cubit closed while the PIN is asked deletes nothing', () async {
      await bindFixedRobot(RobosatsNetwork.testnet);
      final (cubit, storage) = await loaded();
      final gate = _Gate(storage, testnetEntry)..pending = Completer();

      final deleting = cubit.delete(reauthenticate: gate.call);
      await pumpEventQueue();
      await cubit.close();
      gate.pending?.complete(true);
      await deleting;

      expect(gate.asked, 1);
      expect(storage.deletes, 0);
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
    });

    test(
      'the app hidden while « Generate new » asks the PIN: the new key arrives behind the PIN',
      () async {
        await bindFixedRobot(RobosatsNetwork.testnet);
        final (cubit, storage) = await loaded();
        final gate = _Gate(storage, testnetEntry)..pending = Completer();

        final replacing = cubit.replace(reauthenticate: gate.call);
        await pumpEventQueue();
        cubit.conceal();
        gate.pending?.complete(true);
        await replacing;

        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue)
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isFalse,
              ),
        );
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'the app hidden while the PIN is asked hides a key shown, and leaving the PIN does not show it again',
      () async {
        // The draw's record fails: the key arrives of unknown history, so « Generate new » asks the PIN.
        final failing = RecordingBindings(failure: const P2pStorageFailure())
          ..readFailure = const P2pStorageFailure();
        final storage = _CountingStorage();
        final cubit = cubitOver(storage, bindings: failing);
        await cubit.load();
        await cubit.generate();
        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having((state) => state.showWithoutPin, 'showWithoutPin', isTrue)
              .having((state) => state.deletionNeedsPin, 'needsPin', isTrue),
        );
        final drawn = storage.entries[testnetEntry];
        final gate = _Gate(storage, testnetEntry, answer: false)
          ..pending = Completer();

        final replacing = cubit.replace(reauthenticate: gate.call);
        await pumpEventQueue();
        cubit.conceal();
        expect((cubit.state as GarageWithKey).showWithoutPin, isFalse);
        gate.pending?.complete(false);
        await replacing;

        expect(
          cubit.state,
          isA<GarageWithKey>()
              .having(
                (state) => state.showWithoutPin,
                'showWithoutPin',
                isFalse,
              )
              .having((state) => state.awaitsBackup, 'awaitsBackup', isTrue),
        );
        expect(storage.entries[testnetEntry], drawn);
        expect(storage.deletes, 0);
        await cubit.close();
      },
      timeout: slow,
    );
  });

  group('a key whose draw could not be recorded', () {
    test(
      'is said so, through the wizard and the profile, until it is deleted',
      () async {
        final bindings = RecordingBindings(failure: const P2pStorageFailure());
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, bindings: bindings);
        await cubit.load();

        await cubit.generate();

        // Stored all the same, of unknown history.
        expect(storage.entries.keys, [testnetEntry]);
        expect(
          bindings.calls.where((call) => call.$1 == 'recordGeneratedKey'),
          hasLength(2),
        );
        bool said() => (cubit.state as GarageWithKey).historyNotRecorded;
        expect(said(), isTrue);
        cubit.next();
        expect(said(), isTrue);
        cubit.conceal();
        expect(said(), isTrue);
        cubit.acknowledgeBackup();
        expect(said(), isTrue);
        // Its history is unknown, so its delete asks the PIN, as the database would say.
        expect((cubit.state as GarageWithKey).deletionNeedsPin, isTrue);
        var asked = 0;
        Future<bool> passes() async {
          asked++;
          return true;
        }

        // A failed delete reads the slot again: the same key, still said.
        storage.scriptedWrites.add(PlatformException(code: 'delete failed'));
        await cubit.delete(reauthenticate: passes);
        expect(asked, 1);
        expect(said(), isTrue);

        await cubit.delete(reauthenticate: passes);
        expect(asked, 2);
        expect(cubit.state, isA<GarageWithoutKey>());
        bindings.failure = null;
        await cubit.generate();
        expect(said(), isFalse);
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'is not said of another key found in the slot once it was deleted',
      () async {
        final bindings = RecordingBindings(failure: const P2pStorageFailure());
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, bindings: bindings);
        await cubit.load();
        await cubit.generate();
        expect((cubit.state as GarageWithKey).historyNotRecorded, isTrue);
        var asked = 0;
        await cubit.delete(
          reauthenticate: () async {
            asked++;
            return true;
          },
        );
        expect(asked, 1);
        expect(cubit.state, isA<GarageWithoutKey>());

        // Another key appears in the slot before « Generate Garage Key »: the vault refuses the draw, and the slot is read again.
        storage.entries[testnetEntry] = storedFixedKeys[testnetEntry] ?? '';
        await cubit.generate();

        final state = cubit.state as GarageWithKey;
        expect(state.key.key, fixedKey);
        expect(state.historyNotRecorded, isFalse);
        await cubit.close();
      },
      timeout: slow,
    );

    test('is not said of a key recorded, pasted or read at a visit', () async {
      final bindings = RecordingBindings();
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(storage, bindings: bindings);
      await cubit.load();
      await cubit.generate();
      expect((cubit.state as GarageWithKey).historyNotRecorded, isFalse);
      await cubit.delete(reauthenticate: neverAsked);

      await cubit.import(exampleText);
      expect((cubit.state as GarageWithKey).historyNotRecorded, isFalse);
      await cubit.close();

      // A key read at a later visit was not just drawn, whatever its history.
      final later = cubitOver(storage, bindings: bindings);
      await later.load();
      expect((later.state as GarageWithKey).historyNotRecorded, isFalse);
      await later.close();
    }, timeout: slow);

    test(
      'is not said of a key pasted after a delete that failed but emptied the slot',
      () async {
        final bindings = RecordingBindings(failure: const P2pStorageFailure());
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, bindings: bindings);
        await cubit.load();
        await cubit.generate();
        expect((cubit.state as GarageWithKey).historyNotRecorded, isTrue);

        // The keystore loses the entry but reports the delete as failed: the slot is read again, and found empty.
        storage.entries.remove(testnetEntry);
        storage.scriptedWrites.add(PlatformException(code: 'delete failed'));
        await cubit.delete(reauthenticate: () async => true);
        expect(cubit.state, isA<GarageWithoutKey>());

        bindings.failure = null;
        await cubit.import(exampleText);

        expect(cubit.state, isA<GarageWithKey>());
        expect((cubit.state as GarageWithKey).historyNotRecorded, isFalse);
        await cubit.close();
      },
      timeout: slow,
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
        await cubit.replace(reauthenticate: neverAsked);
        seen.add((cubit.state as GarageWithKey).key.key);
        await cubit.delete(reauthenticate: neverAsked);
        await cubit.import(exampleText);
        // A pasted key may have robots on a coordinator: its delete asks the PIN.
        await cubit.delete(reauthenticate: () async => true);
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
