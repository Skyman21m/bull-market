import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../robot_binding.dart';
import '../trade_record.dart';
import 'bolt11.dart';
import 'trade_edges.dart';
import 'trade_status.dart';
import 'trade_tolerances.dart';
import 'trade_warning.dart';
import 'trade_watch.dart';

/// Where the buyer of a trade wants the sats, as the user gave it: a Lightning invoice or an on-chain address, pasted, or later made by this wallet (#90, `P2pWalletPort`), the same text either way, checked the same way (`PayoutAsk.check`).
///
/// Its [toString] names no part of the text: an invoice or an address is never printed or logged (design note § 4.3).
@immutable
sealed class PayoutDestination {
  const PayoutDestination();
}

/// A Lightning invoice, with the routing budget the coordinator may spend to pay it (`routing_budget_ppm`, always sent: [RoutingBudgetPpm.referenceDefault] unless the user changes it, as the reference's « Routing Budget » option).
final class PayoutInvoiceText extends PayoutDestination {
  final String text;
  final RoutingBudgetPpm budget;

  const PayoutInvoiceText(this.text, {required this.budget});

  @override
  String toString() => 'PayoutInvoiceText(${budget.ppm} ppm)';
}

/// An on-chain address, paid through the coordinator's swap, with the mining fee rate the coordinator is to use (`mining_fee_rate`, always sent, 2 to 500 sat/vB: [MiningFeeRate]).
final class PayoutAddressText extends PayoutDestination {
  final String text;
  final MiningFeeRate rate;

  const PayoutAddressText(this.text, {required this.rate});

  @override
  String toString() => 'PayoutAddressText($rate)';
}

/// What the coordinator asks of the buyer at a status the trade screen showed: the figures the payout panel shows before anything is pasted, and the checks of what is pasted ([check]).
///
/// Built only from a status marked stored, with the order it was read from ([of]): the amount to ask is the order's `trade_satoshis`, as the reference client computes it (`frontend/src/components/TradeBox/Forms/LightningPayout.tsx:110-113`, commit ff1998c), for a buyer the coordinator's `invoice_amount` (`api/views.py:345-371`, `:413-428`), the only one it sends again at 15 (`:483-488`).
@immutable
final class PayoutAsk {
  final TradeRecord record;
  final TradeSeen seen;

  /// The order [seen] was read from.
  final CoordinatorOrder order;

  /// What the buyer receives, before the routing budget (`trade_satoshis`).
  final Sats buyerSats;

  /// The end of the step (`expires_at`): at 6 and 8 the buyer loses the bond if no payout is in by then (`api/logics.py:360-379`, `:445-458`); at 15 the coordinator retries until it has a new invoice.
  final DateTime deadline;

  /// The on-chain payout, when the coordinator offers it at this step; `null` otherwise, with [onchainRefusal] when the coordinator said why.
  final OnchainAsk? onchain;
  final SwapRefusal? onchainRefusal;

  const PayoutAsk._({
    required this.record,
    required this.seen,
    required this.order,
    required this.buyerSats,
    required this.deadline,
    required this.onchain,
    required this.onchainRefusal,
  });

  /// Whether the coordinator asks for a new invoice after a failed payout (15), rather than for the first payout (6 or 8).
  bool get isNewInvoice => seen.status.position == TradePosition.routingFailed;

  /// The amount the invoice must be for with [budget]: `floor(n − n × ppm / 10⁶)` of [buyerSats], computed as the coordinator computes it ([RoutingBudgetPpm.invoiceSats], `api/logics.py:868-872`); `null` above the read bounds.
  Sats? invoiceSatsFor(RoutingBudgetPpm budget) => budget.invoiceSats(buyerSats);

  /// What the coordinator asks of the buyer of [record] at [seen], or why it asks nothing that can be checked.
  ///
  /// [seen] must be marked stored and come from an order ([TradeSeen.stored], [TradeSeen.order]: `PayoutNeedsARead` otherwise), the order of [record], with this robot as its buyer and at a step that takes a payout: 6 or 8 for an invoice or an address, 15 for a new invoice once the failed one expired (`api/logics.py:752-769`, `:835-863`; [PayoutNotAsked] otherwise).
  static Result<PayoutAsk, PayoutCheckRefusal> of(
    TradeRecord record,
    TradeSeen seen,
  ) {
    final order = seen.order;
    if (!seen.stored || order == null) return const Err(PayoutNeedsARead());
    if (order.id != record.orderId || order.network != record.network) {
      return const Err(PayoutNotAsked());
    }
    final TradeRole role;
    switch (seen.status) {
      case WaitingForBoth(role: final r) || WaitingForPayout(role: final r):
        role = r;
      case RoutingFailed(role: final r, invoiceExpired: true)
          when order.payoutInvoiceExpired == true:
        role = r;
      default:
        return const Err(PayoutNotAsked());
    }
    if (role != TradeRole.buyer ||
        record.role != TradeRole.buyer ||
        order.isBuyer != true) {
      return const Err(PayoutNotAsked());
    }
    final buyerSats = order.tradeSatoshis;
    if (buyerSats == null) return const Err(PayoutAmountUnknown());
    final firstPayout = seen.status.position != TradePosition.routingFailed;
    final invoiceAmount = order.payoutInvoiceAmount;
    final swapFee = order.swapFeeRate;
    final onchain =
        firstPayout &&
            order.swapAllowed == true &&
            invoiceAmount != null &&
            swapFee != null
        ? OnchainAsk._(
            invoiceAmount: invoiceAmount,
            swapFeePercent: swapFee,
            suggestedSatPerVbyte: order.suggestedMiningFeeRate,
          )
        : null;
    return Ok(
      PayoutAsk._(
        record: record,
        seen: seen,
        order: order,
        buyerSats: buyerSats,
        deadline: order.expiresAt,
        onchain: onchain,
        onchainRefusal: firstPayout && order.swapAllowed != true
            ? order.swapRefusal
            : null,
      ),
    );
  }

  /// [destination] decoded and checked against this ask at [now]: the value the panel shows and `SubmitPayoutUsecase.execute` signs, or why it cannot be signed.
  ///
  /// An invoice: the reference's `lightning:` prefix taken off (`LightningPayout.tsx:145-147`), read by [reader] (at most `Bolt11Reader.maxLength` visible ASCII characters, anything the decoder throws a refusal), on the trade's network (`lnbc` on mainnet, `lntb` on testnet: [PayoutInvoiceOfAnotherNetwork] otherwise, no way around it), for exactly [invoiceSatsFor] its budget ([PayoutInvoiceAmountNotAsked] otherwise: the reference client disables « Submit » on « Invalid invoice amount », `:115-128`, `:643`, and the coordinator refuses it), not expired at [now] ([PayoutInvoiceExpired]: the coordinator refuses it, `api/lightning/lnd.py:529-533`); one that expires before the end of the step and [TradeTolerances.payoutInvoiceAfterStep] carries [PayoutWarning.invoiceMayExpireFirst].
  /// An address: offered by the coordinator at this step ([PayoutOnchainNotOffered] otherwise: the coordinator answers a `500` without a swap, `api/logics.py:800-803`), checked by [BitcoinAddress.check] for the trade's network ([PayoutAddressUnusable] otherwise); what it receives is [MiningFeeRate.sentSats] of `invoice_amount` (`api/logics.py:806-813`), and under [MiningFeeRate.minimumSentSats] it carries [PayoutWarning.sentBelowMinimum] (the coordinator refuses it with 4003; the reference client does not stop it).
  /// Every warning of the status is carried too: information, never a refusal (design note § 3.7).
  Result<CheckedPayout, PayoutCheckRefusal> check(
    PayoutDestination destination, {
    required DateTime now,
    required Bolt11Reader reader,
  }) {
    final network = record.network;
    switch (destination) {
      case PayoutInvoiceText(:final text, :final budget):
        final invoice = text.startsWith(_lightningPrefix)
            ? text.substring(_lightningPrefix.length)
            : text;
        final Bolt11Invoice facts;
        switch (reader.read(invoice)) {
          case Err(:final failure):
            return Err(PayoutInvoiceUnreadable(failure));
          case Ok(:final value):
            facts = value;
        }
        if (!facts.network.belongsTo(network)) {
          return const Err(PayoutInvoiceOfAnotherNetwork());
        }
        final asked = invoiceSatsFor(budget);
        if (asked == null) return const Err(PayoutAmountUnknown());
        if (facts.amount != asked) {
          return const Err(PayoutInvoiceAmountNotAsked());
        }
        if (!now.isBefore(facts.expiresAt)) {
          return const Err(PayoutInvoiceExpired());
        }
        return Ok(
          CheckedPayoutInvoice._(
            destination: destination,
            robot: record.robot,
            orderId: record.orderId,
            network: network,
            text: invoice,
            facts: facts,
            buyerSats: buyerSats,
            budget: budget,
            statusWarnings: seen.status.warnings,
            warnings: [
              if (!isNewInvoice &&
                  facts.expiresAt.isBefore(
                    deadline.add(TradeTolerances.payoutInvoiceAfterStep),
                  ))
                PayoutWarning.invoiceMayExpireFirst,
            ],
          ),
        );
      case PayoutAddressText(:final text, :final rate):
        final ask = onchain;
        if (ask == null) return const Err(PayoutOnchainNotOffered());
        final BitcoinAddress address;
        switch (BitcoinAddress.check(text, network)) {
          case Err(:final failure):
            return Err(PayoutAddressUnusable(failure));
          case Ok(:final value):
            address = value;
        }
        final sent = ask.sentSatsFor(rate);
        if (sent == null) return const Err(PayoutAmountUnknown());
        return Ok(
          CheckedPayoutAddress._(
            destination: destination,
            robot: record.robot,
            orderId: record.orderId,
            network: network,
            address: address,
            rate: rate,
            invoiceAmount: ask.invoiceAmount,
            swapFeePercent: ask.swapFeePercent,
            sentSats: sent,
            statusWarnings: seen.status.warnings,
            warnings: [
              if (sent < MiningFeeRate.minimumSentSats)
                PayoutWarning.sentBelowMinimum,
            ],
          ),
        );
    }
  }

  static const _lightningPrefix = 'lightning:';

  @override
  String toString() => 'PayoutAsk(${seen.status})';
}

/// The on-chain payout the coordinator offers the buyer: its swap fee and its suggested mining fee rate (`swap_allowed`, `swap_fee_rate`, `suggested_mining_fee_rate`, `api/logics.py:671-730`).
@immutable
final class OnchainAsk {
  /// The buyer's amount the swap starts from (`invoice_amount`), as the reference's panel computes it (`OnchainPayout.tsx:66-101`).
  final Sats invoiceAmount;

  /// The coordinator's swap fee, a percentage of [invoiceAmount] (`swap_fee_rate`).
  final double swapFeePercent;

  /// The rate the coordinator suggests, as it sends it: up to 1,000 (`api/logics.py:630-634`), so above what may be sent; [suggestedRate] is it when it can be.
  final double? suggestedSatPerVbyte;

  const OnchainAsk._({
    required this.invoiceAmount,
    required this.swapFeePercent,
    required this.suggestedSatPerVbyte,
  });

  /// The suggested rate as a rate that may be sent, the reference's default for its field (`OnchainPayout.tsx:48-50`); `null` when there is none or it is outside 2 to 500 sat/vB: the panel then offers at most 500 and says the coordinator suggests more than the app allows.
  MiningFeeRate? get suggestedRate => switch (suggestedSatPerVbyte) {
    final rate? => MiningFeeRate.of(rate),
    null => null,
  };

  /// The swap fee in sats, as the reference's panel shows it: `floor(invoice_amount × swap_fee_rate / 100)` (`OnchainPayout.tsx:66-71`).
  int get swapFeeSats =>
      (invoiceAmount.value.toDouble() * swapFeePercent / 100).floor();

  /// The mining fee in sats at [rate] over the 280 vB the coordinator charges: `int(rate × 280)` (`api/logics.py:807`).
  int miningFeeSatsFor(MiningFeeRate rate) =>
      (rate.satPerVbyte * MiningFeeRate.chargedVbytes).truncate();

  /// What the address receives at [rate], computed as the coordinator computes it ([MiningFeeRate.sentSats], `api/logics.py:806-813`); `null` above the read bounds.
  int? sentSatsFor(MiningFeeRate rate) =>
      rate.sentSats(buyerSats: invoiceAmount, swapFeePercent: swapFeePercent);

  @override
  String toString() => 'OnchainAsk($swapFeePercent %)';
}

/// Something the user should know before a payout is signed, which never stops it (design note § 3.7).
enum PayoutWarning {
  /// The invoice expires before the end of the step and [TradeTolerances.payoutInvoiceAfterStep]: if the seller confirms after that, the coordinator cannot pay it and asks for a new one (15).
  invoiceMayExpireFirst,

  /// What the address would receive is under [MiningFeeRate.minimumSentSats]: the coordinator refuses such an address (4003).
  sentBelowMinimum,
}

/// A payout decoded and checked against what the coordinator asks ([PayoutAsk.check]): what the panel shows before the user confirms, and the only input of `SubmitPayoutUsecase.execute`, which signs [text] and nothing else.
///
/// Only [PayoutAsk.check] builds one. Its [toString] names no part of the text.
@immutable
sealed class CheckedPayout {
  /// What the user gave, as given: checked again against a fresh read before it is signed.
  final PayoutDestination destination;

  /// The trade it was checked for.
  final RobotSlot robot;
  final int orderId;
  final RobosatsNetwork network;

  /// Every warning of the status it was checked against: information, shown with it.
  final List<TradeWarning> statusWarnings;

  /// Its own warnings.
  final List<PayoutWarning> warnings;

  const CheckedPayout._({
    required this.destination,
    required this.robot,
    required this.orderId,
    required this.network,
    required this.statusWarnings,
    required this.warnings,
  });

  /// The exact text decoded and shown: what is signed.
  String get text;

  /// Whether it was checked for the trade of [record].
  bool isFor(TradeRecord record) =>
      robot == record.robot &&
      orderId == record.orderId &&
      network == record.network;

  /// Whether [fresh], the same destination checked again, shows the user nothing that this one did not: the same text and figures, and no warning this one did not carry.
  bool showsSameAs(CheckedPayout fresh);

  bool _coversWarningsOf(CheckedPayout fresh) {
    final kinds = {for (final w in statusWarnings) w.runtimeType};
    return fresh.statusWarnings.every((w) => kinds.contains(w.runtimeType)) &&
        fresh.warnings.every(warnings.contains);
  }
}

/// A Lightning invoice checked for a payout.
final class CheckedPayoutInvoice extends CheckedPayout {
  @override
  final String text;

  /// What the invoice says, decoded from [text].
  final Bolt11Invoice facts;

  /// The buyer's amount it was checked against (`trade_satoshis`).
  final Sats buyerSats;

  /// The routing budget sent with it.
  final RoutingBudgetPpm budget;

  const CheckedPayoutInvoice._({
    required super.destination,
    required super.robot,
    required super.orderId,
    required super.network,
    required this.text,
    required this.facts,
    required this.buyerSats,
    required this.budget,
    required super.statusWarnings,
    required super.warnings,
  }) : super._();

  /// The invoice's own amount, which is what the coordinator pays.
  Sats get amount => facts.amount;


  /// When the invoice expires.
  DateTime get expiresAt => facts.expiresAt;

  @override
  bool showsSameAs(CheckedPayout fresh) =>
      fresh is CheckedPayoutInvoice &&
      fresh.text == text &&
      fresh.network == network &&
      fresh.amount == amount &&
      fresh.buyerSats == buyerSats &&
      fresh.budget == budget &&
      _coversWarningsOf(fresh);

  @override
  String toString() =>
      'CheckedPayoutInvoice(${network.name}, ${statusWarnings.length + warnings.length} warnings)';
}

/// An on-chain address checked for a payout through the coordinator's swap.
final class CheckedPayoutAddress extends CheckedPayout {
  final BitcoinAddress address;
  final MiningFeeRate rate;

  /// The figures shown: the buyer's amount the swap starts from, the swap fee, and what the address receives ([OnchainAsk.sentSatsFor]).
  final Sats invoiceAmount;
  final double swapFeePercent;
  final int sentSats;

  const CheckedPayoutAddress._({
    required super.destination,
    required super.robot,
    required super.orderId,
    required super.network,
    required this.address,
    required this.rate,
    required this.invoiceAmount,
    required this.swapFeePercent,
    required this.sentSats,
    required super.statusWarnings,
    required super.warnings,
  }) : super._();

  @override
  String get text => address.text;

  @override
  bool showsSameAs(CheckedPayout fresh) =>
      fresh is CheckedPayoutAddress &&
      fresh.text == text &&
      fresh.network == network &&
      fresh.rate == rate &&
      fresh.invoiceAmount == invoiceAmount &&
      fresh.swapFeePercent == swapFeePercent &&
      fresh.sentSats == sentSats &&
      _coversWarningsOf(fresh);

  @override
  String toString() =>
      'CheckedPayoutAddress(${network.name}, ${statusWarnings.length + warnings.length} warnings)';
}

/// Why a payout cannot be checked, so not signed: a type for each reason, which the panel words (#91), never a coordinator's text or the pasted text.
sealed class PayoutCheckRefusal extends Failure {
  const PayoutCheckRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The status given is not one a read stored with its order: wait for the next read of the trade.
final class PayoutNeedsARead extends PayoutCheckRefusal {
  const PayoutNeedsARead();
}

/// The coordinator asks for no payout of this robot at this status: not its buyer, another order, or a step that takes none (an invoice at 6, 8, or 15 once the failed invoice expired; an address at 6 or 8), as when a payout was already given.
final class PayoutNotAsked extends PayoutCheckRefusal {
  const PayoutNotAsked();
}

/// An address at a step whose order offers no on-chain payout (`swap_allowed` false, or no swap fee given): only an invoice can be given.
final class PayoutOnchainNotOffered extends PayoutCheckRefusal {
  const PayoutOnchainNotOffered();
}

/// The order gives no amount to check against, or one beyond the read bounds.
final class PayoutAmountUnknown extends PayoutCheckRefusal {
  const PayoutAmountUnknown();
}

/// The text is not a BOLT11 invoice this app can read: [reason] says why.
final class PayoutInvoiceUnreadable extends PayoutCheckRefusal {
  final Bolt11Refusal reason;

  const PayoutInvoiceUnreadable(this.reason);

  @override
  String toString() => 'PayoutInvoiceUnreadable($reason)';
}

/// An invoice of another network than the trade's (`lnbc` on mainnet, `lntb` on testnet; signet, regtest and any other prefix are another network).
final class PayoutInvoiceOfAnotherNetwork extends PayoutCheckRefusal {
  const PayoutInvoiceOfAnotherNetwork();
}

/// An invoice for another amount than the one asked ([PayoutAsk.invoiceSatsFor] its routing budget).
final class PayoutInvoiceAmountNotAsked extends PayoutCheckRefusal {
  const PayoutInvoiceAmountNotAsked();
}

/// An invoice already expired.
final class PayoutInvoiceExpired extends PayoutCheckRefusal {
  const PayoutInvoiceExpired();
}

/// The text is not an on-chain address of the trade's network that the coordinator can pay: [reason] says why ([BitcoinAddress.check]).
final class PayoutAddressUnusable extends PayoutCheckRefusal {
  final PayoutDestinationFailure reason;

  const PayoutAddressUnusable(this.reason);

  @override
  String toString() => 'PayoutAddressUnusable($reason)';
}
