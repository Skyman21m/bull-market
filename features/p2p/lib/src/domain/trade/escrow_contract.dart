import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../../../public/p2p_wallet_port.dart';
import 'trade_payment.dart';

/// Where an escrow this wallet was asked to pay for an earlier contract of an order made here stands, for the confirmation of the next contract's escrow (#187, the owner's decision of 2026-11-19: no lock, an alert): three cases the screen can say without being wrong.
enum EarlierEscrowCase {
  /// Back in the wallet, or never left: refunded, or an attempt with nothing sent (a failure or an expiry with nothing sent, or no order of this feature in the wallet's records). It does not count.
  back,

  /// Not back yet: every other state but [kept] — a refund pending (which Bull's own code does not take as final, `order_swap_record.dart:148-157`), an order being prepared or « creating » (with no limit of time), sent, pending at the swap service, under review, a failure or an expiry whose funds may have left, and a state that cannot be told. Its sats count in what is out of the wallet.
  notBack,

  /// Settled: the coordinator kept it (`P2pWalletPaymentPaid`), which is no delay. Said apart.
  kept,
}

/// The case of an escrow whose payment stands at [progress] in the wallet's records: [EarlierEscrowCase.back] only for a refund done or nothing sent, [EarlierEscrowCase.kept] for a payment settled, [EarlierEscrowCase.notBack] for everything else.
EarlierEscrowCase earlierEscrowCaseOf(P2pWalletPaymentProgress progress) =>
    switch (progress) {
      P2pWalletPaymentRefunded() => EarlierEscrowCase.back,
      P2pWalletPaymentFailed(funds: P2pWalletFunds.notSent) ||
      P2pWalletPaymentExpired(
        funds: P2pWalletFunds.notSent,
      ) => EarlierEscrowCase.back,
      P2pWalletPaymentPaid() => EarlierEscrowCase.kept,
      P2pWalletPaymentRefundPending() ||
      P2pWalletPaymentPreparing() ||
      P2pWalletPaymentSigned() ||
      P2pWalletPaymentBroadcastUnknown() ||
      P2pWalletPaymentSent() ||
      P2pWalletPaymentPending() ||
      P2pWalletPaymentUnderReview() ||
      P2pWalletPaymentFailed() ||
      P2pWalletPaymentExpired() => EarlierEscrowCase.notBack,
    };

/// An escrow this wallet was asked to pay for an earlier contract of an order made here (a row of `trade_payments` of step `escrow` under that contract), as the wallet's records say at the moment of asking.
@immutable
final class EarlierEscrow {
  /// The contract of that escrow (`TradeTrail.take` when it was paid).
  final int take;

  final EarlierEscrowCase state;

  /// Its sats, as this run of the app asked the wallet to pay them (the invoice's amount of the quote confirmed); `null` when this run did not pay it (the app started again since): `trade_payments` keeps no amount (schema 8), and the wallet's port gives none.
  final Sats? sats;

  /// Where the wallet's records say its payment stands; `null` when they hold no payment of this feature for its invoice, or cannot be read.
  final P2pWalletPaymentProgress? progress;

  const EarlierEscrow({
    required this.take,
    required this.state,
    required this.sats,
    required this.progress,
  });

  /// The escrow of [record], an attempt recorded for an earlier contract, from what the wallet found for its payment hash ([found], `P2pWalletPort.findPayment`, asked for every record, with or without a wallet id), its sats [sats] when this run knows them.
  ///
  /// - The wallet holds a payment of this feature for that hash: its latest one tells ([earlierEscrowCaseOf]); the wallet pays an invoice again only while every earlier order of it is provably unspent (`P2pWalletPort.payInvoice`), so the latest is the one that may hold funds.
  /// - The wallet holds none, and the record names no wallet id: [EarlierEscrowCase.back], never left. Nothing of this feature is ever signed, saved or broadcast without an order in the wallet's records: the swap order's record is written (« creating ») before its request leaves (`OrderSwapRepositoryImpl._createOrderLocked`), deleted only when the service is known not to have made it, and the signed payin is saved on that record before anything is broadcast (`PayCheckedInvoiceUsecase`, step 7). Not seen: a payment of the same invoice made by the wallet's own Send screen; and an order whose invoice the wallet's decoder cannot read is not given by `findPayment` (functional verification of #187, point 1, in the shell).
  /// - The wallet holds none although the record names a wallet id, or its records cannot be read: [EarlierEscrowCase.notBack], its state unknown.
  static EarlierEscrow of(
    TradePaymentRecord record,
    Result<P2pWalletPaymentFound?, P2pWalletRefusal> found, {
    Sats? sats,
  }) => switch (found) {
    Ok(value: final payment?) => EarlierEscrow(
      take: record.take,
      state: earlierEscrowCaseOf(payment.progress),
      sats: sats,
      progress: payment.progress,
    ),
    Ok(value: null) when record.walletPaymentId == null => EarlierEscrow(
      take: record.take,
      state: EarlierEscrowCase.back,
      sats: sats,
      progress: null,
    ),
    Ok(value: null) || Err() => EarlierEscrow(
      take: record.take,
      state: EarlierEscrowCase.notBack,
      sats: sats,
      progress: null,
    ),
  };

  /// The case and the contract, never an amount nor a hash.
  @override
  String toString() => 'EarlierEscrow($take, ${state.name}, $progress)';
}

/// The contract of a maker seller's escrow this wallet is asked to pay, and every escrow this wallet was asked to pay for the order's other contracts (#187, design note § 6 row 13, the owner's decision of 2026-11-19): what its confirmation says (a new contract when [take] is above 0; the sats of the earlier escrows not back yet and what will be out of the wallet with this one; the escrows the coordinator kept), and what the payment is made under.
///
/// Nothing in it refuses a payment: an earlier escrow not back, or kept, is an alert of the confirmation, the user free to pay. The payment of a maker seller's escrow takes it back (`PayBondFromWalletUsecase.payBond`, `contract`): it goes on only for the very contract the confirmation stated, the trail read again under the payment's lock, and asks a new confirmation when the earlier escrows read again then are more out ([needsNewConfirmation]).
@immutable
final class EscrowContract {
  /// The contract of the escrow (`TradeTrail.take`): 0 for the order's first take.
  final int take;

  /// The sats of this escrow, the invoice of the quote confirmed.
  final Sats escrow;

  /// The escrows this wallet was asked to pay for the order's other contracts, by contract, oldest first.
  final List<EarlierEscrow> earlier;

  EscrowContract({
    required this.take,
    required this.escrow,
    required Iterable<EarlierEscrow> earlier,
  }) : earlier = List.unmodifiable(earlier);

  /// Whether the order was taken again since its first take: the confirmation says this is a new contract.
  bool get isNew => take > 0;

  /// The earlier escrows not back yet.
  List<EarlierEscrow> get notBack => [
    for (final escrow in earlier)
      if (escrow.state == EarlierEscrowCase.notBack) escrow,
  ];

  /// The earlier escrows the coordinator kept.
  List<EarlierEscrow> get kept => [
    for (final escrow in earlier)
      if (escrow.state == EarlierEscrowCase.kept) escrow,
  ];

  /// The sats of the earlier escrows not back yet whose amount this run knows.
  Sats get notBackSats => _sum(notBack);

  /// How many earlier escrows not back yet have an amount this run does not know (paid before the app started again).
  int get notBackUnknown =>
      notBack.where((escrow) => escrow.sats == null).length;

  /// What will be out of the wallet if this escrow is paid: [notBackSats] and [escrow]; at least that when [notBackUnknown] is above 0.
  Sats get outIfPaid => Sats(notBackSats.value + escrow.value);

  /// The sats of the earlier escrows the coordinator kept whose amount this run knows.
  Sats get keptSats => _sum(kept);

  /// Whether the confirmation alerts: an earlier escrow not back yet, or kept.
  bool get alerts => notBack.isNotEmpty || kept.isNotEmpty;

  /// Whether [now], the same contract read again under the payment's lock, shows more out than this confirmation showed: more sats not back, more not back of an unknown amount, or an escrow kept that this confirmation did not show kept. Then the payment asks a new confirmation; less or the same out pays.
  bool needsNewConfirmation(EscrowContract now) {
    if (now.notBackSats.value > notBackSats.value ||
        now.notBackUnknown > notBackUnknown) {
      return true;
    }
    final shownKept = {for (final escrow in kept) escrow.take};
    return now.kept.any((escrow) => !shownKept.contains(escrow.take));
  }

  static Sats _sum(Iterable<EarlierEscrow> escrows) => Sats(
    escrows.fold(
      BigInt.zero,
      (sum, escrow) => sum + (escrow.sats?.value ?? BigInt.zero),
    ),
  );

  /// The contract and the cases, never an amount.
  @override
  String toString() => 'EscrowContract($take, $earlier)';
}
