import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import 'trade/maker_form.dart';

/// A range typed in « From » and « to »: its smallest and largest amounts.
typedef MatchingRange = ({double min, double max});

/// « Existing orders match yours! » (#186): the orders of the book that resemble the one the create form is about to make, which the user could take instead, found as the official client finds them (`basic/MakerPage/index.tsx:33-59` calling `utils/filterOrders.ts`, commit ff1998c).
///
/// The reference's filter is given the book's favourites with the form's values: `type: fav.type`, the type of the orders shown (the book's « I want to buy » sets it to 1, `BookTable/BookControl.tsx:68-88`, and so does the form's « Buy », `MakerForm.tsx:764-775`), while the order made is of the other type (`MakerForm.tsx:258`): a buyer is shown the sell orders, those a buyer can take. No side chosen shows both types (`filterOrders.ts:88`, `baseFilter.type === null`).
///
/// Field by field, in the order of `filterOrders.ts:96-104`:
/// - the coordinator (`coordinatorCheck`, `:85-87`) and the host (`hostChecks`, `:95`, `'robosats'`: a coordinator of the federation, `filterByHost`, `:38-40`): every order of the book received comes from a coordinator of the federation list, which all are (`models/Federation.model.ts:57`), so both always hold here and are not tested again;
/// - the type ([type], `:88`);
/// - the mode: `fiat`, so never an order whose currency is bitcoin (`:89`);
/// - the premium ([premium], `filterByPremium`, `:62-69`): when one is typed, a buy order is kept at that premium or higher, a sell order at that premium or lower, the side where taking it is no worse;
/// - the currency ([currency], `:91`): the form's, never « any » (`fav.currency === 0 ? 1 : fav.currency`, `MakerPage/index.tsx:37`);
/// - the payment methods ([paymentMethods], `filterByPayment`, `:19-29`): none chosen keeps every order, else an order whose text contains one of their names, case included;
/// - the amount (`filterByAmount`, `:46-60`): the exact amount typed ([amount]), from 0.3 to 1.7 times it ([threshold] 0.7, `MakerPage/index.tsx:48`), or with « Amount Range » the range typed ([range]), from 0.3 times its minimum to 1.7 times its maximum ([rangeThreshold]), overlapping the order's amount or range.
///
/// A deviation from the reference, its defect corrected (#230, the owner's decision of 2026-11-19, declared in its pull request): `filterByAmount` is written to take the range's bounds when no exact amount is given (`filter.amount !== '' ? filter.amount : filter.maxAmount`), but `maker.amount` is a number or `null`, never `''`, so the reference always searches the exact amount the field « Amount » holds, even while « Amount Range » hides it, and 0 when none is typed (`Number(null)`), which keeps no order: an order made with a range of 50 to 200 is never shown an order of 120. Here, with « Amount Range » on, the range typed is searched as that line means to, and the field « Amount » it hides is not; an exact amount is searched as the reference searches it.
@immutable
final class MatchingOrders {
  /// How far an order's amount may be from the amount typed, as a share of it (`threshold: 0.7`, `MakerPage/index.tsx:48`).
  static const double threshold = 0.7;

  /// How far an order's amount may be below a range's minimum and above its maximum, as a share of each (#230): the reference's [threshold], the same as for an exact amount, which its line for a range applies (`filterOrders.ts:47-50`), so a range of 50 to 200 searches from 15 to 340. Set to 0, the search is the range itself, from 50 to 200: the one line to change if the owner prefers it.
  static const double rangeThreshold = threshold;

  /// The type of the orders shown, the other side of the order made (`fav.type`); `null` while no side is chosen, which shows both.
  final OrderType? type;

  final RobosatsCurrency currency;

  /// The premium typed (`maker.premium ?? null`), kept within its bounds as the form keeps it; `null` when none or no number is typed, which keeps every premium.
  final double? premium;

  /// The names of the methods chosen (`maker.paymentMethods`).
  final List<String> paymentMethods;

  /// The exact amount typed (`maker.amount`), 0 when none or no number is; searched only when there is no [range].
  final double amount;

  /// With « Amount Range » on, the range searched in place of [amount] (`maker.minAmount`, `maker.maxAmount`); `null` for an exact amount. A range the form does not take is [noRange], which keeps no order.
  final MatchingRange? range;

  MatchingOrders({
    required this.type,
    required this.currency,
    required this.premium,
    required Iterable<String> paymentMethods,
    required this.amount,
    this.range,
  }) : paymentMethods = List.unmodifiable(paymentMethods);

  /// The range searched when the bounds typed are not a range the form takes: both 0, as an exact amount none typed is searched at 0 (`Number(null)`), which keeps no order.
  static const MatchingRange noRange = (min: 0, max: 0);

  /// The search for the form [input] as [check] reads it: the side shown is the other of the side chosen, the premium is the form's ([MakerFormCheck.premiumPercent]) when a number is typed, the amount the field « Amount » ([MakerFormCheck.amount]), or with « Amount Range » the range typed ([rangeOf]).
  factory MatchingOrders.of(MakerFormInput input, MakerFormCheck check) =>
      MatchingOrders(
        type: switch (input.type) {
          null => null,
          OrderType.buy => OrderType.sell,
          OrderType.sell => OrderType.buy,
        },
        currency: input.currency,
        premium: check.premiumField is FormNumberValue
            ? check.premiumPercent
            : null,
        paymentMethods: input.paymentMethods,
        amount: check.amount,
        range: check.hasRange ? rangeOf(check) : null,
      );

  /// The range of a form with « Amount Range » on, as [check] reads it: « From » and « to » when both are numbers above 0 and the form shows no error on them ([MakerFormCheck.rangeMinError], [MakerFormCheck.rangeMaxError]: bounds crossed, too close or too far apart, outside the coordinator's limits); else [noRange], nothing searched, as for an exact amount none typed. A range the form refuses can be made by no one, and « Create order » stays disabled whatever the search finds; searching it would show what no reading of the range gives (200 to 50 would search from 60 to 85).
  static MatchingRange rangeOf(MakerFormCheck check) {
    final min = check.minAmountField.value;
    final max = check.maxAmountField.value;
    if (min == null || max == null || min <= 0 || max <= 0) return noRange;
    if (check.rangeMinError || check.rangeMaxError) return noRange;
    return (min: min, max: max);
  }

  /// Whether [order] resembles the order being made (`filterOrders.ts:82-106`).
  bool matches(PublicOrder order) {
    final typeChecks = type == null || order.type == type;
    final modeChecks = !order.currency.isBitcoin;
    final premiumChecks = switch (premium) {
      final premium? => _byPremium(order, premium),
      null => true,
    };
    final currencyChecks = order.currency == currency;
    final paymentMethodChecks =
        paymentMethods.isEmpty ||
        paymentMethods.any(order.paymentMethods.text.contains);
    final amountChecks = _byAmount(order);
    return typeChecks &&
        modeChecks &&
        premiumChecks &&
        currencyChecks &&
        paymentMethodChecks &&
        amountChecks;
  }

  /// `filterByPremium` (`filterOrders.ts:62-69`).
  static bool _byPremium(PublicOrder order, double premium) =>
      order.type == OrderType.buy
      ? order.premium.percent >= premium
      : order.premium.percent <= premium;

  /// `filterByAmount` (`filterOrders.ts:46-60`): the exact amount typed, or the range when there is one (see the class).
  bool _byAmount(PublicOrder order) {
    final (filterMinAmount, filterMaxAmount) = switch (range) {
      (:final min, :final max) => (
        min * (1 - rangeThreshold),
        max * (1 + rangeThreshold),
      ),
      null => (amount * (1 - threshold), amount * (1 + threshold)),
    };
    // `order.amount` for a fixed order, its `min_amount` and `max_amount` for a range (`:52-57`).
    final orderMinAmount = order.amount.min.value;
    final orderMaxAmount = order.amount.max.value;
    return math.max(filterMinAmount, orderMinAmount) <=
        math.min(filterMaxAmount, orderMaxAmount);
  }

  /// The orders of [book] that match, never one [isOwn] says this device holds (the owner's rule, where the reference shows them too), in the order the reference's table shows them (`components/BookTable/index.tsx:118-122`): by premium, from the lowest when sell orders are shown, from the highest when buy orders are, in the book's order when both are; equal premiums keep the book's order.
  List<PublicOrder> apply(
    Iterable<PublicOrder> book, {
    required bool Function(PublicOrder order) isOwn,
  }) {
    final kept = [
      for (final order in book)
        if (matches(order) && !isOwn(order)) order,
    ];
    final direction = switch (type) {
      null => 0,
      OrderType.sell => 1,
      OrderType.buy => -1,
    };
    if (direction == 0) return kept;
    final ranked = kept.indexed.toList()
      ..sort((a, b) {
        final byPremium = a.$2.premium.compareTo(b.$2.premium) * direction;
        return byPremium != 0 ? byPremium : a.$1.compareTo(b.$1);
      });
    return [for (final (_, order) in ranked) order];
  }
}
