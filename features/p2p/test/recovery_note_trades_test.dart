import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart';

/// The recovery note told only of the makes and takes the coordinator confirmed (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « This design »), and its floor applied to the robot of a take and of a make, through the real use cases, records and robot layer of the trade harnesses, the coordinator scripted.
void main() {
  test('a take the coordinator confirmed tells the notes once, with its record', () async {
    final confirmed = <TradeRecord>[];
    final app = await TradeHarness.start(
      notes: (confirmed: confirmed.add, beforeNewTrade: (_) async {}),
    );
    final taken = TradeHarness.recordOf(await app.takeShown());
    expect(confirmed.map((record) => record.robot), [taken.robot]);
    expect(confirmed.single.confirmedAt, isNotNull);
  });

  test(
    'a take the coordinator did not make tells the notes nothing, though its pending take was recorded',
    () async {
      final confirmed = <TradeRecord>[];
      final app = await TradeHarness.start(
        notes: (confirmed: confirmed.add, beforeNewTrade: (_) async {}),
      );
      app.coordinator.takesNotMade = true;
      await app.takeShown();
      expect(
        app.coordinator.received.where((kind) => kind == ScriptedRequest.take),
        hasLength(1),
      );
      expect(confirmed, isEmpty);
    },
  );

  test('a make the coordinator confirmed tells the notes once', () async {
    final confirmed = <TradeRecord>[];
    final app = await MakeHarness.start(
      notes: (confirmed: confirmed.add, beforeNewTrade: (_) async {}),
    );
    final made = await app.makeOrder();
    expect(made, isA<Ok>());
    expect(confirmed, hasLength(1));
    expect(confirmed.single.origin, TradeOrigin.madeHere);
  });

  test(
    'the robot of a take is above the floor the note gave, the reading awaited before the reservation',
    () async {
      final awaited = <NetworkGarageKey>[];
      late TradeHarness app;
      app = await TradeHarness.start(
        notes: (
          confirmed: (_) {},
          beforeNewTrade: (key) async {
            awaited.add(key);
            // The note read: robot 4 served elsewhere.
            await app.database.customStatement(
              'INSERT OR IGNORE INTO garage_recovery_notes (network, key_fingerprint, account_floor, read_at) VALUES (?, ?, 4, 0)',
              [
                'testnet',
                switch (key.fingerprint) {
                  Ok(:final value) => value.hex,
                  Err(:final failure) => throw StateError('$failure'),
                },
              ],
            );
          },
        ),
      );
      final taken = TradeHarness.recordOf(await app.takeShown());
      expect(awaited, isNotEmpty);
      expect(taken.robot.accountIndex, 5);
    },
  );

  test('the robot of a make is above the floor the note gave', () async {
    late MakeHarness app;
    app = await MakeHarness.start(
      notes: (
        confirmed: (_) {},
        beforeNewTrade: (key) => app.database.customStatement(
          'INSERT OR IGNORE INTO garage_recovery_notes (network, key_fingerprint, account_floor, read_at) VALUES (?, ?, 2, 0)',
          [
            'testnet',
            switch (key.fingerprint) {
              Ok(:final value) => value.hex,
              Err(:final failure) => throw StateError('$failure'),
            },
          ],
        ),
      ),
    );
    expect(await app.makeOrder(), isA<Ok>());
    final pending = await app.activeRecords();
    expect(pending.single.robot.accountIndex, 3);
  });
}
