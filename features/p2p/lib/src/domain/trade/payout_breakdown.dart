import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RoutingBudgetPpm;

import 'trade_payout.dart';
import 'trade_status.dart';
import 'trade_warning.dart';

/// The sats of the buyer's payout from top to bottom, each line explaining the next (#228, the owner's request after the trial of 2026-11-18): what the coordinator gives the contract, its fee already taken out, the Lightning routing budget, the invoice to give, the swap service's fee and what reaches the wallet.
///
/// Built only from one [PayoutAsk] (one read of the order), the routing budget of the form and, for the last two lines, the invoice this wallet made for exactly the invoice's amount: nothing new is read from the coordinator, and every line below the first is a difference of whole sats already kept, so the breakdown adds up to the sat by construction (`given − routingBudget = invoice`, `invoice − swapFee = received`). The roundings are the reference's own, never computed again here: the coordinator's `round` of the payout (`api/logics.py:650-669`) is in `trade_satoshis`, and the budget's truncation (`api/logics.py:869-872`) is [RoutingBudgetPpm.invoiceSats], the very amount the invoice is checked against.
///
/// None while the state machine says the contract's amounts do not agree ([amountsDisagree]) or the order read gives the contract another amount than the one asked here (`TradeSeen.contractAmountMoved`): its alert is then said alone, as the owner's payment rule says nothing then (`PayoutRateMismatch`).
@immutable
final class PayoutBreakdown {
  /// What the coordinator gives the contract for the buyer (`trade_satoshis`, its `invoice_amount`): the trade's sats less the coordinator's fee (`api/logics.py:650-669`).
  final Sats given;

  /// The coordinator's fee taken out of [given]: the trade's sats the order gives a participant (`satoshis_now`, the order's `last_satoshis`, `api/views.py:323`) less [given], two figures of the same read; `null` when the read gives no `satoshis_now` or a figure below [given] (the state machine then raises an amount warning and there is no breakdown at all: never here in practice). Whether it agrees with the fee announced is the state machine's check (`MakerTerms.feeAgrees`, `TakerFeeAboveAnnounced`), whose warning hides the breakdown.
  final Sats? coordinatorFee;

  /// The invoice to give for the form's routing budget ([PayoutAsk.invoiceSatsFor]); `null` above the read bounds, and the lines from the budget on are then not said.
  final Sats? invoice;

  /// What this wallet's invoice brings, when the field holds an invoice this wallet made for exactly [invoice]; `null` otherwise (no invoice made yet, one pasted from another wallet, or one made for another amount).
  final PayoutSwapReceipt? swap;

  const PayoutBreakdown._({
    required this.given,
    required this.coordinatorFee,
    required this.invoice,
    required this.swap,
  });

  /// The breakdown of [ask] with the routing budget [budget], and [wallet] the amount and the sats received of the invoice this wallet made, when the field holds it; `null` while the amounts do not agree.
  static PayoutBreakdown? of(
    PayoutAsk ask, {
    required RoutingBudgetPpm budget,
    ({Sats amount, Sats received})? wallet,
  }) {
    final seen = ask.seen;
    if (amountsDisagree(seen.status) || seen.contractAmountMoved) return null;
    final given = ask.buyerSats;
    final last = ask.order.satoshisNow;
    final fee = last == null || last.value < given.value
        ? null
        : Sats(last.value - given.value);
    final invoice = ask.invoiceSatsFor(budget);
    final swap = switch ((invoice, wallet)) {
      (final invoice?, (:final amount, :final received))
          when amount == invoice &&
              received.value > BigInt.zero &&
              received.value <= amount.value =>
        PayoutSwapReceipt._(
          fee: Sats(amount.value - received.value),
          received: received,
        ),
      _ => null,
    };
    return PayoutBreakdown._(
      given: given,
      coordinatorFee: fee,
      invoice: invoice,
      swap: swap,
    );
  }

  /// The routing budget the invoice leaves to the coordinator: [given] less [invoice]; `null` without an invoice.
  Sats? get routingBudget => switch (invoice) {
    final invoice? => Sats(given.value - invoice.value),
    null => null,
  };

  /// The warnings of the state machine that say the amounts of a contract do not agree with each other or with the terms: while one is raised, nothing is compared (the owner's payment rule, security review of #182, C1 bis) and no breakdown is said, the warning alone.
  static bool amountsDisagree(TradeStatus status) => status.warnings.any(
    (warning) =>
        warning is PayoutAmountMismatch ||
        warning is MakerFeeAboveAnnounced ||
        warning is TakerFeeAboveAnnounced ||
        warning is TradePriceOutsideOrder ||
        warning is InvoiceAmountMismatch,
  );

  @override
  bool operator ==(Object other) =>
      other is PayoutBreakdown &&
      other.given == given &&
      other.coordinatorFee == coordinatorFee &&
      other.invoice == invoice &&
      other.swap == swap;

  @override
  int get hashCode => Object.hash(given, coordinatorFee, invoice, swap);

  /// Never a figure: the breakdown is shown, not logged.
  @override
  String toString() => 'PayoutBreakdown';
}

/// The last two lines of a [PayoutBreakdown]: the swap service's fee and what reaches the Instant Payments wallet ([received]), the invoice's amount less that fee.
@immutable
final class PayoutSwapReceipt {
  final Sats fee;
  final Sats received;

  const PayoutSwapReceipt._({required this.fee, required this.received});

  @override
  bool operator ==(Object other) =>
      other is PayoutSwapReceipt &&
      other.fee == fee &&
      other.received == received;

  @override
  int get hashCode => Object.hash(fee, received);

  @override
  String toString() => 'PayoutSwapReceipt';
}
