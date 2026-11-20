import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';

import 'support/trade_orders.dart';

/// The trace of terms shown otherwise for a taker (schema 9, #231; security review of schema 9, C1; functional review, V2): the state machine over the reference's own answers (`orderJson`, never a real coordinator), a taker buyer at 6 shown other premiums, each put back: the first time and the premium farthest from the order's own (2 %), above or below, never a closer one, and the time of another term first.
void main() {
  late TradeTerms<TakenSide> buyer;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUpAll(() async {
    buyer = await tradeTerms();
  });

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

  /// The taker's status at 6 read at [at], from [previous], the order's answer changed by [changes].
  Future<TradeStatus> at6(
    TradeStatus previous,
    DateTime at, [
    Map<String, Object?> changes = const {},
  ]) async {
    final TradeAnswer answer = await readAnswer(
      orderJson(6, changes: changes),
    );
    return TradeStatus.from(
      previous: previous,
      answer: answer,
      terms: buyer,
      now: at,
      reader: reader,
    );
  }

  Future<TradeStatus> preTake() async {
    final invoice = bondInvoice();
    decoder.add(invoice);
    return TradeStatus.afterTake(
      await takeStarted(orderJson(3, bond: invoice)),
      terms: buyer,
      now: tradeNow,
      reader: reader,
    );
  }

  test(
    'premiums shown otherwise at 6, each put back: the first time, the farthest premium, above or below, never a closer one',
    () async {
      var status = await at6(await preTake(), tradeNow);
      expect(status.trail.termsChangedAt, isNull);
      var at = tradeNow;
      Future<TradeStatus> show([Map<String, Object?> changes = const {}]) async {
        at = at.add(const Duration(minutes: 1));
        return status = await at6(status, at, changes);
      }

      await show({'premium': '2.01'});
      final shownAt = at;
      expect(status.has<TradeTermsChanged>(), isTrue);
      expect(status.trail.termsChangedAt, shownAt);
      expect(status.trail.termsChangedPremium, 2.01);
      await show();
      await show({'premium': '7.00'});
      expect(status.trail.termsChangedPremium, 7);
      await show();
      expect(status.has<TradeTermsChanged>(), isFalse);
      expect(status.trail.termsChangedPremium, 7);
      await show({'premium': '3.00'});
      expect(status.trail.termsChangedPremium, 7);
      await show({'premium': '-6.00'});
      expect(status.trail.termsChangedPremium, -6);
      await show();
      expect(status.trail.termsChangedAt, shownAt);
      expect(status.trail.termsChangedPremium, -6);
      // As stored and read back: the record the trigger takes.
      expect(status.trail.record.termsChangedPremium, -6);
      expect(status.trail.record.termsChangedAtMicros, shownAt.microsecondsSinceEpoch);
    },
  );

  test(
    'another term first (the bond size), then a premium: the time of the first, the premium written then',
    () async {
      var status = await at6(await preTake(), tradeNow);
      final first = tradeNow.add(const Duration(minutes: 1));
      status = await at6(status, first, {'bond_size': '4.00'});
      expect(status.trail.termsChangedAt, first);
      expect(status.trail.termsChangedPremium, isNull);
      status = await at6(status, first.add(const Duration(minutes: 1)));
      status = await at6(status, first.add(const Duration(minutes: 2)), {
        'premium': '9.50',
      });
      status = await at6(status, first.add(const Duration(minutes: 3)));
      expect(status.trail.termsChangedAt, first);
      expect(status.trail.termsChangedPremium, 9.5);
    },
  );
}
