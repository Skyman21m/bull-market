import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../../public/p2p_wallet_port.dart';
import 'escrow_contract.dart';
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

/// The status is not the bond step marked stored: a payment is offered only from a stored `WaitingForTakerBond`, or for an order made here a stored `WaitingForMakerBond` (#180) (`AGENTS.md`, « Rules for the screens (#88) »), and the read just before the payment no longer shows one; also every step this wallet does not pay for the trade's side (the escrow's instance at a maker bond, the bond's at an escrow).
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

/// A maker seller's escrow (#187): the earlier escrows of the order, read again under the payment's lock, are more out than the confirmation showed (more sats not back yet, or an escrow the coordinator kept since): nothing was paid, and the confirmation is to be made again with [contract], what they are now (the owner's decision of 2026-11-19: a new confirmation, not a lock; the next one pays).
final class BondPayConfirmAgain extends BondPayRefusal {
  final EscrowContract contract;

  const BondPayConfirmAgain(this.contract);

  @override
  String toString() => 'BondPayConfirmAgain(${contract.take})';
}

/// A maker seller's escrow (#187) whose payment hash was already presented: an escrow of an earlier contract (the trail's `earlier_escrows`), another payment recorded for the trade (another contract's escrow, or its bond), or a payment recorded for another trade, whether or not it was ever paid. Never paid from this wallet; the state machine refuses the first as a breach too (`EscrowNotOfThisContract`), and the database refuses a payment hash recorded twice (`trade_payments_hash_once`).
final class BondPayEscrowSeenBefore extends BondPayRefusal {
  const BondPayEscrowSeenBefore();
}

/// A maker seller's escrow (#187) whose confirmation did not state the contract the trail now stands at: no contract was confirmed, or the confirmed one is not the trail's read again under the payment's lock. Nothing was paid; a new confirmation is needed.
final class BondPayContractNotConfirmed extends BondPayRefusal {
  const BondPayContractNotConfirmed();
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

/// Where the escrow this wallet was asked to pay for one contract of an order made here stands (#187): the contract ([take]) and the payment's follow ([watch]), as [BondPaymentWatch] says it for the current one.
@immutable
final class EscrowPaymentOfContract {
  final int take;
  final BondPaymentWatch watch;

  const EscrowPaymentOfContract(this.take, this.watch);

  @override
  String toString() => 'EscrowPaymentOfContract($take, $watch)';
}

/// Where every escrow this wallet was asked to pay for an order made here stands, contract by contract (#187, design note § 6 row 13): an escrow paid for contract n stays followed once the trail moved to the next contract, and once the trade ended.
@immutable
sealed class EscrowPaymentsWatch {
  const EscrowPaymentsWatch();
}

/// Each escrow recorded for the trade, by contract, oldest first: empty when none was asked of the wallet from this device.
final class EscrowPaymentsFollowed extends EscrowPaymentsWatch {
  final List<EscrowPaymentOfContract> escrows;

  EscrowPaymentsFollowed(Iterable<EscrowPaymentOfContract> escrows)
    : escrows = List.unmodifiable(escrows);

  @override
  String toString() => 'EscrowPaymentsFollowed($escrows)';
}

/// The trade's records of its payments could not be read ([failure]): nothing is said of an escrow.
final class EscrowPaymentsUnreadable extends EscrowPaymentsWatch {
  final Failure failure;

  const EscrowPaymentsUnreadable(this.failure);

  @override
  String toString() => 'EscrowPaymentsUnreadable($failure)';
}
