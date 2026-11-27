import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart' show P2pGarageKeyRefusalReason;
import 'package:p2p/src/data/garage_key_book_repository_impl.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_keyring.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, GarageKeys, Secrets;
import 'package:secrets/testing.dart';

import 'migrations_test/p2p_database/generated/schema_v9.dart' as v9;
import 'support/garage_words.dart';

/// The Garage Keys of P2P since #81 (design note `docs/design/garage-key-from-the-words.md`), through the real repository, the real vault of `package:secrets` over its in-memory keystore, the real derivation of the public test words and the real database: key 0 at the first opening, « New key », the key selected, the keys checked against their fingerprints, the refusals that never draw a key, and the external key, the one the vault kept before #81 or a key pasted, kept with its robots and its trades, nothing erased.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const mainnet = RobosatsNetwork.mainnet;
  const testnet = RobosatsNetwork.testnet;
  const mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
  const testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';
  const slow = Timeout(Duration(seconds: 120));

  // Fixed test bytes, 0x01 to 0x20: the key drawn at random of these tests, not a key anyone uses.
  final drawnKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final drawnFingerprint = switch (GarageKeyFingerprint.of(drawnKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  late FakeSecureStoragePlatform storage;
  late GarageKeys vault;
  late TestWordsPort words;
  late Directory directory;

  setUp(() async {
    storage = FakeSecureStoragePlatform()..install();
    vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    words = TestWordsPort();
    directory = await Directory.systemTemp.createTemp('p2p-garage-keys-');
  });

  tearDown(() => directory.delete(recursive: true));

  final now = DateTime.utc(2026, 11, 26, 12);

  GarageKeyRepositoryImpl repositoryOver(P2pDatabase database) =>
      GarageKeyRepositoryImpl(
        vault,
        words,
        GarageKeyBookRepositoryImpl(database, clock: () => now),
      );

  P2pDatabase memory() {
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    return database;
  }

  NetworkGarageKey keyOf(Result<NetworkGarageKey, P2pFailure> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  GarageKeyFingerprint fingerprintOf(NetworkGarageKey key) =>
      switch (key.fingerprint) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  Future<List<String>> selectionsOf(P2pDatabase database) async => [
    for (final row
        in await database
            .customSelect(
              'SELECT network, key_index FROM selected_garage_keys ORDER BY network',
            )
            .get())
      '${row.read<String>('network')} ${row.readNullable<int>('key_index')}',
  ];

  /// A file of schema 9 at [file], with nothing in it: opened once, so that it exists.
  Future<void> nineAt(File file) async {
    final nine = v9.DatabaseAtV9(NativeDatabase(file));
    await nine.customSelect('SELECT 1').get();
    await nine.close();
  }

  Future<void> storeKeyIn(GarageKeySlot slot) async => expect(
    await vault.import(slot: slot, bytes: drawnKey.revealBytes()),
    isA<Ok<Object?, Failure>>(),
  );

  Future<int> countOf(P2pDatabase database, String table) async =>
      (await database
              .customSelect('SELECT count(*) AS n FROM $table')
              .getSingle())
          .read<int>('n');

  group('the keys of the words', () {
    test(
      'the first opening activates key 0 of the words, recorded as drawn here',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        // No external key: key 0 is selected, and recorded.
        expect(
          await repository.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 0,
              selected: SelectedWordsKey(0),
              lastInternal: 0,
            ),
          ),
        );
        final key = keyOf(await repository.read(mainnet));
        expect(key.index, 0);
        expect(key.network, mainnet);
        expect(key.key.revealBech32(), abandonMainnet0);
        final testnetKey = keyOf(await repository.read(testnet));
        expect(testnetKey.key.revealBech32(), abandonTestnet0);
        // Recorded as drawn here on its network, so that its robots may be bound and trade.
        final exposure = await RobotBindingRepositoryImpl(
          database,
          clock: () => now,
        ).exposureOf(mainnet, fingerprintOf(key));
        expect(
          exposure,
          isA<Ok<GarageKeyExposure, P2pFailure>>().having(
            (ok) => ok.value.history,
            'history',
            GarageKeyHistory.drawnHere,
          ),
        );
        expect(await selectionsOf(database), ['mainnet 0', 'testnet 0']);
        // Nothing of the key is at rest: no entry in the vault, only the index and the fingerprint in the database.
        expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        expect(storage.entries.keys, isNot(contains(testnetEntry)));
        expect(await countOf(database, 'derived_garage_keys'), 2);
      },
      timeout: slow,
    );

    test(
      '« New key » activates the next index, one at a time, and new trades take the highest key only',
      () async {
        final repository = repositoryOver(memory());
        expect(
          await repository.keyring(mainnet),
          isA<Ok<GarageKeyring, P2pFailure>>(),
        );
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        expect(
          keyOf(await repository.read(mainnet)).key.revealBech32(),
          abandonMainnet1,
        );
        final earlier = keyOf(await repository.derived(mainnet, 0));
        expect(earlier.index, 0);
        expect(earlier.key.revealBech32(), abandonMainnet0);
        final forTrades = keyOf(await repository.forNewTrade(mainnet));
        expect(forTrades.index, 1);
        expect(forTrades.key.revealBech32(), abandonMainnet1);
        // A second tap after the first one won: nothing more.
        expect(
          await repository.activateNext(mainnet, after: 0),
          isErr<GarageKeyMissingFailure>(),
        );
        expect(
          await repository.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 1,
              selected: SelectedWordsKey(1),
              lastInternal: 1,
            ),
          ),
        );
        // Two taps at once: one key.
        final both = await Future.wait([
          repository.activateNext(mainnet, after: 1),
          repository.activateNext(mainnet, after: 1),
        ]);
        expect(both.whereType<Ok<int, P2pFailure>>().map((ok) => ok.value), [
          2,
        ]);
        expect(
          keyOf(await repository.forNewTrade(mainnet)).key.revealBech32(),
          abandonMainnet2,
        );
        // « › » never creates: a key above the highest is not given.
        expect(
          await repository.derived(mainnet, 3),
          isErr<GarageKeyMissingFailure>(),
        );
        expect(
          await repository.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 2,
              selected: SelectedWordsKey(2),
              lastInternal: 2,
            ),
          ),
        );
      },
      timeout: slow,
    );

    test(
      'new trades take the key selected, whatever its number, and the selection survives a restart',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(
          await repository.keyring(mainnet),
          isA<Ok<GarageKeyring, P2pFailure>>(),
        );
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        // « New key » selects the key it makes.
        expect(keyOf(await repository.forNewTrade(mainnet)).index, 1);
        // « ‹ »: key 0 selected, the key of new trades from then on.
        expect(
          await repository.select(mainnet, const SelectedWordsKey(0)),
          isOk(null),
        );
        final forTrades = keyOf(await repository.forNewTrade(mainnet));
        expect(forTrades.index, 0);
        expect(forTrades.key.revealBech32(), abandonMainnet0);
        expect(keyOf(await repository.read(mainnet)).index, 0);
        // Restarted over the same book: still key 0.
        final again = repositoryOver(database);
        expect(
          await again.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 1,
              selected: SelectedWordsKey(0),
              lastInternal: 0,
            ),
          ),
        );
        expect(keyOf(await again.forNewTrade(mainnet)).index, 0);
        // Another network keeps its own selection, and a key not activated is never selected.
        expect(keyOf(await again.forNewTrade(testnet)).index, 0);
        expect(
          await again.select(mainnet, const SelectedWordsKey(2)),
          isErr<GarageKeyMissingFailure>(),
        );
        // Nor an external key the vault does not keep.
        expect(
          await again.select(mainnet, const SelectedExternalKey()),
          isErr<GarageKeyMissingFailure>(),
        );
        // « New key » from key 0 makes key 2, after the highest, and selects it.
        expect(await again.activateNext(mainnet, after: 1), isOk(2));
        expect(keyOf(await again.forNewTrade(mainnet)).index, 2);
      },
      timeout: slow,
    );

    test('the last index has no next key, and 2^31 is never asked', () async {
      final database = memory();
      final repository = repositoryOver(database);
      expect(
        await repository.keyring(mainnet),
        isA<Ok<GarageKeyring, P2pFailure>>(),
      );
      expect(
        await repository.activateNext(mainnet, after: 0x7fffffff),
        isErr<GarageKeyLastIndexFailure>(),
      );
      final book = GarageKeyBookRepositoryImpl(database, clock: () => now);
      final fingerprint = fingerprintOf(keyOf(await repository.read(mainnet)));
      expect(
        () => book.activate(mainnet, 0x80000000, fingerprint),
        throwsArgumentError,
      );
      expect(
        words.asked.map((asked) => asked.$2),
        everyElement(lessThan(0x80000000)),
      );
    });

    test(
      'a key the words give again that is not the recorded one is refused everywhere, never signed with',
      () async {
        final repository = repositoryOver(memory());
        final recorded = keyOf(await repository.read(mainnet));
        final robot = switch (recorded.firstUsableRobot(0)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        // Other words restored in the same book.
        words.words = legalWords;
        for (final result in [
          await repository.read(mainnet),
          await repository.derived(mainnet, 0),
          await repository.forNewTrade(mainnet),
          await repository.ofSlot(robot.slot),
        ]) {
          expect(result, isErr<GarageKeyMismatchFailure>());
        }
        expect(
          await repository.activateNext(mainnet, after: 0),
          isA<Err<int, P2pFailure>>(),
        );
      },
      timeout: slow,
    );

    test(
      'the robot of a recorded trade finds its own key by fingerprint, whichever key is selected',
      () async {
        final repository = repositoryOver(memory());
        final first = keyOf(await repository.read(mainnet));
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        // Key 1 selected, the key of new trades; the trade of key 0 goes on with key 0.
        expect(keyOf(await repository.forNewTrade(mainnet)).index, 1);
        final robot = switch (first.firstUsableRobot(3)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final found = keyOf(await repository.ofSlot(robot.slot));
        expect(found.index, 0);
        expect(found.key.revealBech32(), abandonMainnet0);
        expect(
          await repository.ofSlot(RobotSlot(mainnet, drawnFingerprint, 0)),
          isErr<TradeKeyMissingFailure>(),
        );
      },
      timeout: slow,
    );

    test(
      'when the words cannot give a key, nothing is activated and nothing is drawn',
      () async {
        for (final (reason, failure)
            in <(P2pGarageKeyRefusalReason, P2pFailure)>[
              (
                P2pGarageKeyRefusalReason.noDefaultWallet,
                const GarageKeyNoWalletFailure(),
              ),
              (
                P2pGarageKeyRefusalReason.passphrase,
                const GarageKeyPassphraseFailure(),
              ),
              (
                P2pGarageKeyRefusalReason.noWords,
                const GarageKeyNoWordsFailure(),
              ),
              (
                P2pGarageKeyRefusalReason.locked,
                const GarageKeyLockedFailure(),
              ),
              (
                P2pGarageKeyRefusalReason.unreadable,
                const GarageKeyUnreadableFailure(),
              ),
            ]) {
          words.refusal = reason;
          final database = memory();
          final repository = repositoryOver(database);
          expect(
            await repository.keyring(mainnet),
            isErrLike(failure),
            reason: reason.name,
          );
          expect(
            await repository.forNewTrade(mainnet),
            isErrLike(failure),
            reason: reason.name,
          );
          expect(await countOf(database, 'derived_garage_keys'), 0);
          expect(await countOf(database, 'garage_key_histories'), 0);
          expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        }
      },
      // Since the review of #292 the slot is read before the refusal is given (C-passphrase): an empty slot costs its full read budget at each reading.
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('the external key', () {
    /// A file of schema 9 with the key drawn here before #81, a robot of it bound and its trade, open unless [closed].
    Future<File> schema9File({required bool closed}) async {
      final file = File('${directory.path}/nine.sqlite');
      final old = v9.DatabaseAtV9(NativeDatabase(file));
      final fingerprint = drawnFingerprint.hex;
      for (final statement in [
        "INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES ('mainnet', '$fingerprint', 'generated', 1)",
        "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('mainnet', '$fingerprint', 0, 'temple', 'http://temple.onion', '', 'abc', 2, 'generated')",
        "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('mainnet', '$fingerprint', 0, 'temple', 'http://temple.onion', 42, 'buyer', 'takenHere', 3, 4, ${closed ? 5 : 'NULL'})",
      ]) {
        await old.customStatement(statement);
      }
      await old.close();
      return file;
    }

    Future<void> storeDrawnKey() async {
      expect(
        await vault.import(
          slot: GarageKeySlot.mainnet,
          bytes: drawnKey.revealBytes(),
        ),
        isA<Ok<Object?, Failure>>(),
      );
    }

    P2pDatabase open(File file) {
      final database = P2pDatabase.forTesting(NativeDatabase(file));
      addTearDown(database.close);
      return database;
    }

    test(
      'after the update, the key the vault kept is the external key, selected, with its robots and its open trade, which goes on with it',
      () async {
        await storeDrawnKey();
        final database = open(await schema9File(closed: false));
        final repository = repositoryOver(database);
        expect(
          await repository.keyring(mainnet),
          isOk(
            GarageKeyring(
              highest: 0,
              selected: const SelectedExternalKey(),
              externalNoticeDue: true,
              external: drawnFingerprint,
            ),
          ),
        );
        expect(await selectionsOf(database), ['mainnet null']);
        // The key of new trades is the external key, as it was before the update, with its rights: a key drawn here.
        final forTrades = keyOf(await repository.forNewTrade(mainnet));
        expect(forTrades.index, isNull);
        expect(forTrades.key, drawnKey);
        final exposure = await RobotBindingRepositoryImpl(
          database,
          clock: () => now,
        ).exposureOf(mainnet, drawnFingerprint);
        expect(
          exposure,
          isA<Ok<GarageKeyExposure, P2pFailure>>().having(
            (ok) => ok.value.history,
            'history',
            GarageKeyHistory.drawnHere,
          ),
        );
        // « New key » makes key 1 of the words above the highest, key 0; the external key does not count.
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        expect(
          await repository.keyring(mainnet),
          isOk(
            GarageKeyring(
              highest: 1,
              selected: const SelectedWordsKey(1),
              lastInternal: 1,
              externalNoticeDue: true,
              external: drawnFingerprint,
            ),
          ),
        );
        expect(
          keyOf(await repository.forNewTrade(mainnet)).key.revealBech32(),
          abandonMainnet1,
        );
        // The open trade of the external key goes on with the external key, never with the key selected.
        final ofTrade = keyOf(
          await repository.ofSlot(RobotSlot(mainnet, drawnFingerprint, 0)),
        );
        expect(ofTrade.index, isNull);
        expect(ofTrade.key, drawnKey);
        // Nothing erased: the vault entry and every row of the book stay.
        expect(storage.entries.keys, contains(mainnetEntry));
        expect(await countOf(database, 'trades'), 1);
        expect(await countOf(database, 'robot_bindings'), 1);
        expect(await countOf(database, 'garage_key_histories'), 3);
        // Back to the external key: « ‹ » and « › » reach it, after the highest key of the words.
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(keyOf(await repository.forNewTrade(mainnet)).key, drawnKey);
      },
      timeout: slow,
    );

    test(
      'a trade of a key of the words goes on with that key while the external key is selected',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        final words0 = keyOf(await repository.read(mainnet));
        await storeDrawnKey();
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(keyOf(await repository.forNewTrade(mainnet)).key, drawnKey);
        final robot = switch (words0.firstUsableRobot(2)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final found = keyOf(await repository.ofSlot(robot.slot));
        expect(found.index, 0);
        expect(found.key.revealBech32(), abandonMainnet0);
      },
      timeout: slow,
    );

    test(
      'a key pasted is the external key, selected at once, recorded from elsewhere, and only one at a time',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(keyOf(await repository.read(mainnet)).index, 0);
        expect(
          await ImportGarageKeyUsecase(
            repository,
            RobotBindingRepositoryImpl(database, clock: () => now),
          ).execute(mainnet, text: drawnKey.revealBech32()),
          isOk(null),
        );
        expect(
          await repository.keyring(mainnet),
          isOk(
            GarageKeyring(
              highest: 0,
              selected: const SelectedExternalKey(),
              lastInternal: 0,
              external: drawnFingerprint,
            ),
          ),
        );
        // Recorded as imported: its robots may live elsewhere, which a binding of « Select Host » says; it trades as any other key (decided on 2026-11-26, #81).
        final exposure = await RobotBindingRepositoryImpl(
          database,
          clock: () => now,
        ).exposureOf(mainnet, drawnFingerprint);
        expect(
          exposure,
          isA<Ok<GarageKeyExposure, P2pFailure>>().having(
            (ok) => ok.value.history,
            'history',
            isNot(GarageKeyHistory.drawnHere),
          ),
        );
        // A second paste is refused while the vault keeps one: nothing replaced.
        expect(
          await repository.import(mainnet, drawnKey),
          isErr<GarageKeyAlreadyStoredFailure>(),
        );
      },
      timeout: slow,
    );

    test(
      'removing the external key deletes its vault entry only, and selects the last internal key selected',
      () async {
        await storeDrawnKey();
        final database = open(await schema9File(closed: true));
        final repository = repositoryOver(database);
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(await repository.delete(mainnet), isOk(null));
        expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        expect(
          await repository.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 1,
              selected: SelectedWordsKey(1),
              lastInternal: 1,
              externalNoticeDue: true,
            ),
          ),
        );
        // Its records stay: a key pasted back finds its robots bound where they were.
        expect(await countOf(database, 'trades'), 1);
        expect(await countOf(database, 'robot_bindings'), 1);
        expect(await countOf(database, 'derived_garage_keys'), 2);
      },
      timeout: slow,
    );

    test(
      'an external key that cannot be read keeps its position and is never taken for an empty slot',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(keyOf(await repository.read(mainnet)).index, 0);
        storage.entries[mainnetEntry] = 'not a key';
        final keyring = await repository.keyring(mainnet);
        expect(
          keyring,
          isA<Ok<GarageKeyring, P2pFailure>>().having(
            (ok) => (ok.value.hasExternal, ok.value.external),
            'external',
            (true, null),
          ),
        );
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(
          await repository.forNewTrade(mainnet),
          isA<Err<NetworkGarageKey, P2pFailure>>(),
        );
        expect(
          await repository.import(mainnet, drawnKey),
          isErr<GarageKeyAlreadyStoredFailure>(),
        );
      },
      timeout: slow,
    );

    test(
      'an external key selected that the vault no longer keeps gives way to the highest key of the words',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(keyOf(await repository.read(mainnet)).index, 0);
        await storeDrawnKey();
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(
          await vault.delete(slot: GarageKeySlot.mainnet),
          isA<Ok<Object?, Failure>>(),
        );
        expect(
          await repository.keyring(mainnet),
          isOk(
            const GarageKeyring(
              highest: 0,
              selected: SelectedWordsKey(0),
              lastInternal: 0,
            ),
          ),
        );
        expect(await selectionsOf(database), ['mainnet 0']);
      },
      timeout: slow,
    );
  });

  group('after the first review and the mock-up (#292)', () {
    Future<void> storeKey(GarageKey key) async {
      expect(
        await vault.import(
          slot: GarageKeySlot.mainnet,
          bytes: key.revealBytes(),
        ),
        isA<Ok<Object?, Failure>>(),
      );
    }

    GarageKey parsed(String text) => switch (GarageKey.parse(text)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

    for (final (reason, failure) in <(P2pGarageKeyRefusalReason, Matcher)>[
      (
        P2pGarageKeyRefusalReason.noDefaultWallet,
        isA<GarageKeyNoWalletFailure>(),
      ),
      (P2pGarageKeyRefusalReason.passphrase, isA<GarageKeyPassphraseFailure>()),
      (P2pGarageKeyRefusalReason.noWords, isA<GarageKeyNoWordsFailure>()),
      (P2pGarageKeyRefusalReason.locked, isA<GarageKeyLockedFailure>()),
      (P2pGarageKeyRefusalReason.unreadable, isA<GarageKeyUnreadableFailure>()),
    ]) {
      test(
        'words that refuse (${reason.name}) leave the external Garage Key shown, usable and deletable; without it, the refusal (C-passphrase)',
        () async {
          words.refusal = reason;
          final database = memory();
          final repository = repositoryOver(database);
          // Without an external Garage Key: the refusal, as before, and nothing written.
          expect(
            await repository.keyring(mainnet),
            isA<Err<GarageKeyring, P2pFailure>>().having(
              (err) => err.failure,
              'failure',
              failure,
            ),
          );
          expect(await selectionsOf(database), isEmpty);
          // With one: the keyring offers it, selected, and the internal side says why.
          await storeKey(drawnKey);
          final keyring = switch (await repository.keyring(mainnet)) {
            Ok(:final value) => value,
            Err(:final failure) => fail('$failure'),
          };
          expect(keyring.highest, isNull);
          expect(keyring.internalFailure, failure);
          expect(keyring.selected, const SelectedExternalKey());
          expect(keyring.external, drawnFingerprint);
          expect(keyOf(await repository.read(mainnet)).key, drawnKey);
          expect(keyOf(await repository.forNewTrade(mainnet)).key, drawnKey);
          expect(
            keyOf(
              await repository.ofSlot(RobotSlot(mainnet, drawnFingerprint, 3)),
            ).key,
            drawnKey,
          );
          // « Back to internal Garage Keys »: the refusal, the external Garage Key still selected.
          expect(
            await repository.selectInternal(mainnet),
            isA<Err<void, P2pFailure>>().having(
              (err) => err.failure,
              'failure',
              failure,
            ),
          );
          expect(await selectionsOf(database), ['mainnet null']);
          // It can be deleted; then nothing is left to show but the refusal.
          expect(await repository.delete(mainnet), isOk(null));
          expect(storage.entries.keys, isNot(contains(mainnetEntry)));
          expect(
            await repository.keyring(mainnet),
            isA<Err<GarageKeyring, P2pFailure>>(),
          );
        },
        timeout: slow,
      );
    }

    test(
      'words that refuse once keys were activated: the keyring stands, the internal key is refused, the external one given',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        await storeKey(drawnKey);
        words.refusal = P2pGarageKeyRefusalReason.passphrase;
        final keyring = switch (await repository.keyring(mainnet)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(keyring.highest, 1);
        expect(keyring.selected, const SelectedWordsKey(1));
        expect(
          await repository.derived(mainnet, 1),
          isErr<GarageKeyPassphraseFailure>(),
        );
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(keyOf(await repository.forNewTrade(mainnet)).key, drawnKey);
      },
      timeout: slow,
    );

    test(
      '« Back to internal Garage Keys » selects the last internal one selected, kept across a restart and a delete, else the highest',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        expect(await repository.activateNext(mainnet, after: 1), isOk(2));
        expect(
          await repository.select(mainnet, const SelectedWordsKey(1)),
          isOk(null),
        );
        await storeKey(drawnKey);
        expect(
          await repository.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        // Restarted: the external key, and key 1 remembered.
        final again = repositoryOver(database);
        expect(
          await again.keyring(mainnet),
          isOk(
            GarageKeyring(
              highest: 2,
              selected: const SelectedExternalKey(),
              lastInternal: 1,
              external: drawnFingerprint,
            ),
          ),
        );
        expect(await again.selectInternal(mainnet), isOk(null));
        expect(keyOf(await again.read(mainnet)).index, 1);
        // Deleted while selected: back to key 1, not to the highest nor to key 0.
        expect(
          await again.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(await again.delete(mainnet), isOk(null));
        expect(keyOf(await again.read(mainnet)).index, 1);
        // No internal key ever selected: the highest.
        await storeKey(drawnKey);
        final other = memory();
        final fresh = repositoryOver(other);
        expect(await fresh.activateNext(mainnet, after: 0), isOk(1));
        await other.customStatement('DELETE FROM selected_garage_keys');
        expect(
          await fresh.select(mainnet, const SelectedExternalKey()),
          isOk(null),
        );
        expect(await fresh.selectInternal(mainnet), isOk(null));
        expect(keyOf(await fresh.read(mainnet)).index, 1);
      },
      timeout: slow,
    );

    test(
      '« Your Garage Keys » is due after the update only, shown once, never on a new install nor after an import',
      () async {
        Future<bool> due(
          GarageKeyRepositoryImpl repository, [
          RobosatsNetwork network = mainnet,
        ]) async => switch (await repository.keyring(network)) {
          Ok(:final value) => value.externalNoticeDue,
          Err(:final failure) => fail('$failure'),
        };
        // A new install: never, even with a key in the vault (one an earlier install left).
        await storeKey(drawnKey);
        final fresh = memory();
        expect(await due(repositoryOver(fresh)), isFalse);
        expect(await countOf(fresh, 'garage_notices'), 0);
        expect(
          await vault.delete(slot: GarageKeySlot.mainnet),
          isA<Ok<Object?, Failure>>(),
        );
        // The update without a key in the vault: nothing to say, then nothing after an import either.
        final emptyFile = File('${directory.path}/empty-nine.sqlite');
        await nineAt(emptyFile);
        final empty = P2pDatabase.forTesting(NativeDatabase(emptyFile));
        addTearDown(empty.close);
        final withoutKey = repositoryOver(empty);
        expect(await due(withoutKey), isFalse);
        expect(
          await ImportGarageKeyUsecase(
            withoutKey,
            RobotBindingRepositoryImpl(empty, clock: () => now),
          ).execute(mainnet, text: drawnKey.revealBech32()),
          isOk(null),
        );
        expect(await due(withoutKey), isFalse);
        expect(
          await vault.delete(slot: GarageKeySlot.mainnet),
          isA<Ok<Object?, Failure>>(),
        );
        // The update with a key in the vault: due until shown, then never again, on any network.
        await storeKey(drawnKey);
        final file = File('${directory.path}/key-nine.sqlite');
        await nineAt(file);
        final updated = P2pDatabase.forTesting(NativeDatabase(file));
        addTearDown(updated.close);
        final repository = repositoryOver(updated);
        expect(await due(repository), isTrue);
        expect(await due(repository), isTrue);
        expect(await repository.externalNoticeShown(), isOk(null));
        expect(await due(repository), isFalse);
        expect(
          await vault.import(
            slot: GarageKeySlot.testnet,
            bytes: drawnKey.revealBytes(),
          ),
          isA<Ok<Object?, Failure>>(),
        );
        expect(await due(repository, testnet), isFalse);
        // The database keeps it so: a notice shown never turns due again, nor is deleted.
        await expectLater(
          updated.customStatement('UPDATE garage_notices SET shown = 0'),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          updated.customStatement('DELETE FROM garage_notices'),
          throwsA(isA<Exception>()),
        );
      },
      timeout: slow,
    );

    test(
      'an internal Garage Key pasted in « Robot recovery » is refused, said by its number, and nothing is recorded or stored',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        final import = ImportGarageKeyUsecase(
          repository,
          RobotBindingRepositoryImpl(database, clock: () => now),
        );
        for (final (text, index) in [
          (abandonMainnet0, 0),
          (abandonMainnet1, 1),
        ]) {
          expect(
            await import.execute(mainnet, text: text),
            isA<Err<void, P2pFailure>>().having(
              (err) => err.failure,
              'failure',
              isA<GarageKeyIsInternalFailure>().having(
                (failure) => failure.index,
                'index',
                index,
              ),
            ),
          );
        }
        expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        expect(
          (await database
                  .customSelect('SELECT origin FROM garage_key_histories')
                  .get())
              .map((row) => row.read<String>('origin')),
          everyElement('generated'),
        );
        // A key the words did not give on this network yet is imported.
        expect(
          await import.execute(mainnet, text: abandonMainnet2),
          isOk(null),
        );
      },
      timeout: slow,
    );

    test(
      '« New internal Garage Key » that gives the key already external activates it: the same records, its trades going on, nothing lost',
      () async {
        final database = memory();
        final repository = repositoryOver(database);
        expect(keyOf(await repository.read(mainnet)).index, 0);
        final external = parsed(abandonMainnet1);
        await storeKey(external);
        final fingerprint = switch (GarageKeyFingerprint.of(external)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(await repository.activateNext(mainnet, after: 0), isOk(1));
        final keyring = switch (await repository.keyring(mainnet)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(keyring.fingerprints, hasLength(2));
        expect(keyring.fingerprints.last, fingerprint);
        expect(keyring.external, fingerprint);
        // A robot of that key finds its key, the internal one, the same bytes.
        final found = keyOf(
          await repository.ofSlot(RobotSlot(mainnet, fingerprint, 4)),
        );
        expect(found.index, 1);
        expect(found.key, external);
      },
      timeout: slow,
    );
  });

  // Restored from `main` (review of #292): the vault slot of each network, which keeps the external Garage Key since #81. `create`, gone with #81, has no test any more.
  group('the vault slot of the external Garage Key', () {
    /// The keystore of the test made [replacement], with the vault over it; the words derived beforehand over a keystore of their own, then given from memory.
    Future<void> keystore(FakeSecureStoragePlatform replacement) async {
      final port = TestWordsPort();
      FakeSecureStoragePlatform().install();
      await port.precompute([(mainnet, 0), (testnet, 0)]);
      storage = replacement..install();
      vault = Secrets(scratchDirectory: () async => '.').garageKeys();
      words = port;
    }

    Future<String> storedEntry() async {
      final scratch = FakeSecureStoragePlatform()..install();
      final scratchVault = Secrets(
        scratchDirectory: () async => '.',
      ).garageKeys();
      expect(
        await scratchVault.import(
          slot: GarageKeySlot.mainnet,
          bytes: drawnKey.revealBytes(),
        ),
        isA<Ok<Object?, Failure>>(),
      );
      return scratch.entries[mainnetEntry] ?? fail('nothing stored');
    }

    Iterable<String> garageReads() =>
        storage.readKeys.where((key) => key.contains('/garage/'));

    test(
      'is read with the network of its slot, never the other, and of one network is never reached from the other',
      () async {
        await storeKeyIn(GarageKeySlot.testnet);
        final repository = repositoryOver(memory());
        final testnetKey = keyOf(await repository.read(testnet));
        expect(testnetKey, NetworkGarageKey(testnet, drawnKey));
        expect(
          await repository.firstUsableRobot(testnet),
          isA<Ok<NetworkRobot, P2pFailure>>().having(
            (ok) => (ok.value.network, ok.value.slot.keyFingerprint),
            'network and key',
            (testnet, drawnFingerprint),
          ),
        );
        // Mainnet has no external key: its internal key 0, and a delete there touches nothing of testnet.
        expect(keyOf(await repository.read(mainnet)).index, 0);
        expect(await repository.delete(mainnet), isOk(null));
        expect(storage.entries[testnetEntry], isNotNull);
        expect(keyOf(await repository.read(testnet)).key, drawnKey);
        expect(garageReads().toSet(), {testnetEntry, mainnetEntry});
      },
      timeout: slow,
    );

    test(
      'is never replaced: an import is refused while it holds a key',
      () async {
        await storeKeyIn(GarageKeySlot.mainnet);
        final before = storage.entries[mainnetEntry];
        final repository = repositoryOver(memory());
        final example = switch (GarageKey.parse(abandonMainnet2)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(
          await repository.import(mainnet, example),
          isErr<GarageKeyAlreadyStoredFailure>(),
        );
        expect(storage.entries[mainnetEntry], before);
        expect(keyOf(await repository.read(mainnet)).key, drawnKey);
      },
      timeout: slow,
    );

    test(
      'an entry that cannot be used is reported as such, refused as a slot, and kept until deleted',
      () async {
        storage.entries[mainnetEntry] = 'not json at all';
        final repository = repositoryOver(memory());
        expect(
          await repository.read(mainnet),
          isErr<GarageKeyUnusableFailure>(),
        );
        expect(
          await repository.firstUsableRobot(mainnet),
          isErr<GarageKeyUnusableFailure>(),
        );
        expect(
          await repository.exists(mainnet),
          isErr<GarageKeyUnusableFailure>(),
        );
        expect(
          await repository.import(mainnet, drawnKey),
          isErr<GarageKeyAlreadyStoredFailure>(),
        );
        expect(storage.entries[mainnetEntry], 'not json at all');
        expect(await repository.delete(mainnet), isOk(null));
        expect(storage.entries, isNot(contains(mainnetEntry)));
        expect(keyOf(await repository.read(mainnet)).index, 0);
      },
      timeout: slow,
    );

    test(
      'an entry that keeps failing to read is unreadable, and nothing is written over it',
      () async {
        final entry = await storedEntry();
        await keystore(
          FakeSecureStoragePlatform(
            entries: {mainnetEntry: entry},
            scripted: List.generate(
              20,
              (_) => PlatformException(code: 'read failed'),
            ),
          ),
        );
        final repository = repositoryOver(memory());
        expect(
          await repository.keyring(mainnet),
          isA<Ok<GarageKeyring, P2pFailure>>().having(
            (ok) => ok.value.externalFailure,
            'externalFailure',
            isA<GarageKeyUnreadableFailure>(),
          ),
        );
        expect(
          await repository.read(mainnet),
          isErr<GarageKeyUnreadableFailure>(),
        );
        expect(storage.entries[mainnetEntry], entry);
      },
      timeout: slow,
    );

    test(
      'a locked keystore is reported as locked, and nothing is written or deleted',
      () async {
        final entry = await storedEntry();
        await keystore(
          FakeSecureStoragePlatform(
            entries: {mainnetEntry: entry},
            locked: true,
            writesFail: true,
          ),
        );
        final repository = repositoryOver(memory());
        for (final result in [
          await repository.read(mainnet),
          await repository.firstUsableRobot(mainnet),
          await repository.exists(mainnet),
          await repository.import(mainnet, drawnKey),
        ]) {
          expect(result, isErr<GarageKeyLockedFailure>());
        }
        storage
          ..locked = false
          ..writesFail = true;
        expect(
          await repository.delete(mainnet),
          isErr<GarageKeyLockedFailure>(),
        );
        expect(storage.entries[mainnetEntry], entry);
      },
      timeout: slow,
    );

    test(
      'a keystore that refuses a change keeps the key when a delete fails, and stores no key when a write fails, and says so',
      () async {
        final entry = await storedEntry();
        await keystore(
          FakeSecureStoragePlatform(
            entries: {mainnetEntry: entry},
            scriptedWrites: [PlatformException(code: 'delete failed')],
          ),
        );
        final repository = repositoryOver(memory());
        expect(keyOf(await repository.read(mainnet)).key, drawnKey);
        expect(
          await repository.delete(mainnet),
          isErr<GarageKeyNotDeletedFailure>(),
        );
        expect(storage.entries[mainnetEntry], entry);

        await keystore(
          FakeSecureStoragePlatform(
            scriptedWrites: [PlatformException(code: 'write failed')],
          ),
        );
        final empty = repositoryOver(memory());
        expect(
          await empty.import(mainnet, drawnKey),
          isErr<GarageKeyNotSavedFailure>(),
        );
        expect(storage.entries, isNot(contains(mainnetEntry)));
      },
      timeout: slow,
    );

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
        const GarageKeyNoWalletFailure(),
        const GarageKeyPassphraseFailure(),
        const GarageKeyNoWordsFailure(),
        const GarageKeyMismatchFailure(),
        const GarageKeyLastIndexFailure(),
      ]) {
        expect(failure.logMessage, isNull);
        expect(failure.toString(), '${failure.runtimeType}');
      }
      // The number of an internal key is not a secret, and is all the failure carries.
      expect(const GarageKeyIsInternalFailure(3).logMessage, isNull);
    });
  });
}
