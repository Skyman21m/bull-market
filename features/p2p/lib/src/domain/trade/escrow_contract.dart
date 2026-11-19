import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../../public/p2p_wallet_port.dart';
import 'trade_payment.dart';

/// Whether an escrow this wallet paid is no longer held, as the wallet's records of its swap say (#187, design note `docs/design/phase-3-making-an-order.md` § 4.3, § 6 row 13): only a refund pending or done ([P2pWalletPaymentRefundPending], [P2pWalletPaymentRefunded]), or a payment that failed or expired with nothing sent ([P2pWalletPaymentFailed] or [P2pWalletPaymentExpired] with [P2pWalletFunds.notSent]).
///
/// Every other state counts as held: being prepared or signed (the wallet may still send it), broadcast or sent, pending at the service (the coordinator holds the hold invoice), under review, paid (the escrow settled: the funds are gone, not free), and a failure or an expiry whose funds may have left the wallet.
bool escrowNoLongerHeld(P2pWalletPaymentProgress progress) =>
    switch (progress) {
      P2pWalletPaymentRefundPending() || P2pWalletPaymentRefunded() => true,
      P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) ||
      P2pWalletPaymentExpired(funds: P2pWalletFunds.notSent) => true,
      P2pWalletPaymentPreparing() ||
      P2pWalletPaymentSigned() ||
      P2pWalletPaymentBroadcastUnknown() ||
      P2pWalletPaymentSent() ||
      P2pWalletPaymentPending() ||
      P2pWalletPaymentUnderReview() ||
      P2pWalletPaymentPaid() ||
      P2pWalletPaymentFailed() ||
      P2pWalletPaymentExpired() => false,
    };

/// Where the escrow of an earlier contract of an order made here stands, when this wallet was asked to pay it (a row of `trade_payments` of step `escrow` under that contract), as the wallet's records say at the moment of asking: what the confirmation of the next contract's escrow says, and what lets this wallet pay it ([held]).
@immutable
sealed class EarlierEscrow {
  /// The contract of that escrow (`TradeTrail.take` when it was paid).
  final int take;

  const EarlierEscrow(this.take);

  /// The state of the escrow of [record], an attempt recorded for an earlier contract, from what the wallet found for its payment hash ([found], `P2pWalletPort.findPayment`); [found] is not looked at when the record has no wallet id.
  ///
  /// [EarlierEscrowUnknown], which counts as held, when the record has no wallet id (an attempt the app was killed in, between its record and the wallet's answer, or one the wallet refused before giving one), when the wallet's records cannot be read, or when they hold no payment of that hash although the record names one. Otherwise the wallet's latest payment of that hash tells: the wallet pays an invoice again only while every earlier order of it is provably unspent (`P2pWalletPort.payInvoice`), so the latest is the one that may hold funds.
  static EarlierEscrow of(
    TradePaymentRecord record,
    Result<P2pWalletPaymentFound?, P2pWalletRefusal>? found,
  ) {
    if (record.walletPaymentId == null) {
      return EarlierEscrowUnknown(record.take);
    }
    return switch (found) {
      Ok(value: final payment?) when escrowNoLongerHeld(payment.progress) =>
        EarlierEscrowReleased(record.take, payment.progress),
      Ok(value: final payment?) => EarlierEscrowHeld(
        record.take,
        payment.progress,
      ),
      Ok(value: null) || Err() || null => EarlierEscrowUnknown(record.take),
    };
  }

  /// Whether this escrow may still be held: then this wallet pays no escrow of a later contract of the order, and only « Pay with another wallet » stays.
  bool get held;
}

/// An earlier escrow no longer held ([escrowNoLongerHeld]): refunded, its refund pending, or never sent.
final class EarlierEscrowReleased extends EarlierEscrow {
  final P2pWalletPaymentProgress progress;

  const EarlierEscrowReleased(super.take, this.progress);

  @override
  bool get held => false;

  @override
  String toString() => 'EarlierEscrowReleased($take, $progress)';
}

/// An earlier escrow the wallet's records show still held: sent, pending at the swap service, under review, paid, or failed or expired with funds that may have left the wallet.
final class EarlierEscrowHeld extends EarlierEscrow {
  final P2pWalletPaymentProgress progress;

  const EarlierEscrowHeld(super.take, this.progress);

  @override
  bool get held => true;

  @override
  String toString() => 'EarlierEscrowHeld($take, $progress)';
}

/// An earlier escrow whose state cannot be told: no wallet id recorded, the wallet's records unreadable, or no payment found for a recorded one. It counts as held.
final class EarlierEscrowUnknown extends EarlierEscrow {
  const EarlierEscrowUnknown(super.take);

  @override
  bool get held => true;

  @override
  String toString() => 'EarlierEscrowUnknown($take)';
}

/// The contract of a maker seller's escrow this wallet is asked to pay, and every escrow this wallet was asked to pay for the order's earlier contracts (#187, design note § 6 row 13): what its confirmation says (a new contract when [take] is above 0, and the state of each earlier escrow), and what the payment is made under.
///
/// The payment of a maker seller's escrow takes it back (`PayBondFromWalletUsecase.payBond`, `contract`): the payment goes on only for the very contract the confirmation stated, the trail read again under the payment's lock; and only while no earlier escrow is [EarlierEscrow.held], checked again then.
@immutable
final class EscrowContract {
  /// The contract of the escrow (`TradeTrail.take`): 0 for the order's first take.
  final int take;

  /// The escrows this wallet was asked to pay for the order's other contracts, by contract, oldest first.
  final List<EarlierEscrow> earlier;

  EscrowContract({required this.take, required Iterable<EarlierEscrow> earlier})
    : earlier = List.unmodifiable(earlier);

  /// Whether the order was taken again since its first take: the confirmation says this is a new contract.
  bool get isNew => take > 0;

  /// Whether an escrow of another contract paid from this wallet may still be held: then nothing is paid from this wallet, only « Pay with another wallet » stays.
  bool get earlierHeld => earlier.any((escrow) => escrow.held);

  @override
  String toString() => 'EscrowContract($take, $earlier)';
}
