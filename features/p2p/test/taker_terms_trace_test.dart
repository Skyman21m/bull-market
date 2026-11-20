import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';

import 'support/trade_orders.dart';

/// The trace of terms shown otherwise for a taker (schema 9, #231; security review of schema 9, C1; security verification, R8): the state machine over the reference's own answers (`orderJson`, never a real coordinator), a taker buyer and a taker seller at 6 shown other premiums, each put back: the first time, the lowest and the highest premium shown otherwise than the order's own (2 %), a premium in between moving neither, and the time of another term first.
void main() {
  late TradeTerms<TakenSide> buyer;
  late TradeTerms<TakenSide> seller;
  late Bolt11TestDecoder decoder;
  late Bolt11Reader reader;

  setUpAll(() async {
    buyer = await tradeTerms();
    seller = await tradeTerms(role: TradeRole.seller);
  });

  setUp(() {
    decoder = Bolt11TestDecoder();
    reader = Bolt11Reader(decoder);
  });

  /// The taker's status at 6 as [role] read at [at], from [previous], the order's answer changed by [changes].
  Future<TradeStatus> at6(
    TradeRole role,
    TradeStatus previous,
    DateTime at, [
    Map<String, Object?> changes = const {},
  ]) async {
    final escrow = escrowInvoice();
    if (role == TradeRole.seller) decoder.add(escrow);
    final TradeAnswer answer = await readAnswer(
      orderJson(
        6,
        role: role,
        escrow: role == TradeRole.seller ? escrow : null,
        changes: changes,
      ),
    );
    return TradeStatus.from(
      previous: previous,
      answer: answer,
      terms: role == TradeRole.buyer ? buyer : seller,
      now: at,
      reader: reader,
    );
  }

  Future<TradeStatus> preTake(TradeRole role) async {
    final invoice = bondInvoice();
    decoder.add(invoice);
    return TradeStatus.afterTake(
      await takeStarted(orderJson(3, role: role, bond: invoice)),
      terms: role == TradeRole.buyer ? buyer : seller,
      now: tradeNow,
      reader: reader,
    );
  }

  /// A taker at 6 as [role], and a way to show it [changes] a minute later each time.
  Future<
    (
      TradeStatus Function(),
      Future<TradeStatus> Function([Map<String, Object?>]),
    )
  >
  start(TradeRole role) async {
    var status = await at6(role, await preTake(role), tradeNow);
    expect(status.trail.termsChangedAt, isNull);
    var at = tradeNow;
    Future<TradeStatus> show([Map<String, Object?> changes = const {}]) async {
      at = at.add(const Duration(minutes: 1));
      return status = await at6(role, status, at, changes);
    }

    return (() => status, show);
  }

  for (final role in [TradeRole.buyer, TradeRole.seller]) {
    test(
      'a taker ${role.name} at 6 shown -10 then +7 for the order\'s +2, each put back: both kept, the first time, a premium in between moves nothing',
      () async {
        final (status, show) = await start(role);
        await show({'premium': '-10.00'});
        final shownAt = tradeNow.add(const Duration(minutes: 1));
        expect(status().has<TradeTermsChanged>(), isTrue);
        expect(status().trail.termsChangedAt, shownAt);
        expect(status().trail.termsChangedPremiumLow, -10);
        expect(status().trail.termsChangedPremiumHigh, -10);
        await show();
        await show({'premium': '7.00'});
        expect(status().trail.termsChangedPremiumLow, -10);
        expect(status().trail.termsChangedPremiumHigh, 7);
        await show();
        await show({'premium': '1.00'});
        expect(status().trail.termsChangedPremiumLow, -10);
        expect(status().trail.termsChangedPremiumHigh, 7);
        await show();
        expect(status().has<TradeTermsChanged>(), isFalse);
        expect(status().trail.termsChangedAt, shownAt);
        // As stored and read back: the record the trigger takes.
        final record = status().trail.record;
        expect(record.termsChangedAtMicros, shownAt.microsecondsSinceEpoch);
        expect(record.termsChangedPremiumLow, -10);
        expect(record.termsChangedPremiumHigh, 7);
      },
    );
  }

  test(
    '+7 then -3, each put back: both kept; a premium closer than the tolerance writes nothing',
    () async {
      final (status, show) = await start(TradeRole.buyer);
      await show({'premium': '2.004'});
      expect(status().trail.termsChangedAt, isNull);
      await show({'premium': '7.00'});
      await show();
      await show({'premium': '-3.00'});
      await show();
      expect(status().trail.termsChangedPremiumLow, -3);
      expect(status().trail.termsChangedPremiumHigh, 7);
    },
  );

  test(
    'another term first (the bond size), then a premium: the time of the first, the premium written then',
    () async {
      final (status, show) = await start(TradeRole.buyer);
      await show({'bond_size': '4.00'});
      final first = tradeNow.add(const Duration(minutes: 1));
      expect(status().trail.termsChangedAt, first);
      expect(status().trail.termsChangedPremiumLow, isNull);
      expect(status().trail.termsChangedPremiumHigh, isNull);
      await show();
      await show({'premium': '9.50'});
      await show();
      expect(status().trail.termsChangedAt, first);
      expect(status().trail.termsChangedPremiumLow, 9.5);
      expect(status().trail.termsChangedPremiumHigh, 9.5);
    },
  );
}
