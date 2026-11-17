import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The wallet's invoice of a maker buyer's payout, keyed by trade and contract (#179, design note `docs/design/phase-3-making-an-order.md` § 3.4): the key of contract 0 is the one every trade had before, a next contract's has its number, so that the invoice of an earlier contract, of another amount, is never given again.
void main() {
  Future<TradeSeen> read(MakeHarness harness, TradeRecord record) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return seen;
  }

  PayoutAsk askOf(TradeRecord record, TradeSeen seen) =>
      switch (PayoutAsk.of(record, seen)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  test(
    'contract 0 keeps the trade\'s key, a next contract, whether the order was seen back in the book or not, appends its number',
    () async {
      final harness = await MakeHarness.start();
      final made = switch (await harness.makeOrder()) {
        Ok(value: final MakeStarted started) => started,
        final other => fail('$other'),
      };
      final record = made.record;
      harness.coordinator
        ..lockMakerBond(42)
        ..take(42, harness.robot(5));
      final first = await read(harness, record);
      expect(first.status, isA<WaitingForBoth>());
      expect(first.status.trail.take, 0);
      expect(
        PayoutFromWalletUsecase.payoutKey(askOf(record, first)),
        'testnet:temple:42',
      );

      // The taker lets its step run out: the order back in the book, and taken again an hour later, while the app read nothing.
      await harness.elapse(const Duration(hours: 1));
      harness.coordinator
        ..backToBook(42)
        ..take(42, harness.robot(4));
      final next = await read(harness, record);
      expect(next.status, isA<WaitingForBoth>());
      expect(next.status.trail.take, 1);
      expect(
        PayoutFromWalletUsecase.payoutKey(askOf(record, next)),
        'testnet:temple:42:1',
      );
    },
  );
}
