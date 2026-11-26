import 'dart:typed_data';

import 'package:p2p/src/data/garage_key_book_repository_impl.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_keyring.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, GarageKeys, Secrets;
import 'package:secrets/testing.dart';
import 'package:test/test.dart';

import 'support/garage_words.dart';
import 'support/make_harness.dart';
import 'support/robot_coordinators.dart' show pairOf;
import 'support/trade_harness.dart';

/// The trades over the real Garage Keys (#81; review of #292, C-wiring and the decisions of 2026-11-26): the real repository over the vault of `package:secrets` and the real derivation of the public test words, the real robot layer (`InterimTradeRobots`), the real records, with three distinct keys, the external Garage Key, internal key 0 and internal key 1. A make and a take take their robot from the key selected and no other; a trade in progress goes on with its own key whichever key is selected; a key imported trades as any other, and the coordinator's refusal of a robot it already knows still holds for it.
void main() {
  const testnet = RobosatsNetwork.testnet;
  const slow = Timeout(Duration(seconds: 180));

  // Fixed test bytes, 0x21 to 0x40: the external Garage Key of these tests, not a key anyone uses.
  final externalKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 0x21)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  GarageKeyFingerprint fingerprintOf(GarageKey key) =>
      switch (GarageKeyFingerprint.of(key)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  late GarageKeys vault;
  late TestWordsPort words;

  setUp(() {
    FakeSecureStoragePlatform().install();
    vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    words = TestWordsPort();
  });

  /// Internal Garage Key [index] of the public test words on testnet.
  Future<GarageKey> internalKey(int index) async =>
      switch (await words.garageKey(testnet, index: index)) {
        Ok(:final value) => switch (GarageKey.fromBytes(value.bytes)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        },
        Err(:final failure) => throw StateError('$failure'),
      };

  Future<void> storeExternal() async => expect(
    await vault.import(
      slot: GarageKeySlot.testnet,
      bytes: externalKey.revealBytes(),
    ),
    isA<Ok<Object?, Failure>>(),
  );

  late GarageKeyRepositoryImpl garage;
  GarageKeyRepositoryImpl garageOver(P2pDatabase database) =>
      garage = GarageKeyRepositoryImpl(
        vault,
        words,
        GarageKeyBookRepositoryImpl(
          database,
          clock: () => DateTime.utc(2026, 11, 26),
        ),
      );

  /// The keys of the Garage of testnet: internal keys 0 and 1 activated, [selected] selected; the external Garage Key in the vault.
  Future<void> keysWith(GarageKeySelection selected) async {
    expect(await garage.keyring(testnet), isA<Ok<GarageKeyring, P2pFailure>>());
    expect(await garage.activateNext(testnet, after: 0), isOk(1));
    expect(await garage.select(testnet, selected), isOk(null));
  }

  test('three distinct keys', () async {
    final keys = {
      fingerprintOf(externalKey),
      fingerprintOf(await internalKey(0)),
      fingerprintOf(await internalKey(1)),
    };
    expect(keys, hasLength(3));
  }, timeout: slow);

  test(
    'a take uses the key selected, internal key 1, never key 0 nor the external one; its trade goes on with its own key whichever key is selected then',
    () async {
      await storeExternal();
      final one = await internalKey(1);
      final app = await TradeHarness.start(key: one, garageOver: garageOver);
      await keysWith(const SelectedWordsKey(1));
      expect(await app.takeShown(), isA<Ok<TakeOutcome, TakeRefusal>>());
      final record = (await app.activeRecords()).single;
      expect(record.robot.keyFingerprint, fingerprintOf(one));
      // Another key selected: the trade is read with its own key's robot.
      for (final other in [
        const SelectedExternalKey(),
        const SelectedWordsKey(0),
      ]) {
        expect(await garage.select(testnet, other), isOk(null));
        expect(
          await app.robots.robotOfTrade(record),
          isA<Ok<NetworkRobot, P2pFailure>>().having(
            (ok) => ok.value.slot,
            'slot',
            record.robot,
          ),
          reason: '$other',
        );
        // The app started again reads the trade once, as its page does, with its own key's robot: one more read of the order at its coordinator.
        final again = app.restart();
        final reads = again.coordinator.received
            .where((kind) => kind == ScriptedRequest.order)
            .length;
        await again.watch.readOnce(record);
        await again.settle();
        expect(
          again.coordinator.received
              .where((kind) => kind == ScriptedRequest.order)
              .length,
          greaterThan(reads),
          reason: '$other',
        );
      }
    },
    timeout: slow,
  );

  test(
    'a make uses the key selected, internal key 1, never key 0 nor the external one',
    () async {
      await storeExternal();
      final one = await internalKey(1);
      final harness = await MakeHarness.start(key: one, garageOver: garageOver);
      await keysWith(const SelectedWordsKey(1));
      expect(await harness.makeOrder(), isA<Ok<MakeOutcome, MakeRefusal>>());
      final made = await harness.allTrades();
      expect(made, hasLength(1));
      expect(made.single['key_fingerprint'], fingerprintOf(one).hex);
      // Restarted with key 0 selected: the trade is still read with key 1's robot.
      expect(
        await garage.select(testnet, const SelectedWordsKey(0)),
        isOk(null),
      );
      final record = (await harness.restart().activeRecords()).single;
      expect(
        await harness.robots.robotOfTrade(record),
        isA<Ok<NetworkRobot, P2pFailure>>().having(
          (ok) => ok.value.slot,
          'slot',
          record.robot,
        ),
      );
    },
    timeout: slow,
  );

  test(
    'an imported key trades as any other (decided on 2026-11-26, #81): a take with it, selected',
    () async {
      final app = await TradeHarness.start(
        key: externalKey,
        garageOver: garageOver,
      );
      expect(
        await garage.keyring(testnet),
        isA<Ok<GarageKeyring, P2pFailure>>(),
      );
      expect(
        await ImportGarageKeyUsecase(
          garage,
          RobotBindingRepositoryImpl(app.database, clock: () => app.now),
        ).execute(testnet, text: externalKey.revealBech32()),
        isOk(null),
      );
      expect(keyOfNewTrade(await garage.forNewTrade(testnet)), externalKey);
      expect(await app.takeShown(), isA<Ok<TakeOutcome, TakeRefusal>>());
      expect(
        (await app.activeRecords()).single.robot.keyFingerprint,
        fingerprintOf(externalKey),
      );
    },
    timeout: slow,
  );

  test(
    'an imported key: a robot the coordinator already knows with another pair is refused, and the next make takes the next robot',
    () async {
      final harness = await MakeHarness.start(
        key: externalKey,
        garageOver: garageOver,
      );
      expect(
        await garage.keyring(testnet),
        isA<Ok<GarageKeyring, P2pFailure>>(),
      );
      expect(
        await ImportGarageKeyUsecase(
          garage,
          RobotBindingRepositoryImpl(
            harness.database,
            clock: () => harness.now,
          ),
        ).execute(testnet, text: externalKey.revealBech32()),
        isOk(null),
      );
      final robots = TradeHarness.robotsOf(testnet, externalKey);
      final first = robots.first;
      final pair = pairOf(first);
      harness.coordinator.existsWithPair(
        first,
        publicKey: pair.publicKey.armored,
        encryptedPrivateKey: pair.encryptedPrivateKeyArmored,
        nostrPublicKey: first.nostrKeyPair().publicKeyHex,
      );
      expect(
        await harness.makeOrder(),
        isA<Err<MakeOutcome, MakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<MakeRobotRefused>().having(
            (r) => r.failure,
            'failure',
            isA<RobotNotForNewTradeFailure>(),
          ),
        ),
      );
      expect(await harness.allTrades(), isEmpty);
      // The robot refused stays bound to that coordinator: the next make takes the next one.
      expect(await harness.makeOrder(), isA<Ok<MakeOutcome, MakeRefusal>>());
      final made = (await harness.activeRecords()).single;
      expect(made.robot.keyFingerprint, fingerprintOf(externalKey));
      final bound = await harness.database
          .customSelect(
            'SELECT robot_index FROM robot_bindings ORDER BY robot_index',
          )
          .get();
      expect(bound, hasLength(2));
      expect(made.robot.accountIndex, bound.last.read<int>('robot_index'));
    },
    timeout: slow,
  );
}

/// The key of a new trade.
GarageKey keyOfNewTrade(Result<NetworkGarageKey, P2pFailure> result) =>
    switch (result) {
      Ok(:final value) => value.key,
      Err(:final failure) => throw StateError('$failure'),
    };
