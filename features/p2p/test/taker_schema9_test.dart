import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart' show FakeP2pWalletPort;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// Schema 9 for a taker buyer (#204, #231; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis), over the real records, use cases and state machine, the coordinator played by `ScriptedCoordinator` (never a real one): an on-chain address this wallet gave, traced « from this wallet »; and the trace of terms a taker's coordinator showed otherwise, then put back (functional review of schema 9, C5, m14 and m20).
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// BIP-173's own test vector, which no wallet of the project holds.
  const testnetAddress = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';

  /// The status the watch of [record] read once, on [app].
  Future<TradeSeen> read(TradeHarness app, TradeRecord record) async {
    final run = app.watchOf(record);
    await app.settle();
    final status = run.lastStatus;
    await run.subscription.cancel();
    return status.seen;
  }

  /// A sell order taken on a fresh run (this robot the buyer), its bond locked: the status at 6 as a read stored it.
  Future<(TradeHarness, TradeRecord, TradeSeen)> atSix({
    bool swap = false,
  }) async {
    final app = await TradeHarness.start();
    app.coordinator.swapAllowed = swap;
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    await app.elapse(const Duration(seconds: 5));
    final status = run.lastStatus;
    await run.subscription.cancel();
    expect(status.stored, isTrue);
    expect(status.seen.status, isA<WaitingForBoth>());
    return (app, status.record, status.seen);
  }

  for (final (name, fromWallet) in [
    ('given by this wallet: « from this wallet »', true),
    ('pasted: « pasted »', false),
  ]) {
    test(
      'a taker buyer\'s on-chain address $name, after a restart too (m14)',
      () async {
        final (app, record, seen) = await atSix(swap: true);
        if (fromWallet) {
          final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
            ..scriptAddress(const Ok(P2pWalletAddress(testnetAddress)));
          final given = valueOf(
            await PayoutFromWalletUsecase(
              wallet,
              given: app.walletPayouts,
            ).address(record),
          );
          expect(given.address, testnetAddress);
        }
        final rate = MiningFeeRate.of(3.5) ?? (throw StateError('no rate'));
        final checked = valueOf(
          app.payout.check(
            record,
            seen,
            PayoutAddressText(testnetAddress, rate: rate),
          ),
        );
        expect(
          valueOf(await app.payout.execute(record, checked)),
          isA<PayoutGiven>(),
        );
        final expected = fromWallet
            ? PayoutFromThisWallet(PayoutTraceKind.address, app.now)
            : PayoutPasted(PayoutTraceKind.address, app.now);
        expect(valueOf(await app.payouts.traceOf(record, take: 0)), expected);
        final reopened = switch (await app.restart().reader.open(record)) {
          TradeOpened(:final trade) => trade.seen,
          final other => throw StateError('$other'),
        };
        expect(reopened.payout, expected);
      },
    );
  }

  test(
    'a taker\'s coordinator that showed the order with other terms (priced in sats), then put them back: the trail keeps when, no premium, after a restart too (m20)',
    () async {
      final (app, record, _) = await atSix();
      await app.elapse(const Duration(minutes: 1));
      final shownAt = app.now;
      app.coordinator.explicitSatoshis = 106900;
      final changed = await read(app, record);
      expect(changed.status.has<TradeTermsChanged>(), isTrue);
      expect(changed.status.trail.termsChangedAt, shownAt);
      expect(changed.status.trail.termsChangedPremium, isNull);
      await app.elapse(const Duration(minutes: 1));
      app.coordinator.explicitSatoshis = null;
      final back = await read(app, record);
      expect(back.status.has<TradeTermsChanged>(), isFalse);
      expect(back.status.trail.termsChangedAt, shownAt);
      final reopened = switch (await app.restart().reader.open(record)) {
        TradeOpened(:final trade) => trade.seen,
        final other => throw StateError('$other'),
      };
      expect(reopened.status.trail.termsChangedAt, shownAt);
    },
  );
}
