import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../src/domain/checked_bolt11_invoice.dart';

/// What the wallet of the app lends the P2P feature so that a bond or an escrow can be paid from its Instant Payments wallet without leaving the trade screen (#100, design note § 2.1 and § 3.9).
///
/// The shell implements it in `lib/features/p2p_wallet` and passes it to `P2pFeature.setup` in the foreground composition only; the feature works without it.
/// It reads the balance, asks the swap service for a quote, and pays: [payInvoice] moves money and triggers a signature, and is reviewed as money code (and key material). [watchPayment] and [findPayment] only read what the wallet recorded.
/// Only the trade use cases (`lib/src/domain/usecases/trade/`) may reach it: `wallet_port_architecture_test.dart`.
/// Its types carry no wallet type and no text: a refusal is a type, with at most a number; a payment is an opaque handle.
abstract interface class P2pWalletPort {
  /// What the Instant Payments wallet on [network] can spend now: at once, then again each time the app finishes a sync of that wallet.
  ///
  /// It reads the wallet's own records and starts no sync. A refusal ends the stream: [P2pWalletNoInstantWallet], [P2pWalletUnavailable] or [P2pWalletWrongNetwork] (the wallet is on the other network).
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(
    RobosatsNetwork network,
  );

  /// The swap service's quote for paying exactly [invoice] from the Instant Payments wallet, or why it cannot.
  ///
  /// It runs only when called, and only once the invoice is unexpired, the wallet on its network and its balance at least the invoice's amount. Nothing is created at the service, nothing is signed, nothing is broadcast.
  /// What the service learns, since P2P otherwise talks only over Tor: one HTTPS POST over clearnet, through the wallet's own client, to the wallet's swap service (its staging host on testnet), a JSON-RPC `getBestSwapOption` carrying the invoice's amount, `isInAmountFixed: false` and the two networks; never the invoice, an address or anything of the trade. The request bears no API key and the default Dart user agent, and the user's IP address. Its JSON-RPC id is `mobile-<microsecond timestamp>-<counter>`, the counter shared, for the life of the app, with the wallet's own calls to the service, which poll its swap orders: so the service can tie a quote to the user's other swap orders. And since a bond's amount follows from an order of the public book, a quote just before a take lets the service's operator guess which order this address is about to take.
  /// Side effects in the wallet: the quote waits behind the wallet's own calls to the service, one at a time; an answer HTTP 418 sets the wallet's « app update required » flag, which stops its swaps until the app is updated.
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(
    CheckedBolt11Invoice invoice,
  );

  /// Pays [invoice] from the Instant Payments wallet within [accepted], the quote the user confirmed, and returns once the funding transaction is broadcast; or a refusal.
  ///
  /// [accepted] must be a quote this wallet gave, from the same Instant Payments wallet, for this very invoice (same string, amount, network and payment hash), not used before and not older than the wallet allows: a quote is consumed by the first call that presents it, whatever its outcome, so that each payment follows one confirmation (#88). The invoice given is the one the latest status offered (`walletPaymentFor`); its [CheckedBolt11Invoice.payableUntil] is the one taken.
  /// **Never twice.** An attempt that moved nothing may be tried again, after a new quote and a new confirmation: an invoice is paid again only while every earlier order of the wallet for it (its text, or this feature's order of the same payment hash; any wallet, any purpose) is provably unspent, nothing signed and nothing broadcast. As soon as one may have moved funds (signed, broadcast or after) or cannot be read, the invoice is refused with [P2pWalletPaymentExists] (or [P2pWalletUnavailable]), and is paid with another wallet or replaced by a new invoice: the swap service is paid by a Liquid transaction of this wallet, and a second transaction would send the amount twice, its return depending on the service's refund. Nothing retries by itself. Everything that can be known before the order is created is checked first (the quote, the invoice's time, the wallet, the wallet's own reading of the invoice, the earlier orders, the balance and the coins against the total accepted, the fee); what only the order says (its payin) can still refuse it after its creation, with nothing moved. Two calls at once run one after the other.
  /// What it sends the swap service, through the wallet's own client over clearnet: a JSON-RPC `createOrderSwap` with the invoice itself (its payee, amount, payment hash, description and expiry), the invoice's amount as the amount to pay out with `isInAmountFixed: false`, the two networks, an address of the Instant Payments wallet as the refund destination, and a request id `mobile-<random hex>`; the payin the user accepted stays on the device. Then the funding transaction reaches the Liquid network through the wallet's Electrum servers. #109 tracks the privacy of these calls.
  /// **Trust.** The swap is custodial, as for the wallet's own Lightning sends: the device holds no HTLC and no refund key; once the funding is broadcast, the swap service holds the payin and may pay the invoice, refund the wallet's address, or keep it. The cap bounds what it can hold: the payin accepted.
  /// Every refusal but one means nothing left the wallet ([P2pWalletRefusal.fundsMayHaveMoved] is false); [P2pWalletBroadcastUnknown] means the broadcast was tried and its outcome is unknown: its payment is then followed with [watchPayment] and found again with [findPayment].
  /// It never resumes or retries a payment left halfway by an earlier run: such a payment is reported by [findPayment] and [watchPayment] as it stands. Each step is bounded in time; a step that does not answer in time ends the call (nothing moved before the broadcast, [P2pWalletBroadcastUnknown] after it), so that the next payment does not wait behind it.
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payInvoice(
    CheckedBolt11Invoice invoice, {
    required P2pWalletQuote accepted,
  });

  /// The progress of [payment], at once and then each time the wallet records a change (its own watcher asks the swap service while the app is open); it starts nothing and asks the service nothing.
  ///
  /// A refusal ends the stream: [P2pWalletUnavailable] when the payment's record cannot be read or is not this payment.
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watchPayment(
    P2pWalletPayment payment,
  );

  /// The payment of [paymentHash] that this feature started, in any state (a terminal one included), with its progress; `null` when it started none, so that a restart never pays an invoice twice.
  ///
  /// It reads the wallet's records only, and fails closed: [P2pWalletUnavailable] when the records, or the invoice of any order this feature made, cannot be read, never `null`. An order of the invoice made by the wallet's own screens is not this feature's and is not given (but [payInvoice] still refuses that invoice). When several were started for one hash, which [payInvoice] prevents, the latest is given.
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> findPayment(
    String paymentHash,
  );
}

/// A payment the wallet started: the swap's local id in the wallet's records and the invoice's payment hash. No key, address or transaction id.
///
/// Opaque to the feature, which keeps it (or finds it again by its hash) to follow the payment. Its [toString] names neither field.
final class P2pWalletPayment {
  /// The wallet's local id of the swap that pays the invoice.
  final String id;

  /// The payment hash of the invoice it pays.
  final String paymentHash;

  const P2pWalletPayment({required this.id, required this.paymentHash});

  @override
  bool operator ==(Object other) =>
      other is P2pWalletPayment &&
      other.id == id &&
      other.paymentHash == paymentHash;

  @override
  int get hashCode => Object.hash(id, paymentHash);

  @override
  String toString() => 'P2pWalletPayment';
}

/// A payment [findPayment] found, with its progress when it was read.
final class P2pWalletPaymentFound {
  final P2pWalletPayment payment;
  final P2pWalletPaymentProgress progress;

  const P2pWalletPaymentFound({required this.payment, required this.progress});

  @override
  String toString() => 'P2pWalletPaymentFound($progress)';
}

/// What the wallet knows of the funds of a payment that ended without paying: whether the funding transaction left the wallet.
enum P2pWalletFunds {
  /// Nothing was signed for it: nothing left the wallet.
  notSent,

  /// A funding transaction was signed and saved, but no broadcast was recorded: it may have left the wallet.
  maybeSent,

  /// The funding transaction was broadcast: the funds left the wallet, and only the swap service can return them.
  sent,
}

/// Where a payment stands, as the wallet records it: what a user can be told, without any text of the swap service.
///
/// [fundsMayHaveLeft] says whether the funding transaction may have left the wallet.
sealed class P2pWalletPaymentProgress {
  const P2pWalletPaymentProgress();

  /// Whether the funds may have left the wallet at this point.
  bool get fundsMayHaveLeft;

  /// Whether nothing more is to come for the user: the invoice was paid, the refund arrived, or the payment ended with nothing sent.
  ///
  /// False while the payment goes on, and for an expired or failed payment whose funds may have left the wallet: a refund may be due, and the wallet stops following such an order (only the swap service's support can tell what became of the funds).
  bool get isFinal;

  @override
  String toString() => runtimeType.toString();
}

/// The swap is being created or prepared: nothing has left the wallet.
final class P2pWalletPaymentPreparing extends P2pWalletPaymentProgress {
  const P2pWalletPaymentPreparing();

  @override
  bool get fundsMayHaveLeft => false;

  @override
  bool get isFinal => false;
}

/// The funding transaction is signed and saved, but was not sent: nothing has left the wallet. After a restart, the payment was interrupted before its broadcast, and nothing finishes it.
final class P2pWalletPaymentSigned extends P2pWalletPaymentProgress {
  const P2pWalletPaymentSigned();

  @override
  bool get fundsMayHaveLeft => false;

  @override
  bool get isFinal => false;
}

/// The funding transaction was being broadcast and the outcome is unknown: the funds may have left the wallet. The wallet's watcher settles it when the swap service sees the funding (or not).
final class P2pWalletPaymentBroadcastUnknown extends P2pWalletPaymentProgress {
  const P2pWalletPaymentBroadcastUnknown();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => false;
}

/// The funding transaction was broadcast: the funds left the wallet for the swap service, which has not yet reported receiving them.
final class P2pWalletPaymentSent extends P2pWalletPaymentProgress {
  const P2pWalletPaymentSent();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => false;
}

/// The swap service received the funds and is paying the invoice: a hold invoice stays pending as long as the coordinator holds it, and the funds stay with the service meanwhile.
final class P2pWalletPaymentPending extends P2pWalletPaymentProgress {
  const P2pWalletPaymentPending();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => false;
}

/// The swap service holds the payment for a manual review; the funds are with it.
final class P2pWalletPaymentUnderReview extends P2pWalletPaymentProgress {
  const P2pWalletPaymentUnderReview();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => false;
}

/// The invoice was paid and settled: for a bond, the coordinator kept it; for an escrow, the trade ended normally.
final class P2pWalletPaymentPaid extends P2pWalletPaymentProgress {
  const P2pWalletPaymentPaid();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => true;
}

/// The invoice was not paid after the funds reached the swap service (the payee cancelled a hold invoice, or the service failed): the service is to refund the wallet's refund address.
final class P2pWalletPaymentRefundPending extends P2pWalletPaymentProgress {
  const P2pWalletPaymentRefundPending();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => false;
}

/// The swap service refunded the funds, less its fees, to the wallet's refund address.
final class P2pWalletPaymentRefunded extends P2pWalletPaymentProgress {
  const P2pWalletPaymentRefunded();

  @override
  bool get fundsMayHaveLeft => true;

  @override
  bool get isFinal => true;
}

/// The swap expired before it was paid; [funds] says whether its funding left the wallet (then only the swap service can return it).
final class P2pWalletPaymentExpired extends P2pWalletPaymentProgress {
  final P2pWalletFunds funds;

  const P2pWalletPaymentExpired(this.funds);

  @override
  bool get fundsMayHaveLeft => funds != P2pWalletFunds.notSent;

  @override
  bool get isFinal => funds == P2pWalletFunds.notSent;

  @override
  String toString() => 'P2pWalletPaymentExpired(${funds.name})';
}

/// The swap failed with no broadcast recorded; [funds] says whether a funding transaction was signed and may have left the wallet. A failure after a recorded broadcast is [P2pWalletPaymentRefundPending].
final class P2pWalletPaymentFailed extends P2pWalletPaymentProgress {
  final P2pWalletFunds funds;

  const P2pWalletPaymentFailed(this.funds);

  @override
  bool get fundsMayHaveLeft => funds != P2pWalletFunds.notSent;

  @override
  bool get isFinal => funds == P2pWalletFunds.notSent;

  @override
  String toString() => 'P2pWalletPaymentFailed(${funds.name})';
}

/// The swap service's quote for paying [invoice] from the Instant Payments wallet, with the wallet's estimate of its network fee.
///
/// The service gives no expiry for a quote: [quotedAt] is when the wallet received it, so that a payment can refuse a quote it finds too old.
/// The service's fee is given as an amount, [serviceFee], the payin less the invoice's amount: the rate the service lists beside it is not carried, since it may not add up to that amount.
/// A payment made from this quote is bound to it: the same [invoice], at most [payin] sent to the service, and at most [total] leaving the wallet.
/// Its [toString] names none of its amounts.
final class P2pWalletQuote {
  /// The invoice quoted, the one a payment from this quote must pay.
  final CheckedBolt11Invoice invoice;

  /// What the wallet sends to the swap service, which pays the invoice from it: the invoice's amount and the service's fee.
  final Sats payin;

  /// The wallet's estimate of the Liquid network fee of sending [payin], at the rate the wallet uses for every Liquid send.
  final Sats networkFee;

  /// What the Instant Payments wallet could spend when quoted.
  final Sats balance;

  /// When the wallet received the quote.
  final DateTime quotedAt;

  /// Throws an [ArgumentError] when [payin] is less than the invoice's amount or the [total] exceeds the [balance]: the implementation of the port refuses these before it builds a quote.
  P2pWalletQuote({
    required this.invoice,
    required this.payin,
    required this.networkFee,
    required this.balance,
    required this.quotedAt,
  }) {
    if (payin.value < invoice.amount.value) {
      throw ArgumentError('A payin is never less than the invoice it pays');
    }
    if (total.value > balance.value) {
      throw ArgumentError('A quote never exceeds the balance');
    }
  }

  /// The amount of the invoice.
  Sats get amount => invoice.amount;

  /// The swap service's fee: what it keeps of [payin].
  Sats get serviceFee => Sats(payin.value - invoice.amount.value);

  /// What leaves the wallet: [payin] and [networkFee].
  Sats get total => Sats(payin.value + networkFee.value);

  /// What stays in the Instant Payments wallet once [total] has left it.
  Sats get remaining => Sats(balance.value - total.value);

  @override
  String toString() => 'P2pWalletQuote';
}

/// Why the wallet cannot quote or pay an invoice, or read its balance: a type, never a text of the service or of an exception (design note § 3.10).
///
/// Every refusal means that nothing left the wallet, but [P2pWalletBroadcastUnknown]: [fundsMayHaveMoved] tells them apart without reading any text.
sealed class P2pWalletRefusal extends Failure {
  const P2pWalletRefusal();

  /// Whether the funds may have left the wallet: only when a broadcast was tried and its outcome is unknown.
  bool get fundsMayHaveMoved => false;
}

/// The invoice's amount is under the swap service's minimum, which it gives most of the time ([minimum], as the service states it, when it is a plausible amount of bitcoin).
final class P2pWalletUnderMinimum extends P2pWalletRefusal {
  final Sats? minimum;

  const P2pWalletUnderMinimum({this.minimum});
}

/// The invoice's amount is over the swap service's maximum, which it gives most of the time ([maximum], as the service states it, when it is a plausible amount of bitcoin).
final class P2pWalletOverMaximum extends P2pWalletRefusal {
  final Sats? maximum;

  const P2pWalletOverMaximum({this.maximum});
}

/// The swap service refused the amount as out of its limits without saying which one.
final class P2pWalletOutsideServiceLimits extends P2pWalletRefusal {
  const P2pWalletOutsideServiceLimits();
}

/// The Instant Payments wallet has [available], less than the [needed] that paying would take.
///
/// [needed] is always above [available]; it is a lower bound when the wallet could not price the network fee (it then says only that the payin and the fee are more than the balance).
final class P2pWalletNotEnoughBalance extends P2pWalletRefusal {
  final Sats available;
  final Sats needed;

  /// Throws an [ArgumentError] unless [needed] is above [available].
  P2pWalletNotEnoughBalance({required this.available, required this.needed}) {
    if (needed.value <= available.value) {
      throw ArgumentError('Not enough means needing more than there is');
    }
  }
}

/// The Instant Payments wallet holds too many coins to spend them in one transaction: the wallet's own consolidation comes first.
final class P2pWalletNeedsConsolidation extends P2pWalletRefusal {
  const P2pWalletNeedsConsolidation();
}

/// The app has no Instant Payments wallet.
final class P2pWalletNoInstantWallet extends P2pWalletRefusal {
  const P2pWalletNoInstantWallet();
}

/// The Instant Payments wallet cannot be read, or cannot pay without a device of its own.
final class P2pWalletUnavailable extends P2pWalletRefusal {
  const P2pWalletUnavailable();
}

/// The Instant Payments wallet is on the other network than the invoice or the trade.
final class P2pWalletWrongNetwork extends P2pWalletRefusal {
  const P2pWalletWrongNetwork();
}

/// The invoice does not read again as the trade screen showed it.
final class P2pWalletInvoiceUnreadable extends P2pWalletRefusal {
  const P2pWalletInvoiceUnreadable();
}

/// The invoice has expired.
final class P2pWalletInvoiceExpired extends P2pWalletRefusal {
  const P2pWalletInvoiceExpired();
}

/// The swap service did not answer: no connection, no answer in time, or an HTTP status other than 2xx, 418 and 429 (which the wallet's client reads as a network failure).
final class P2pWalletServiceUnreachable extends P2pWalletRefusal {
  const P2pWalletServiceUnreachable();
}

/// The swap service asked to wait before asking again ([retryAfter], when it says how long: never negative, at most ten minutes).
final class P2pWalletServiceBusy extends P2pWalletRefusal {
  final Duration? retryAfter;

  const P2pWalletServiceBusy({this.retryAfter});
}

/// The swap service refused, or answered what the wallet cannot use (a quote that does not match the invoice included).
final class P2pWalletServiceRefused extends P2pWalletRefusal {
  const P2pWalletServiceRefused();
}

/// The invoice, or the coordinator's step, stops being payable too soon for this wallet to pay it in time through its swap service.
final class P2pWalletInvoiceExpiresTooSoon extends P2pWalletRefusal {
  const P2pWalletInvoiceExpiresTooSoon();
}

/// The quote presented cannot be paid: it was not given by this wallet, it was used already, it is too old, or it is for another invoice. A new quote and a new confirmation are needed.
final class P2pWalletQuoteStale extends P2pWalletRefusal {
  const P2pWalletQuoteStale();
}

/// The swap service asked a payin above the one the user accepted, or the network fee came out above the one quoted: nothing was sent.
///
/// When the fee is found too high before the order is created, nothing reaches the service. When it is the order's payin, the order exists, unspent, and is left at the service. Either way the invoice may be quoted and confirmed again ([P2pWalletPort.payInvoice]); while the earlier order is active, the wallet's store answers it again and its payin must then fit the new quote.
final class P2pWalletQuoteChanged extends P2pWalletRefusal {
  const P2pWalletQuoteChanged();
}

/// This wallet has a payment of this invoice that may have moved funds, so it never pays the invoice again ([P2pWalletPort.payInvoice]): an order signed (its funding saved, not sent), « broadcast unknown », broadcast, paid, refunded, under review, or an open order of the wallet's own screens.
///
/// [progress] is where the latest such order stands, so that the screen can tell « a signed payment of this invoice exists, nothing left this wallet: pay with another wallet » ([P2pWalletPaymentProgress.fundsMayHaveLeft] false) from « a payment of this invoice is on its way, or its funds are with the swap service » (true). [payment] is the handle to follow it, `null` when the order was made by the wallet's own screens (then [P2pWalletPort.findPayment] does not give it). This call itself moved nothing.
final class P2pWalletPaymentExists extends P2pWalletRefusal {
  final P2pWalletPaymentProgress progress;
  final P2pWalletPayment? payment;

  const P2pWalletPaymentExists({required this.progress, this.payment});
}

/// The funding transaction was being broadcast when something failed: it may have left the wallet. [payment] is followed with [P2pWalletPort.watchPayment]; nothing tries the broadcast again.
final class P2pWalletBroadcastUnknown extends P2pWalletRefusal {
  final P2pWalletPayment payment;

  const P2pWalletBroadcastUnknown(this.payment);

  @override
  bool get fundsMayHaveMoved => true;
}
