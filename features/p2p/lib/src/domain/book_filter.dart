import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// What the user wants to do, the first choice of the filter sentence of the book: « I want to [Buy] ».
///
/// It stays a single choice, as in the official client: with buy and sell only, choosing both is choosing any, and the order of the book, the side of the empty book's message and the sign of the premium that is best all follow one side (#101).
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

/// The filter sentence of the book, « I want to [side] and use [currencies] pay with [methods] hosted by [hosts] », as the official client applies it (`utils/filterOrders.ts`).
///
/// An empty set of currencies, payment methods or hosts means any; a set that is not empty keeps an order that matches one of its members.
/// The official client takes several payment methods but one currency and one host; several currencies and several hosts are the owner's request (#101), on the same rule.
/// Each set keeps the order its members were chosen in, which the sentence uses to name the first one; two filters with the same members are equal whatever that order.
/// Like the official client by default (`mode: 'fiat'`), the book never shows swap orders, whose currency is bitcoin: they belong to the « Swap In » and « Swap Out » choices, which this filter does not offer yet.
@immutable
final class BookFilter {
  final BookSide side;

  /// The currencies chosen, none for any.
  final Set<RobosatsCurrency> currencies;

  /// The names of the payment methods chosen, none for any: an order is kept when its text contains one of them (`filterByPayment`).
  final Set<String> paymentMethods;

  /// The coordinators chosen, none for any.
  final Set<Coordinator> hosts;

  /// A filter with the given choices; the sets are copied, so a set changed afterwards does not change the filter.
  BookFilter({
    this.side = BookSide.any,
    Iterable<RobosatsCurrency> currencies = const [],
    Iterable<String> paymentMethods = const [],
    Iterable<Coordinator> hosts = const [],
  }) : currencies = _frozen(currencies),
       paymentMethods = _frozen(paymentMethods),
       hosts = _frozen(hosts);

  /// The filter that keeps every order but the swaps, in the order the coordinators gave them.
  const BookFilter.any()
    : side = BookSide.any,
      currencies = const {},
      paymentMethods = const {},
      hosts = const {};

  static Set<T> _frozen<T>(Iterable<T> members) =>
      UnmodifiableSetView(LinkedHashSet.of(members));

  BookFilter withSide(BookSide side) => BookFilter(
    side: side,
    currencies: currencies,
    paymentMethods: paymentMethods,
    hosts: hosts,
  );

  BookFilter withCurrencies(Iterable<RobosatsCurrency> currencies) =>
      BookFilter(
        side: side,
        currencies: currencies,
        paymentMethods: paymentMethods,
        hosts: hosts,
      );

  BookFilter withPaymentMethods(Iterable<String> paymentMethods) => BookFilter(
    side: side,
    currencies: currencies,
    paymentMethods: paymentMethods,
    hosts: hosts,
  );

  BookFilter withHosts(Iterable<Coordinator> hosts) => BookFilter(
    side: side,
    currencies: currencies,
    paymentMethods: paymentMethods,
    hosts: hosts,
  );

  /// Whether [order] belongs to the book this filter shows.
  bool matches(PublicOrder order) =>
      _matchesAllButMethod(order) && matchesPaymentMethods(order);

  /// Whether [order] passes the payment methods chosen, by the official client's rule (`filterByPayment` in `utils/filterOrders.ts`): with none chosen every order does, and otherwise an order does when its text contains the name of at least one of them.
  ///
  /// « Contains » is the official client's `includes`: case included, anywhere in the text, so `SEPA` keeps an order of `Instant SEPA` and `Revolut` does not keep an order written `revolut`, which the list recognises.
  bool matchesPaymentMethods(PublicOrder order) =>
      paymentMethods.isEmpty ||
      paymentMethods.any(order.paymentMethods.text.contains);

  bool _matchesAllButMethod(PublicOrder order) {
    if (order.currency.isBitcoin) return false;
    if (side.shownType case final type? when order.type != type) return false;
    return _matchesCurrencyAndHost(order);
  }

  bool _matchesCurrencyAndHost(PublicOrder order) =>
      (currencies.isEmpty || currencies.contains(order.currency)) &&
      (hosts.isEmpty || hosts.contains(order.coordinator));

  /// Whether the depth chart draws [order]: it filters by currency and host only, as the official client's chart does, so it shows both sides, every payment method, and the swaps when every currency is shown.
  ///
  /// With several currencies or hosts chosen, it draws the orders of each of them.
  bool showsInDepthChart(PublicOrder order) => _matchesCurrencyAndHost(order);

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

  /// The payment methods the selector offers: the official client's fixed list of fiat methods, in its order, whatever the orders of the book and the other choices (`AutocompletePayments.tsx:301` at commit ff1998c, with `optionsType` `fiat`: the app offers no swap currency).
  ///
  /// It is not narrowed to the methods of the orders that match the other choices: a list that shrinks as one chooses a side or a currency reads as methods gone missing (the owner's report of 2026-11-14), and the reference does not do it.
  static List<PaymentMethodInfo> get offeredPaymentMethods =>
      PaymentMethods.fiat;

  @override
  bool operator ==(Object other) =>
      other is BookFilter &&
      other.side == side &&
      _sameMembers(other.currencies, currencies) &&
      _sameMembers(other.paymentMethods, paymentMethods) &&
      _sameMembers(other.hosts, hosts);

  static bool _sameMembers<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  int get hashCode => Object.hash(
    side,
    Object.hashAllUnordered(currencies),
    Object.hashAllUnordered(paymentMethods),
    Object.hashAllUnordered(hosts),
  );

  /// The side, the currencies and the hosts; never the payment methods, which come from the text of orders.
  @override
  String toString() =>
      'BookFilter(${side.name}, '
      '${[for (final currency in currencies) currency.code]}, '
      '${[for (final host in hosts) host.shortAlias]})';
}
