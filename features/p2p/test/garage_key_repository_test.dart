import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
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
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, GarageKeys, Secrets;
import 'package:secrets/testing.dart';

import 'migrations_test/p2p_database/generated/schema_v9.dart' as v9;
import 'support/garage_words.dart';

/// The Garage Keys of P2P since #81 (design note `docs/design/garage-key-from-the-words.md`), through the real repository, the real vault of `package:secrets` over its in-memory keystore, the real derivation of the public test words and the real database: key 0 at the first opening, « New key », the keys checked against their fingerprints, the refusals that never draw a key, and the book of the key drawn at random emptied once, never while a trade of it is in progress, and never again.
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

  Future<List<String>> statesOf(P2pDatabase database) async => [
    for (final row
        in await database.customSelect('SELECT state FROM garage_switch').get())
      row.read<String>('state'),
  ];

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
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(DerivedGarageKeyring(0)),
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
        expect(await statesOf(database), ['derived']);
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
        expect(
          await repository.activateNext(mainnet, after: 0),
          const Ok<int, P2pFailure>(1),
        );
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
          const Err<int, P2pFailure>(GarageKeyMissingFailure()),
        );
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(DerivedGarageKeyring(1)),
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
          const Err<NetworkGarageKey, P2pFailure>(GarageKeyMissingFailure()),
        );
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(DerivedGarageKeyring(2)),
        );
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
        const Err<int, P2pFailure>(GarageKeyLastIndexFailure()),
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
          expect(
            result,
            const Err<NetworkGarageKey, P2pFailure>(GarageKeyMismatchFailure()),
          );
        }
        expect(
          await repository.activateNext(mainnet, after: 0),
          isA<Err<int, P2pFailure>>(),
        );
      },
      timeout: slow,
    );

    test(
      'the robot of a recorded trade finds its key by fingerprint',
      () async {
        final repository = repositoryOver(memory());
        final first = keyOf(await repository.read(mainnet));
        expect(
          await repository.activateNext(mainnet, after: 0),
          const Ok<int, P2pFailure>(1),
        );
        final robot = switch (first.firstUsableRobot(3)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final found = keyOf(await repository.ofSlot(robot.slot));
        expect(found.index, 0);
        expect(found.key.revealBech32(), abandonMainnet0);
        expect(
          await repository.ofSlot(RobotSlot(mainnet, drawnFingerprint, 0)),
          const Err<NetworkGarageKey, P2pFailure>(TradeKeyMissingFailure()),
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
            Err<GarageKeyring, P2pFailure>(failure),
            reason: reason.name,
          );
          expect(
            await repository.forNewTrade(mainnet),
            Err<NetworkGarageKey, P2pFailure>(failure),
            reason: reason.name,
          );
          expect(await countOf(database, 'derived_garage_keys'), 0);
          expect(await countOf(database, 'garage_key_histories'), 0);
          expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        }
      },
    );

    test(
      'a book created at schema 10 leaves the vault slots as they are',
      () async {
        expect(
          await vault.import(
            slot: GarageKeySlot.mainnet,
            bytes: drawnKey.revealBytes(),
          ),
          isA<Ok<Object?, Failure>>(),
        );
        final repository = repositoryOver(memory());
        expect(
          keyOf(await repository.read(mainnet)).key.revealBech32(),
          abandonMainnet0,
        );
        expect(storage.entries.keys, contains(mainnetEntry));
      },
      timeout: slow,
    );
  });

  group('the book of the key drawn at random, emptied once', () {
    /// A file of schema 9 with a key drawn here, a robot of it bound and its trade, open unless [closed].
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
      'nothing is emptied while a trade is in progress: the earlier key only finishes it',
      () async {
        await storeDrawnKey();
        final file = await schema9File(closed: false);
        final database = open(file);
        final repository = repositoryOver(database);
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(LegacyGarageKeyring()),
        );
        final legacy = keyOf(await repository.read(mainnet));
        expect(legacy.index, isNull);
        expect(legacy.key, drawnKey);
        expect(
          keyOf(
            await repository.ofSlot(RobotSlot(mainnet, drawnFingerprint, 0)),
          ).key,
          drawnKey,
        );
        // No new trade, on that key or any other, and no key of the words yet.
        expect(
          await repository.forNewTrade(mainnet),
          const Err<NetworkGarageKey, P2pFailure>(
            GarageKeySwitchPendingFailure(),
          ),
        );
        expect(
          await repository.activateNext(mainnet, after: 0),
          const Err<int, P2pFailure>(GarageKeySwitchPendingFailure()),
        );
        expect(
          await repository.derived(mainnet, 0),
          const Err<NetworkGarageKey, P2pFailure>(
            GarageKeySwitchPendingFailure(),
          ),
        );
        expect(await statesOf(database), ['legacy']);
        expect(await countOf(database, 'trades'), 1);
        expect(await countOf(database, 'robot_bindings'), 1);
        expect(await countOf(database, 'derived_garage_keys'), 0);
        expect(storage.entries.keys, contains(mainnetEntry));
        expect(words.asked, isEmpty);
      },
      timeout: slow,
    );

    test(
      'the first start where every trade is finished empties the book, then the vault, then switches',
      () async {
        await storeDrawnKey();
        final file = await schema9File(closed: false);
        final first = P2pDatabase.forTesting(NativeDatabase(file));
        expect(await statesOf(first), ['legacy']);
        // The trade ends during the run: the switch waits for the next start.
        await first.customStatement('UPDATE trades SET closed_at = 9');
        expect(await statesOf(first), ['legacy']);
        await first.close();
        final database = open(file);
        expect(await statesOf(database), ['vaultPending']);
        for (final table in [
          'trades',
          'robot_bindings',
          'garage_key_histories',
          'trade_trails',
          'trade_terms',
          'trade_payments',
          'trade_payouts',
          'trade_chat_pins',
          'trade_chat_nostr_pins',
          'maker_terms',
        ]) {
          expect(await countOf(database, table), 0, reason: table);
        }
        // The triggers that refuse a delete are back.
        final triggers = [
          for (final row
              in await database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'trigger'",
                  )
                  .get())
            row.read<String>('name'),
        ];
        expect(
          triggers,
          containsAll([
            'trades_never_deleted',
            'trade_trails_never_deleted',
            'trade_payouts_never_deleted',
          ]),
        );
        expect(storage.entries.keys, contains(mainnetEntry));
        final repository = repositoryOver(database);
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(DerivedGarageKeyring(0)),
        );
        expect(storage.entries.keys, isNot(contains(mainnetEntry)));
        expect(await statesOf(database), ['derived']);
        expect(
          keyOf(await repository.forNewTrade(mainnet)).key.revealBech32(),
          abandonMainnet0,
        );
      },
      timeout: slow,
    );

    test(
      'an emptying cut at any point resumes at the next opening, never half done',
      () async {
        await storeDrawnKey();
        final killed = File('${directory.path}/killed.sqlite');
        await _killedMidEmptying(killed, drawnFingerprint.hex);
        final database = open(killed);
        expect(await statesOf(database), ['vaultPending']);
        expect(await countOf(database, 'trades'), 0);
        expect(await countOf(database, 'robot_bindings'), 0);
        expect(await countOf(database, 'garage_key_histories'), 0);
        final triggers = [
          for (final row
              in await database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = 'trades_never_deleted'",
                  )
                  .get())
            row.read<String>('name'),
        ];
        expect(triggers, ['trades_never_deleted']);
        // Killed again between the database and the vault: the slot is still there, and the next reading of the keys deletes it before any key of the words.
        expect(storage.entries.keys, contains(mainnetEntry));
        final repository = repositoryOver(database);
        expect(
          await repository.keyring(mainnet),
          const Ok<GarageKeyring, P2pFailure>(DerivedGarageKeyring(0)),
        );
        expect(storage.entries.keys, isNot(contains(mainnetEntry)));
      },
      timeout: slow,
    );

    test(
      'the book of the keys of the words is never emptied again, and the switch never goes back',
      () async {
        final file = File('${directory.path}/ten.sqlite');
        final database = P2pDatabase.forTesting(NativeDatabase(file));
        final repository = repositoryOver(database);
        final key = keyOf(await repository.read(mainnet));
        final robot = switch (key.firstUsableRobot(0)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(
          await RobotBindingRepositoryImpl(database, clock: () => now).bind(
            robot.slot,
            CoordinatorIdentity(
              network: mainnet,
              alias: 'temple',
              onion: 'http://temple.onion',
              nodeKeys: const [],
              nostrKey: 'abc',
            ),
          ),
          const Ok<void, P2pFailure>(null),
        );
        await database.close();
        final again = open(file);
        expect(await statesOf(again), ['derived']);
        expect(await countOf(again, 'robot_bindings'), 1);
        expect(await countOf(again, 'derived_garage_keys'), 1);
        for (final state in ['legacy', 'emptying', 'vaultPending']) {
          await expectLater(
            again.customStatement("UPDATE garage_switch SET state = '$state'"),
            throwsA(anything),
            reason: state,
          );
        }
        await expectLater(
          again.customStatement('DELETE FROM garage_switch'),
          throwsA(anything),
        );
        await again.customStatement(
          "INSERT OR REPLACE INTO garage_switch (id, state) VALUES (1, 'legacy')",
        );
        expect(await statesOf(again), ['derived']);
      },
      timeout: slow,
    );
  });
}

/// A file left by a run killed in the middle of the emptying: at schema 10, the switch at `emptying`, `trades_never_deleted` dropped, the bindings deleted, the history and the closed trade still there.
Future<void> _killedMidEmptying(File file, String fingerprint) async {
  final old = v9.DatabaseAtV9(NativeDatabase(file));
  for (final statement in [
    "INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES ('mainnet', '$fingerprint', 'generated', 1)",
    "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('mainnet', '$fingerprint', 0, 'temple', 'http://temple.onion', '', 'abc', 2, 'generated')",
    "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('mainnet', '$fingerprint', 0, 'temple', 'http://temple.onion', 42, 'buyer', 'takenHere', 3, 4, NULL)",
  ]) {
    await old.customStatement(statement);
  }
  await old.close();
  // Upgraded with the trade open: `legacy`, whole.
  final upgraded = P2pDatabase.forTesting(NativeDatabase(file));
  expect(
    (await upgraded.customSelect('SELECT state FROM garage_switch').getSingle())
        .read<String>('state'),
    'legacy',
  );
  // The trade closed, then a run that started the emptying and was killed in the middle of it.
  await upgraded.customStatement('UPDATE trades SET closed_at = 9');
  await upgraded.customStatement(
    "UPDATE garage_switch SET state = 'emptying' WHERE state = 'legacy'",
  );
  await upgraded.customStatement('DROP TRIGGER trades_never_deleted');
  await upgraded.customStatement('PRAGMA foreign_keys = OFF');
  await upgraded.customStatement('DELETE FROM robot_bindings');
  await upgraded.close();
}
