import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade/wallet_rate_check.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/check_payout_rate_usecase.dart';

/// [CheckPayoutRateUsecase.execute], which the locator gives the cubit.
typedef PayoutRateChecker =
    Future<WalletRateCheck?> Function(TradeRecord record, TradeSeen seen);

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

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3), on the trade screen: the only caller of [CheckPayoutRateUsecase]. It reads the Bull wallet's price once per contract and step when the screen shows that step ([show]), and again only on « Retry » ([retry]) after a price that could not be read; never in a loop.
class PayoutRateCubit extends Cubit<PayoutRateState> {
  final TradeRecord record;
  final PayoutRateChecker _check;

  /// The step whose price was asked last, so that the same step is never read twice by itself.
  PayoutRateStep? _asked;

  /// The status last shown at that step, for « Retry ».
  TradeSeen? _seen;

  PayoutRateCubit(this.record, this._check) : super(const PayoutRateNone());

  /// The screen shows [seen]: its step's price is read when it was not read for that step yet.
  Future<void> show(TradeSeen seen) async {
    final step = PayoutRateStep.of(seen.status);
    if (step == null || !seen.stored) {
      if (state is! PayoutRateNone && step != _asked) {
        emit(const PayoutRateNone());
      }
      return;
    }
    _seen = seen;
    if (step == _asked) return;
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
    final check = await _check(record, seen);
    if (isClosed || _asked != step) return;
    emit(
      check == null ? const PayoutRateNone() : PayoutRateChecked(step, check),
    );
  }
}
