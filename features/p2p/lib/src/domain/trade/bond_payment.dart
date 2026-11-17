import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../../public/p2p_wallet_port.dart';
import 'wallet_payment.dart';

/// Why the bond of a trade was not quoted or paid from the wallet (#100): a type for each reason, which the screen words; nothing was sent to the wallet's swap service for these, but [BondPayWalletRefused] says what the wallet itself answered.
@immutable
sealed class BondPayRefusal extends Failure {
  const BondPayRefusal();

  /// Whether the funds may have left the wallet: only when the wallet says so ([P2pWalletRefusal.fundsMayHaveMoved]).
  bool get fundsMayHaveMoved => false;

  @override
  String toString() => runtimeType.toString();
}

/// The status is not the bond step marked stored: a payment is offered only from a stored `WaitingForTakerBond`, or for an order made here a stored `WaitingForMakerBond` (#180) (`AGENTS.md`, « Rules for the screens (#88) »), and the read just before the payment no longer shows one; also every step this wallet does not pay for the trade's side (a maker seller's escrow before #187).
final class BondPayNotAtBondStep extends BondPayRefusal {
  const BondPayNotAtBondStep();
}

/// `walletPaymentFor` does not offer the wallet for the invoice of the status ([reason]): only « Pay with another wallet » stays, as the invoice's warnings allow.
final class BondPayNotOffered extends BondPayRefusal {
  final WalletPaymentRefusal reason;

  const BondPayNotOffered(this.reason);

  @override
  String toString() => 'BondPayNotOffered(${reason.name})';
}

/// The invoice the read just before the payment offers is not the one quoted and confirmed (another payment hash, or another text): a new quote and a new confirmation are needed.
final class BondPayInvoiceChanged extends BondPayRefusal {
  const BondPayInvoiceChanged();
}

/// The read just before the payment was superseded twice by a read that left before it (#141), which does not happen while the watch sends no read during the payment's read: nothing was paid, and the order did not necessarily move on.
final class BondPayReadSuperseded extends BondPayRefusal {
  const BondPayReadSuperseded();
}

/// The order could not be read again from the coordinator just before the payment ([failure]): nothing was paid.
final class BondPayTradeUnavailable extends BondPayRefusal {
  final Failure failure;

  const BondPayTradeUnavailable(this.failure);

  @override
  String toString() => 'BondPayTradeUnavailable($failure)';
}

/// The trade's records could not be read ([failure]): nothing was asked of the coordinator nor paid.
final class BondPayRecordsUnreadable extends BondPayRefusal {
  final Failure failure;

  const BondPayRecordsUnreadable(this.failure);

  @override
  String toString() => 'BondPayRecordsUnreadable($failure)';
}

/// The start of the payment could not be written before the wallet was asked: nothing was paid, since a payment is never started without its record (design note § 3.5).
final class BondPayNotRecorded extends BondPayRefusal {
  const BondPayNotRecorded();
}

/// The wallet refused ([refusal]): nothing left it, but for [P2pWalletBroadcastUnknown], whose payment is followed.
final class BondPayWalletRefused extends BondPayRefusal {
  final P2pWalletRefusal refusal;

  const BondPayWalletRefused(this.refusal);

  @override
  bool get fundsMayHaveMoved => refusal.fundsMayHaveMoved;

  @override
  String toString() => 'BondPayWalletRefused($refusal)';
}

/// Where the payment of a trade's bond from the wallet stands, as the screen follows it (#100).
@immutable
sealed class BondPaymentWatch {
  const BondPaymentWatch();
}

/// No payment of the bond was asked of the wallet from this device, or the wallet has none for its invoice (an attempt stopped before the wallet started it).
final class BondPaymentNone extends BondPaymentWatch {
  const BondPaymentNone();

  @override
  String toString() => 'BondPaymentNone';
}

/// The wallet's payment of the bond, and where it stands.
final class BondPaymentFollowed extends BondPaymentWatch {
  final P2pWalletPayment payment;
  final P2pWalletPaymentProgress progress;

  const BondPaymentFollowed(this.payment, this.progress);

  @override
  String toString() => 'BondPaymentFollowed($progress)';
}

/// The records, or the wallet's, could not be read: nothing is said of a payment, and nothing is paid.
final class BondPaymentUnreadable extends BondPaymentWatch {
  final Failure failure;

  const BondPaymentUnreadable(this.failure);

  @override
  String toString() => 'BondPaymentUnreadable($failure)';
}
