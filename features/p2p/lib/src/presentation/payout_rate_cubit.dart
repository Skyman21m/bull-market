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

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3), on the trade screen: the only caller of [CheckPayoutRateUsecase], for an order made here whose user buys only (a taker's trade never sees it, not even « reading »). It reads the Bull wallet's price when the screen shows a step of the rule (the payout at 6 or 8, « fiat sent » at 9) for the first time; again when that step appears anew (the screen built, shown again, the app back) or moves to another status (8 after 6) while the last read is [freshFor] old; and on « Retry » after a price that could not be read. A new read of the same status, which the trade's watch brings at its own cadence, never reads the price again: never in a loop.
class PayoutRateCubit extends Cubit<PayoutRateState> {
  final TradeRecord record;
  final PayoutRateChecker _check;

  /// The clock of the reads' age.
  final DateTime Function() now;

  /// How old a read may be when its step is shown again: older, it is read again (the create form's own bound, `MakeOrderCubit.staleAfter`).
  static const Duration freshFor = Duration(minutes: 3);

  /// The step whose price was asked last, so that the same step is never read twice by itself, and when that read ended.
  PayoutRateStep? _asked;
  DateTime? _readAt;

  /// The status last shown, so that 8 after 6 is a new show of the same step.
  Type? _status;

  /// The status last shown at that step, for « Retry ».
  TradeSeen? _seen;

  PayoutRateCubit(this.record, this._check, {required this.now})
    : super(const PayoutRateNone());

  /// The screen shows [seen]: its step's price is read when it was not read for that step yet, or, when the read is [freshFor] old, if the step [appeared] anew (the screen built, shown again, the app back) or its status moved (8 after 6).
  Future<void> show(TradeSeen seen, {bool appeared = false}) async {
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
    final moved = _status != null && _status != seen.status.runtimeType;
    _status = seen.status.runtimeType;
    final readAt = _readAt;
    final stale = readAt != null && !now().isBefore(readAt.add(freshFor));
    // No sats in the last read: looked at again at each show, which reads no price until the read gives sats.
    final missing = state is PayoutRateSatsMissing;
    if (step == _asked && state is PayoutRateReading) return;
    if (step == _asked && !missing && !(stale && (appeared || moved))) return;
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
    _readAt = now();
    emit(switch (finding) {
      null => const PayoutRateNone(),
      PayoutRateFound(:final check) => PayoutRateChecked(step, check),
      PayoutRateNoSats() => PayoutRateSatsMissing(step),
    });
  }
}
