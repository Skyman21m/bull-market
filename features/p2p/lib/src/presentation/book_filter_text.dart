import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/book_filter.dart';
import 'coordinator_text.dart';

/// The texts of the filter sentence of the book and of its empty book, in the language of [l10n] (#101).
///
/// Each selector names its subject while nothing is chosen (« Any currency »), where the official client shows « ANY » on all four: the owner's request, so that one can tell them apart without opening them.
/// With one choice it shows that choice; with several, the first one chosen and how many more (« EUR +2 »), as the official client shows its hidden payment method tags; a screen reader hears the subject and every choice (« Currency: EUR, USD or CHF »).
/// The sentence starts with « I want » while no order type is chosen, « I want [Any type] » reading as English where « I want to [Any type] » would not, and with the official client's « I want to » once one is (« I want to [Buy] »).
final class BookFilterText {
  final P2pLocalizations l10n;

  const BookFilterText(this.l10n);

  /// The words before the order type.
  String start(BookSide side) => switch (side) {
    BookSide.any => l10n.p2pBookFilterIWant,
    BookSide.buy || BookSide.sell => l10n.p2pBookFilterIWantTo,
  };

  /// The order type as its selector shows it and as its list names it.
  String side(BookSide side) => switch (side) {
    BookSide.any => l10n.p2pBookFilterAnyType,
    BookSide.buy => l10n.p2pBookFilterBuy,
    BookSide.sell => l10n.p2pBookFilterSell,
  };

  String sideSemantics(BookSide side) => _semantics(
    l10n.p2pBookFilterSubjectType,
    [if (side != BookSide.any) this.side(side)],
    l10n.p2pBookFilterAnyType,
  );

  String currencies(BookFilter filter) =>
      _compact(_codes(filter), l10n.p2pBookFilterAnyCurrency);

  String currenciesSemantics(BookFilter filter) => _semantics(
    l10n.p2pBookFilterSubjectCurrency,
    _codes(filter),
    l10n.p2pBookFilterAnyCurrency,
  );

  String paymentMethods(BookFilter filter) =>
      _compact(filter.paymentMethods.toList(), l10n.p2pBookFilterAnyMethod);

  String paymentMethodsSemantics(BookFilter filter) => _semantics(
    l10n.p2pBookFilterSubjectMethod,
    filter.paymentMethods.toList(),
    l10n.p2pBookFilterAnyMethod,
  );

  String hosts(BookFilter filter) =>
      _compact(_hostNames(filter), l10n.p2pBookFilterAnyHost);

  String hostsSemantics(BookFilter filter) => _semantics(
    l10n.p2pBookFilterSubjectHost,
    _hostNames(filter),
    l10n.p2pBookFilterAnyHost,
  );

  /// The first line of the empty book: the official client's message, to sell when « Sell » is chosen and to buy otherwise, for the currency chosen, every currency chosen (« EUR, USD or CHF »), or any currency.
  String emptyBook(BookFilter filter) {
    final codes = _codes(filter);
    final currencies = codes.isEmpty
        ? l10n.p2pBookEmptyAnyCurrency
        : orList(codes);
    return filter.side == BookSide.sell
        ? l10n.p2pBookEmptySell(currencies)
        : l10n.p2pBookEmptyBuy(currencies);
  }

  /// [items] as one choice or another: « EUR », « EUR or USD », « EUR, USD or CHF ».
  String orList(List<String> items) => switch (items) {
    [] => '',
    [final single] => single,
    [...final others, final last] => l10n.p2pBookFilterOrList(
      others.join(l10n.p2pBookFilterListSeparator),
      last,
    ),
  };

  /// The name of a coordinator, cleaned and bounded as every P2P screen shows it.
  static String hostName(Coordinator coordinator) => CoordinatorText.of(
    coordinator.longAlias,
    maxCodePoints: CoordinatorText.name,
  );

  static List<String> _codes(BookFilter filter) => [
    for (final currency in filter.currencies) currency.code,
  ];

  static List<String> _hostNames(BookFilter filter) => [
    for (final host in filter.hosts) hostName(host),
  ];

  String _compact(List<String> chosen, String any) => switch (chosen) {
    [] => any,
    [final single] => single,
    [final first, ...final more] => l10n.p2pBookFilterMore(first, more.length),
  };

  String _semantics(String subject, List<String> chosen, String any) =>
      chosen.isEmpty ? any : l10n.p2pBookFilterChoices(subject, orList(chosen));
}
