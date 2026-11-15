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

  /// The estimate the official client's order details show to the taker who buys, when the coordinator gives neither `invoice_amount` nor `trade_satoshis` yet (before both bonds are locked: `components/OrderDetails/index.tsx:203-229`), for [order] as the coordinator describes it to the trade's robot, with the [takerFee] of its coordinator (0 while it is unknown).
  ///
  /// The rate comes from the order: the amount taken (or the fixed amount) over `satoshis_now`, else the largest amount of the range; the sats are counted as for [of], the taker fee against the coordinator and the default routing budget deducted. `null` when the order gives no sats.
  static TakerEstimate? ofTrade(
    CoordinatorOrder order, {
    required double takerFee,
  }) {
    final satoshisNow = order.satoshisNow?.value.toInt();
    if (satoshisNow == null || satoshisNow <= 0) return null;
    final single = switch ((order.takenAmount, order.amount)) {
      (final taken?, _) => taken,
      (null, FixedOrderAmount(:final amount)) => amount,
      _ => null,
    };
    final top = single ?? order.amount.max;
    final rate = top.value / (satoshisNow / 100000000);
    int sats(FiatAmount amount) =>
        (amount.value /
                rate *
                100000000 *
                (1 + takerFee) *
                (1 - defaultRoutingBudget))
            .round();
    if (single != null) {
      final value = sats(single);
      return TakerEstimate._(value, value);
    }
    return TakerEstimate._(sats(order.amount.min), sats(order.amount.max));
  }

  /// The sats « You will receive {{satoshis}} Sats (Approx) » shows under the amount field of a range order for [amount], an amount of the order's currency (bitcoin for an order in sats), or `null` when the order gives no sats at the current price.
  ///
  /// The official client's take button computes it apart from its order details (`components/OrderDetails/TakeButton.tsx:59-76`): the same rate, the taker fee as a positive fee (`computeSats`, `utils/computeSats.ts`: the sats times one less the fee), and no routing budget, since the order of a robot that is no participant says it is not a buyer (`is_buyer`, `api/views.py:312`).
  static int? takeSats(
    PublicOrder order,
    double amount, {
    required double takerFee,
  }) {
    final satoshisNow = order.satoshisNow?.value.toInt();
    if (satoshisNow == null || satoshisNow <= 0) return null;
    final rate = order.amount.max.value / (satoshisNow / 100000000);
    return (amount / rate * 100000000 * (1 - takerFee)).round();
  }

  /// [takeSats] at the rate of [read], the order as the robot that takes it read it (#119), with the [takerFee] of its terms.
  static int? takeSatsOfRead(
    CoordinatorOrder read,
    double amount, {
    required double takerFee,
  }) {
    final satoshisNow = read.satoshisNow?.value.toInt();
    if (satoshisNow == null || satoshisNow <= 0) return null;
    final rate = read.amount.max.value / (satoshisNow / 100000000);
    return (amount / rate * 100000000 * (1 - takerFee)).round();
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
