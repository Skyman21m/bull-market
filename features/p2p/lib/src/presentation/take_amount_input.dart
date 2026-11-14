import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/trade_take.dart';

/// What the amount field of a range order says of the text typed, as the official client's take button does (`components/OrderDetails/TakeButton.tsx:115-186`).
///
/// The text is read as a number, a comma taken as the decimal separator as well as a point; for an order in bitcoin it is a number of sats, divided by 10⁸ as the reference does (`:126-127`).
/// Below the order's minimum it is « Too low », above its maximum « Too high »; empty, or not a number, « Take Order » is disabled with nothing under the field.
@immutable
sealed class TakeAmountInput {
  const TakeAmountInput();

  /// What [text], typed in the amount field of [order], says.
  static TakeAmountInput read(String text, PublicOrder order) {
    final amount = order.amount;
    if (amount is! RangeOrderAmount) return const TakeAmountEmpty();
    final typed = double.tryParse(text.trim().replaceAll(',', '.'));
    if (typed == null || !typed.isFinite) return const TakeAmountEmpty();
    final value = order.currency.isBitcoin ? typed / 100000000 : typed;
    if (value < amount.min.value) return const TakeAmountTooLow();
    if (value > amount.max.value) return const TakeAmountTooHigh();
    return switch (TakeAmount.tryCreate(value)) {
      final valid? => TakeAmountValid(valid, value),
      null => const TakeAmountEmpty(),
    };
  }
}

/// Nothing typed, or not a number: « Take Order » disabled, nothing said.
final class TakeAmountEmpty extends TakeAmountInput {
  const TakeAmountEmpty();
}

/// Below the order's minimum: « Too low ».
final class TakeAmountTooLow extends TakeAmountInput {
  const TakeAmountTooLow();
}

/// Above the order's maximum: « Too high ».
final class TakeAmountTooHigh extends TakeAmountInput {
  const TakeAmountTooHigh();
}

/// Within the order's range: « Take Order » takes [amount]; [value] is the amount in the order's currency, for the estimate.
final class TakeAmountValid extends TakeAmountInput {
  final TakeAmount amount;
  final double value;

  const TakeAmountValid(this.amount, this.value);
}
