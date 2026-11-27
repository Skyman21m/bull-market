import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/testing.dart' show ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/garage_words.dart';
import 'support/trade_harness.dart';

/// A take by a robot of a key of the wallet's words (#81, design note `docs/design/garage-key-from-the-words.md` § 3): the key is recorded as drawn here by its activation, so its robots may trade, and the one guard against a robot another device or the official client already used stays the check at the coordinator of the new trade, which is not weakened for such a key.
void main() {
  // Key 0 of the public test phrase « abandon ×11 about » on testnet, the design note's vector.
  final words = switch (GarageKey.parse(abandonTestnet0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  int takes(TradeHarness app) => app.coordinator.received
      .where((kind) => kind == ScriptedRequest.take)
      .length;

  test('a robot of a key of the words takes an order', () async {
    final app = await TradeHarness.start(key: words, activatedFromWords: true);
    expect(await app.takeShown(), isA<Ok<TakeOutcome, TakeRefusal>>());
    expect(takes(app), 1);
  });

  test(
    'a robot of a key of the words that the coordinator already knew with an order is not used',
    () async {
      for (final fields in [
        {'active_order_id': 7},
        {'last_order_id': 7},
      ]) {
        final app = await TradeHarness.start(
          key: words,
          activatedFromWords: true,
        );
        app.coordinator.robotAnswerHas(app.robot(0), fields);
        expect(
          await app.takeShown(),
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeRobotRefused>().having(
              (r) => r.failure,
              'failure',
              isA<RobotNotForNewTradeFailure>(),
            ),
          ),
          reason: '$fields',
        );
        expect(takes(app), 0, reason: '$fields');
      }
    },
  );
}
