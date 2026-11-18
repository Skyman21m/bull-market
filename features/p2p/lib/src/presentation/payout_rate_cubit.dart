import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade/wallet_rate_check.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/check_payout_rate_usecase.dart';

/// [CheckPayoutRateUsecase.execute], which the locator gives the cubit.
typedef PayoutRateChecker =
    Future<PayoutRateFinding?> Function(TradeRecord record, TradeSeen seen);

/// Which buyer's step a check is for: the payout (6 and 8) or « fiat sent » (9), of a contract ([take]).
@immutable
final class PayoutRateStep {
  final int take;
  final bool fiatSent;

  const PayoutRateStep(this.take, {required this.fiatSent});

  /// The step of [status], `null` where the rule says nothing.
  static PayoutRateStep? of(TradeStatus status) => switch (status) {
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(
      role: TradeRole.buyer,
    ) => PayoutRateStep(status.trail.take, fiatSent: false),
    Chatting(role: TradeRole.buyer, fiatSent: false) => PayoutRateStep(
      status.trail.take,
      fiatSent: true,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PayoutRateStep &&
      other.take == take &&
      other.fiatSent == fiatSent;

  @override
  int get hashCode => Object.hash(take, fiatSent);
}

/// Where the check of the step shown stands.
@immutable
sealed class PayoutRateState {
  const PayoutRateState();
}

/// Nothing to show: no step of the rule, or nothing to compare.
final class PayoutRateNone extends PayoutRateState {
  const PayoutRateNone();
}

/// The Bull wallet's price is being read for [step].
final class PayoutRateReading extends PayoutRateState {
  final PayoutRateStep step;

  const PayoutRateReading(this.step);
}

/// The check of [step].
final class PayoutRateChecked extends PayoutRateState {
  final PayoutRateStep step;
  final WalletRateCheck check;

  const PayoutRateChecked(this.step, this.check);
}

/// The read of [step] gives no sats the buyer receives: nothing compared, « rate not checked » said rather than nothing.
final class PayoutRateSatsMissing extends PayoutRateState {
  final PayoutRateStep step;

  const PayoutRateSatsMissing(this.step);
}

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3), on the trade screen: the only caller of [CheckPayoutRateUsecase], for an order made here whose user buys only (a taker's trade never sees it, not even « reading »). It reads the Bull wallet's price when the screen shows a step of the rule (the payout at 6 or 8, « fiat sent » at 9) and no read of that step's contract is younger than [freshFor]: so once per step, and again at a later show once the last read is [freshFor] old (8 shown hours after 6), never more often, and on « Retry » after a price that could not be read; never in a loop of its own.
class PayoutRateCubit extends Cubit<PayoutRateState> {
  final TradeRecord record;
  final PayoutRateChecker _check;
  final DateTime Function() _now;

  /// How old a read may be when its step is shown again: older, it is read again (the create form's own bound, `MakeOrderCubit.staleAfter`).
  static const Duration freshFor = Duration(minutes: 3);

  /// The step whose price was asked last, so that the same step is never read twice by itself, and when that read ended.
  PayoutRateStep? _asked;
  DateTime? _readAt;

  /// The status last shown at that step, for « Retry ».
  TradeSeen? _seen;

  PayoutRateCubit(
    this.record,
    this._check, {
    required DateTime Function() now,
  }) : _now = now,
       super(const PayoutRateNone());

  /// The screen shows [seen]: its step's price is read when it was not read for that step yet, or when that read is [freshFor] old.
  Future<void> show(TradeSeen seen) async {
    if (record.origin != TradeOrigin.madeHere ||
        record.role != TradeRole.buyer) {
      return;
    }
    final step = PayoutRateStep.of(seen.status);
    if (step == null || !seen.stored) {
      if (state is! PayoutRateNone && step != _asked) {
        emit(const PayoutRateNone());
      }
      return;
    }
    _seen = seen;
    final readAt = _readAt;
    final stale =
        readAt != null && !_now().isBefore(readAt.add(freshFor));
    // No sats in the last read: looked at again at each show, which reads no price until the read gives sats.
    final missing = state is PayoutRateSatsMissing;
    if (step == _asked && !stale && !missing) return;
    if (step == _asked && state is PayoutRateReading) return;
    _asked = step;
    await _read(step, seen);
  }

  /// « Retry »: the price read again for the step shown, only after a price that could not be read.
  Future<void> retry() async {
    final seen = _seen;
    if (seen == null) return;
    if (state case PayoutRateChecked(
      :final step,
      check: WalletRateUnverified(),
    )) {
      await _read(step, seen);
    }
  }

  Future<void> _read(PayoutRateStep step, TradeSeen seen) async {
    if (isClosed) return;
    emit(PayoutRateReading(step));
    final finding = await _check(record, seen);
    // A late answer for a step no longer shown is dropped.
    if (isClosed || _asked != step) return;
    _readAt = _now();
    emit(switch (finding) {
      null => const PayoutRateNone(),
      PayoutRateFound(:final check) => PayoutRateChecked(step, check),
      PayoutRateNoSats() => PayoutRateSatsMissing(step),
    });
  }
}
