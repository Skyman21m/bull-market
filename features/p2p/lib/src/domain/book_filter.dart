import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// What the user wants to do, the first choice of the filter sentence of the book: « I want to [Buy] ».
enum BookSide {
  /// Both sides: every order is shown.
  any,

  /// The user buys bitcoin, so the book shows the orders of makers who sell.
  buy,

  /// The user sells bitcoin, so the book shows the orders of makers who buy.
  sell;

  /// The type of the orders this side shows, or `null` for both.
  OrderType? get shownType => switch (this) {
    any => null,
    buy => OrderType.sell,
    sell => OrderType.buy,
  };
}

/// The filter sentence of the book, « I want to [side] and use [currency] pay with [method] hosted by [host] », as the official client applies it (`utils/filterOrders.ts`).
///
/// A `null` currency, payment method or host means any.
/// Like the official client by default (`mode: 'fiat'`), the book never shows swap orders, whose currency is bitcoin: they belong to the « Swap In » and « Swap Out » choices, which this filter does not offer yet.
@immutable
final class BookFilter {
  final BookSide side;
  final RobosatsCurrency? currency;

  /// The name of a recognised payment method, which the text of an order must contain.
  final String? paymentMethod;
  final Coordinator? host;

  const BookFilter({
    this.side = BookSide.any,
    this.currency,
    this.paymentMethod,
    this.host,
  });

  BookFilter withSide(BookSide side) => BookFilter(
    side: side,
    currency: currency,
    paymentMethod: paymentMethod,
    host: host,
  );

  BookFilter withCurrency(RobosatsCurrency? currency) => BookFilter(
    side: side,
    currency: currency,
    paymentMethod: paymentMethod,
    host: host,
  );

  BookFilter withPaymentMethod(String? paymentMethod) => BookFilter(
    side: side,
    currency: currency,
    paymentMethod: paymentMethod,
    host: host,
  );

  BookFilter withHost(Coordinator? host) => BookFilter(
    side: side,
    currency: currency,
    paymentMethod: paymentMethod,
    host: host,
  );

  /// Whether [order] belongs to the book this filter shows.
  ///
  /// The payment method is matched as the official client does: the text of the order contains its name, case included.
  bool matches(PublicOrder order) =>
      _matchesAllButMethod(order) &&
      switch (paymentMethod) {
        null => true,
        final method => order.paymentMethods.text.contains(method),
      };

  bool _matchesAllButMethod(PublicOrder order) {
    if (order.currency.isBitcoin) return false;
    if (side.shownType case final type? when order.type != type) return false;
    if (currency case final currency? when order.currency != currency) {
      return false;
    }
    if (host case final host? when order.coordinator != host) return false;
    return true;
  }

  /// The orders that match, in the default order of the official client (`components/BookTable/index.tsx`).
  ///
  /// Buying sorts by premium from the lowest, selling from the highest, the best offer first either way.
  /// With both sides the official client does not sort, so the orders keep the given order.
  /// Equal premiums keep the given order too.
  List<PublicOrder> apply(Iterable<PublicOrder> orders) {
    final kept = [
      for (final order in orders)
        if (matches(order)) order,
    ];
    final direction = switch (side) {
      BookSide.any => 0,
      BookSide.buy => 1,
      BookSide.sell => -1,
    };
    if (direction == 0) return kept;
    final ranked = kept.indexed.toList()
      ..sort((a, b) {
        final byPremium = a.$2.premium.compareTo(b.$2.premium) * direction;
        return byPremium != 0 ? byPremium : a.$1.compareTo(b.$1);
      });
    return [for (final (_, order) in ranked) order];
  }

  /// The recognised payment methods of the orders that match every other choice, in the order of the official list, for the payment method selector.
  List<PaymentMethodInfo> paymentMethodsIn(Iterable<PublicOrder> orders) {
    final found = <PaymentMethodInfo>{
      for (final order in orders)
        if (_matchesAllButMethod(order)) ...order.paymentMethods.recognized,
    }..remove(PaymentMethods.notSpecified);
    return [
      for (final method in PaymentMethods.known)
        if (found.contains(method)) method,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is BookFilter &&
      other.side == side &&
      other.currency == currency &&
      other.paymentMethod == paymentMethod &&
      other.host == host;

  @override
  int get hashCode => Object.hash(side, currency, paymentMethod, host);

  @override
  String toString() =>
      'BookFilter(${side.name}, ${currency?.code}, ${host?.shortAlias})';
}
