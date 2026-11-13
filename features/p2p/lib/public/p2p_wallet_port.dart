import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../src/domain/checked_bolt11_invoice.dart';

/// What the wallet of the app lends the P2P feature so that a bond or an escrow can be paid from its Instant Payments wallet without leaving the trade screen (#100, design note § 2.1 and § 3.9).
///
/// The shell implements it in `lib/features/p2p_wallet` and passes it to `P2pFeature.setup` in the foreground composition only; the feature works without it.
/// This contract moves no money: it reads the balance and asks the swap service for a quote. Paying (`pay`, `watch`, `find`) is added by a later pull request, reviewed as money code.
/// Only the trade use cases (`lib/src/domain/usecases/trade/`) may reach it: `wallet_port_architecture_test.dart`.
/// Its types carry no wallet type and no text: a refusal is a type, with at most a number.
abstract interface class P2pWalletPort {
  /// What the Instant Payments wallet on [network] can spend now: at once, then again each time the app finishes a sync of that wallet.
  ///
  /// It reads the wallet's own records and starts no sync. A refusal ends the stream: [P2pWalletNoInstantWallet], [P2pWalletUnavailable] or [P2pWalletWrongNetwork] (the wallet is on the other network).
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(RobosatsNetwork network);

  /// The swap service's quote for paying exactly [invoice] from the Instant Payments wallet, or why it cannot.
  ///
  /// It runs only when called, and sends the swap service, over the network the wallet uses for it (clearnet, not Tor), the invoice's amount and the route (Liquid to Lightning), never the invoice; nothing is created at the service, nothing is signed, nothing is broadcast.
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(
    CheckedBolt11Invoice invoice,
  );
}

/// The swap service's quote for paying [invoice] from the Instant Payments wallet, with the wallet's estimate of its network fee.
///
/// The service gives no expiry for a quote: [quotedAt] is when the wallet received it, so that a payment can refuse a quote it finds too old.
/// A payment made from this quote is bound to it: the same [invoice], at most [payin] sent to the service, and at most [total] leaving the wallet.
/// Its [toString] names none of its amounts.
final class P2pWalletQuote {
  /// The invoice quoted, the one a payment from this quote must pay.
  final CheckedBolt11Invoice invoice;

  /// What the wallet sends to the swap service, which pays the invoice from it: the invoice's amount and the service's fee.
  final Sats payin;

  /// The service's fee rate as it gives it, in basis points (1 % is 100), the sum of the fees it lists.
  final int serviceFeeBasisPoints;

  /// The wallet's estimate of the Liquid network fee of sending [payin], at the rate the wallet uses for every Liquid send.
  final Sats networkFee;

  /// What the Instant Payments wallet could spend when quoted.
  final Sats balance;

  /// When the wallet received the quote.
  final DateTime quotedAt;

  /// Throws an [ArgumentError] when [payin] is less than the invoice's amount, [serviceFeeBasisPoints] is negative, or the [total] exceeds the [balance]: the implementation of the port refuses these before it builds a quote.
  P2pWalletQuote({
    required this.invoice,
    required this.payin,
    required this.serviceFeeBasisPoints,
    required this.networkFee,
    required this.balance,
    required this.quotedAt,
  }) {
    if (payin.value < invoice.amount.value) {
      throw ArgumentError('A payin is never less than the invoice it pays');
    }
    if (serviceFeeBasisPoints < 0) {
      throw ArgumentError('A fee rate is never negative');
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
sealed class P2pWalletRefusal extends Failure {
  const P2pWalletRefusal();
}

/// The invoice's amount is under the swap service's minimum, which it gives most of the time ([minimum], as the service states it).
final class P2pWalletUnderMinimum extends P2pWalletRefusal {
  final Sats? minimum;

  const P2pWalletUnderMinimum({this.minimum});
}

/// The invoice's amount is over the swap service's maximum, which it gives most of the time ([maximum], as the service states it).
final class P2pWalletOverMaximum extends P2pWalletRefusal {
  final Sats? maximum;

  const P2pWalletOverMaximum({this.maximum});
}

/// The swap service refused the amount as out of its limits without saying which one.
final class P2pWalletOutsideServiceLimits extends P2pWalletRefusal {
  const P2pWalletOutsideServiceLimits();
}

/// The Instant Payments wallet has [available], less than the [needed] that paying would take (at least that much, when the network fee could not be estimated).
final class P2pWalletNotEnoughBalance extends P2pWalletRefusal {
  final Sats available;
  final Sats needed;

  const P2pWalletNotEnoughBalance({
    required this.available,
    required this.needed,
  });
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

/// The swap service did not answer: no connection, or no answer in time.
final class P2pWalletServiceUnreachable extends P2pWalletRefusal {
  const P2pWalletServiceUnreachable();
}

/// The swap service asked to wait before asking again ([retryAfter], when it says how long).
final class P2pWalletServiceBusy extends P2pWalletRefusal {
  final Duration? retryAfter;

  const P2pWalletServiceBusy({this.retryAfter});
}

/// The swap service refused, or answered what the wallet cannot use (a quote that does not match the invoice included).
final class P2pWalletServiceRefused extends P2pWalletRefusal {
  const P2pWalletServiceRefused();
}
