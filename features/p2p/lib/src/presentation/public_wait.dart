import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// The two figures of the reference's « Your order is public » (`TradeBox/Prompts/PublicWait.tsx:52-78`), computed from the book this app read, as the reference computes them from its own (design note `docs/design/phase-3-making-an-order.md` § 1.11, § 2.1, #182).
///
/// Its quirks are kept: « Public orders for {{currencyCode}} » counts every order of the book in the order's currency, whatever its side (the reference's filter tests the maker's own status, not the book order's, `:52-60`); « Premium rank » is the share of the book's orders of the same currency and side whose premium is below the order's, floored to a whole percent once rounded to 2 decimals, and 0.5 when the book holds at most one such order (`:62-78`, where 0.5 is shown « 0.5% »).
@immutable
final class PublicWaitStanding {
  /// How many orders of the book are in the order's currency.
  final int similarOrders;

  /// The premium rank in percent: a whole number, or 0.5 when the book holds at most one order of the order's currency and side.
  final double premiumRank;

  const PublicWaitStanding._(this.similarOrders, this.premiumRank);

  /// The figures for [order], a maker's order public, from [book], every order the book received (`BookState.receivedOrders`), the order itself included when the book lists it.
  static PublicWaitStanding of(
    CoordinatorOrder order, {
    required List<PublicOrder> book,
  }) {
    final similar = book.where((o) => o.currency == order.currency).length;
    final query = [
      for (final o in book)
        if (o.currency == order.currency && o.type == order.type) o,
    ];
    if (query.length <= 1) return PublicWaitStanding._(similar, 0.5);
    final premium = order.premium?.percent ?? 0;
    final below = query.where((o) => o.premium.percent < premium).length;
    final percentile = below / query.length * 100;
    return PublicWaitStanding._(
      similar,
      double.parse(percentile.toStringAsFixed(2)).floorToDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PublicWaitStanding &&
      other.similarOrders == similarOrders &&
      other.premiumRank == premiumRank;

  @override
  int get hashCode => Object.hash(similarOrders, premiumRank);

  @override
  String toString() => 'PublicWaitStanding($similarOrders, $premiumRank)';
}
