import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// An order made here followed by its watch through the panels of #182, over the real records, use cases and state machine, the coordinator played by `ScriptedMakerCoordinator` (never a real one): made, its bond locked from another wallet, public, taken, back in the book, taken again by another robot (a next contract, with a payout invoice of its own), the app killed and opened again at each point; what each read gives the screen is the view of `TradeView.of`.
///
/// The steps from 8 on are a taker's buyer steps of phase 2, whose coordinator the maker's script does not play: they are drawn from the reference's answers in `maker_panels_test.dart`.
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// The view the trade screen draws after the watch of [record] read the order once, on [harness].
  Future<(TradeContract, TradeSeen)> read(
    MakeHarness harness,
    TradeRecord record,
  ) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final watch = run.lastStatus;
    await run.subscription.cancel();
    final view = TradeView.of(watch);
    if (view is! TradeContract) throw StateError('$view');
    return (view, watch.seen);
  }

  test(
    'made, its bond locked elsewhere, public, taken, back in the book, taken again: each panel, each contract\'s own payout key, after a restart too',
    () async {
      var harness = await MakeHarness.start();
      final made = valueOf(await harness.makeOrder());
      final record = (made as MakeStarted).record;
      expect(record.origin, TradeOrigin.madeHere);

      var (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.lockBondToPublish);
      expect(view.step, (1, 5));
      expect(view.cancel, TradeCancelOffer.free);

      // The bond paid from another wallet: the coordinator publishes the order.
      harness.coordinator.lockMakerBond(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<MakerOrderPublic>());
      expect(view.title, TradeTitle.orderPublic);
      expect(view.prompt, TradePrompt.publicWait);
      expect(view.step, (2, 5));
      expect(view.bondLine, TradeBondLine.locked);
      expect(view.cancel, TradeCancelOffer.immediate);
      expect(view.maker, isTrue);

      // The app killed and opened again: the same panel from the stored trail.
      harness = harness.restart();
      (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.orderPublic);

      // Taken by a seller.
      harness.coordinator.take(record.orderId, harness.robot(7));
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<WaitingForBoth>());
      expect(view.title, TradeTitle.payout);
      expect(view.step, (3, 5));
      expect(view.cancel, TradeCancelOffer.losesBond);
      expect((seen.status as WaitingForBoth).rateGap, isNotNull);
      final firstKey = PayoutFromWalletUsecase.payoutKey(
        valueOf(PayoutAsk.of(record, seen)),
      );
      expect(seen.status.trail.take, 0);

      // The taker did not act: the order back in the book, its bond still locked.
      harness.coordinator.backToBook(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<MakerOrderPublic>());
      expect((seen.status as MakerOrderPublic).backInBook, isTrue);
      expect(view.title, TradeTitle.orderPublic);
      expect(view.bondLine, TradeBondLine.locked);

      // Taken again later, while the app is closed, by another robot: a next contract, its own payout invoice.
      await harness.elapse(const Duration(minutes: 10));
      harness = harness.restart();
      harness.coordinator.take(record.orderId, harness.robot(8));
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<WaitingForBoth>());
      expect(seen.status.trail.take, 1);
      expect(seen.status.warnings, isEmpty);
      expect(view.title, TradeTitle.payout);
      final nextKey = PayoutFromWalletUsecase.payoutKey(
        valueOf(PayoutAsk.of(record, seen)),
      );
      expect(nextKey, isNot(firstKey));
      expect(nextKey, '$firstKey:1');

      // Opened again: the contract kept.
      harness = harness.restart();
      (view, seen) = await read(harness, record);
      expect(seen.status.trail.take, 1);
    },
  );

  test(
    'expired at 1 untaken: « The order has expired », no step, no cancel',
    () async {
      final harness = await MakeHarness.start();
      final record =
          (valueOf(await harness.makeOrder()) as MakeStarted).record;
      harness.coordinator
        ..lockMakerBond(record.orderId)
        ..expire(record.orderId);
      final (view, seen) = await read(harness, record);
      expect(seen.status, isA<Expired>());
      expect(view.title, TradeTitle.expired);
      expect(view.step, isNull);
      expect(view.cancel, TradeCancelOffer.none);
    },
  );
}
