import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// The sats a taker would trade on a public order, estimated as the official client does in its order details (`components/OrderDetails/index.tsx`, `utils/computeSats.ts`).
///
/// The rate comes from the order itself: its largest amount over [PublicOrder.satoshisNow], the sats it trades at the current price.
/// A taker who buys bitcoin receives the sats of the amount with the taker fee counted against the coordinator and the default routing budget of 0.1 % deducted; a taker who sells sends the sats of the amount less the taker fee.
/// It is an estimate (« Approx »): the coordinator fixes the real figure when the order is taken.
@immutable
final class TakerEstimate {
  /// The sats for the smallest amount of the order.
  final int minSats;

  /// The sats for the largest amount: the same as [minSats] for a fixed amount.
  final int maxSats;

  const TakerEstimate._(this.minSats, this.maxSats);

  /// The routing budget the official client assumes for a buyer's Lightning invoice.
  static const double defaultRoutingBudget = 0.001;

  /// The estimate for a taker of [order], with the [takerFee] of its coordinator as a fraction (0 while it is unknown, as the official client does), or `null` when the order gives no sats at the current price.
  static TakerEstimate? of(PublicOrder order, {required double takerFee}) {
    final satoshisNow = order.satoshisNow?.value.toInt();
    if (satoshisNow == null || satoshisNow <= 0) return null;
    final rate = order.amount.max.value / (satoshisNow / 100000000);
    final takerBuys = order.type == OrderType.sell;
    int sats(FiatAmount amount) {
      var value = amount.value / rate * 100000000;
      value = takerBuys
          ? value * (1 + takerFee) * (1 - defaultRoutingBudget)
          : value * (1 - takerFee);
      return value.round();
    }

    return TakerEstimate._(sats(order.amount.min), sats(order.amount.max));
  }

  /// Whether the order has a range, so the estimate too.
  bool get isRange => minSats != maxSats;

  @override
  bool operator ==(Object other) =>
      other is TakerEstimate &&
      other.minSats == minSats &&
      other.maxSats == maxSats;

  @override
  int get hashCode => Object.hash(minSats, maxSats);

  @override
  String toString() => 'TakerEstimate($minSats-$maxSats)';
}
