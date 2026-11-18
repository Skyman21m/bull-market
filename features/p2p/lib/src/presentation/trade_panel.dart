import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
import '../domain/trade/trade_edges.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_storable.dart';
import '../domain/trade/trade_warning.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';

/// The bond line of a contract (`TradeBox/BondStatus.tsx`): hidden, or « Your taker bond is locked / unlocked / settled », « Your maker bond is … » for a maker (`BondStatus.tsx:39`, #182).
enum TradeBondLine { hide, locked, unlocked, settled }

/// What « Cancel » does at a status (`TradeBox/CancelButton.tsx`): absent, free (« Cancel order », the dialog of `Dialogs/CancelOrder.tsx`), free at once with no dialog (a maker's public or paused order, whose bond is returned, `CancelButton.tsx:30`, `:79-80`, #182), or losing the bond (« Unilateral cancelation (bond at risk!) », `TradeBox/Dialogs/ConfirmCancel.tsx`).
enum TradeCancelOffer { none, free, immediate, losesBond }

/// The title of a contract (`TradeBox/index.tsx`, `statusToContract`).
enum TradeTitle {
  lockBond,

  /// The maker's at 0 (#180): « Lock {{amountSats}} Sats to PUBLISH order » (`TradeBox/index.tsx:379-389`).
  lockBondToPublish,

  /// The maker's at 1 and 2 (#182): « Your order is public », « Your order is paused » (`TradeBox/index.tsx:390-420`).
  orderPublic,
  orderPaused,
  payout,
  infoGood,

  /// The seller's (#96): « Lock {{amountSats}} Sats as collateral » at 6 and 7, « The trade collateral is locked! » at 8, « Chat with the buyer » at 9 and 10.
  lockEscrow,
  collateralLocked,
  chatWithBuyer,
  expired,
  chat,
  dispute,
  statementReceived,
  sendingSats,
  finished,
  routingFailed,
  statements,
  disputeWon,
  disputeLost,
  unknown,
}

/// The prompt under a title: the bond's invoice, the payout's (`Prompts/Payout.tsx`), the wait for the escrow, the expiry's reason, a failed payout's (`Prompts/RoutingFailed.tsx`, #91), the buyer's chat step (`Prompts/Chat.tsx`, #95), the buyer being paid (`Prompts/SendingSats.tsx`, #95), the trade finished (`Prompts/Successful.tsx`, #95), or a step a later version shows.
enum TradePrompt {
  lockInvoice,

  /// The maker's at 1 (`Prompts/PublicWait.tsx`) and at 2 (`Prompts/Paused.tsx`, its text without « Unpause Order », which comes with the pause, #184), #182.
  publicWait,
  paused,
  payout,
  escrowWait,

  /// The seller's (#96): the escrow to lock (`Prompts/LockInvoice.tsx`, concept `escrow`) at 6 and 7, the wait for the buyer's payout (`Prompts/PayoutWait.tsx`) at 8.
  lockEscrow,
  payoutWait,
  expired,
  routingFailed,
  chat,
  sendingSats,
  finished,

  /// 11 and later, read-only (#95, design note § 2.7): a dispute opened, this robot's statement not in (`Prompts/Dispute.tsx`, whose statement form comes in a later phase); received (`Prompts/DisputeWaitPeer.tsx`); both statements in, 16 (`DisputeWaitResolution.tsx`); won, 17 for a taker (`DisputeWinner.tsx`); lost, 18 (`DisputeLoser.tsx`).
  disputeOpen,
  disputeWaitPeer,
  disputeWaitResolution,
  disputeWon,
  disputeLost,
  later,
}

/// What the trade screen shows for the state the watch gave (#88): one case per kind of screen, the conditions written once here, with no rule of their own on statuses (the state machine of #86 decides).
@immutable
sealed class TradeView {
  const TradeView();

  /// The view of [watch], the last state of the trade's watch, or `null` before the first.
  static TradeView of(TradeWatchState? watch) => switch (watch) {
    null => const TradeWaiting(),
    TradeWatchUnrestorable(reason: TradeCoordinatorGone()) =>
      const TradeMessage(TradeMessageKind.coordinatorGone),
    TradeWatchUnrestorable() => const TradeMessage(
      TradeMessageKind.unrestorable,
    ),
    TradeWatchUnavailable(
      failure: GarageKeyMissingFailure() || TradeKeyMissingFailure(),
    ) =>
      const TradeMessage(TradeMessageKind.keyMissing),
    TradeWatchUnavailable(failure: P2pStorageFailure()) => const TradeMessage(
      TradeMessageKind.recordsUnreadable,
    ),
    TradeWatchUnavailable() => const TradeMessage(TradeMessageKind.unavailable),
    TradeWatchTakeNeverSent() => const TradeMessage(
      TradeMessageKind.takeNeverSent,
    ),
    // A take that did not happen: no pre-take, so no invoice, was ever seen.
    TradeWatchTakeNotMade() => const TradeMessage(TradeMessageKind.takeNotMade),
    // A newer subscription took the trade over: not an error; the cubit stops and never shows it.
    TradeWatchSuperseded() => const TradeWaiting(),
    TradeWatchStatus(:final seen, :final takePending) => _ofStatus(
      seen,
      takePending: takePending,
      // An invoice, or a payment, only from a status marked stored (#117): `recordProblem` alone does not decide it.
      payable: seen.stored,
    ),
  };

  static TradeView _ofStatus(
    TradeSeen seen, {
    required bool takePending,
    required bool payable,
  }) {
    final status = seen.status;
    final order = seen.order;
    return switch (status) {
      StatusUnknown() when takePending => const TradeMessage(
        TradeMessageKind.takePending,
      ),
      // An end the stored trail holds, with no read of it to show: the trade is over for this robot, and nothing is read again.
      StatusUnknown(position: TradePosition.cancelled) => const TradeMessage(
        TradeMessageKind.cancelled,
      ),
      StatusUnknown(position: TradePosition.notAvailable) => const TradeMessage(
        TradeMessageKind.notAvailable,
      ),
      StatusUnknown(isTerminal: true) => const TradeMessage(
        TradeMessageKind.ended,
      ),
      StatusUnknown() => const TradeWaiting(),
      Cancelled() => const TradeMessage(TradeMessageKind.cancelled),
      TakenByAnother() ||
      PreTakeUnavailable() => const TradeMessage(TradeMessageKind.notAvailable),
      BondForfeited(position: TradePosition.notAvailable) => const TradeMessage(
        TradeMessageKind.notAvailable,
      ),
      // This robot is no participant any more and the order is public again: the official client shows the order alone, with no contract.
      PreTakeEnded() ||
      BondForfeited() when order != null => TradeOrderOnly(order),
      PreTakeEnded() ||
      BondForfeited() => const TradeMessage(TradeMessageKind.notAvailable),
      _ => TradeContract(seen, order: order, payable: payable),
    };
  }
}

/// Nothing understood yet: a spinner, as the official client's order page before its order arrives.
final class TradeWaiting extends TradeView {
  const TradeWaiting();
}

/// A message alone, as the official client shows a `bad_request` on the order page, or a state the watch gives that it has no screen for.
final class TradeMessage extends TradeView {
  final TradeMessageKind kind;

  const TradeMessage(this.kind);
}

enum TradeMessageKind {
  cancelled,
  ended,
  notAvailable,
  takePending,
  takeNeverSent,
  takeNotMade,
  unrestorable,
  coordinatorGone,
  unavailable,
  keyMissing,
  recordsUnreadable,
}

/// The order alone, public again, as the official client shows an order to a robot that is no participant.
final class TradeOrderOnly extends TradeView {
  final CoordinatorOrder order;

  const TradeOrderOnly(this.order);
}

/// A contract of the TradeBox: the tabs « Order » / « Contract », with the title, prompt, bond line and cancel of [seen]'s status.
final class TradeContract extends TradeView {
  final TradeSeen seen;
  final CoordinatorOrder? order;

  /// Whether the status is marked stored (`TradeSeen.stored`): otherwise nothing payable is offered (no QR code, no copy, no wallet), only the reads and what the reference offers without an invoice (`AGENTS.md`, « Rules for #88 »).
  final bool payable;

  const TradeContract(this.seen, {required this.order, this.payable = true});

  TradeStatus get status => seen.status;

  TradeTitle get title => titleOf(status);

  TradePrompt get prompt => promptOf(status);

  TradeBondLine get bondLine => bondLineOf(status);

  TradeCancelOffer get cancel => cancelOf(status);

  /// The sats the title states: the bond at 3 (`bond_satoshis`), the maker bond at 0 (`bond_satoshis`, `TradeBox/index.tsx:383`, #180), the escrow at 6 and 7 for a seller (`escrow_satoshis`, `TradeBox/index.tsx:482`, `:500`; before the coordinator gives the invoice, the seller's `trade_satoshis`, which is the same `Logics.escrow_amount`, `api/views.py:362-365`); `null` elsewhere.
  Sats? get titleSats => switch (status) {
    WaitingForTakerBond(:final bond) ||
    WaitingForMakerBond(:final bond) => bond.orderAmount,
    WaitingForBoth(
      role: TradeRole.seller,
      :final escrow,
      :final tradeSatoshis,
    ) ||
    WaitingForEscrow(
      role: TradeRole.seller,
      :final escrow,
      :final tradeSatoshis,
    ) => escrow?.orderAmount ?? tradeSatoshis,
    _ => null,
  };

  /// Whether the trade is a maker's (`TradeTrail.made`, which follows from its terms): the reference's `is_maker` for the step and the bond line.
  bool get maker => status.trail.made;

  /// The step and the steps (`TradeBox/stepXofY.ts`): for a taker 3 → 1 of 4, 6 to 8 → 2, 9 → 3, 10 → 4; for a maker 0 → 1 of 5, 1 and 2 → 2, 6 to 8 → 3, 9 → 4, 10 → 5 (`stepXofY.ts:15-26`, #180, #182); none elsewhere.
  (int, int)? get step => stepOf(status, maker: maker);

  /// The step of [status] for a maker or a taker ([maker]), as `stepXofY.ts` counts it from the status the order shows.
  static (int, int)? stepOf(TradeStatus status, {required bool maker}) => maker
      ? switch (status.position) {
          TradePosition.makerBondStep => (1, 5),
          TradePosition.public || TradePosition.paused => (2, 5),
          TradePosition.waitingForBoth ||
          TradePosition.waitingForEscrow ||
          TradePosition.waitingForPayout => (3, 5),
          TradePosition.chatting => (4, 5),
          TradePosition.fiatSent => (5, 5),
          _ => null,
        }
      : switch (status.position) {
          TradePosition.bondStep => (1, 4),
          TradePosition.waitingForBoth ||
          TradePosition.waitingForEscrow ||
          TradePosition.waitingForPayout => (2, 4),
          TradePosition.chatting => (3, 4),
          TradePosition.fiatSent => (4, 4),
          _ => null,
        };

  /// The title the official client gives a taker at [status], of either side (`statusToContract`, `TradeBox/index.tsx:359-724`): a seller locks the escrow at 6 and 7, waits at 8, and sees « Trade finished! » from 13 on, 15 included, where the buyer is still being paid.
  static TradeTitle titleOf(TradeStatus status) => switch (status) {
    WaitingForTakerBond() => TradeTitle.lockBond,
    WaitingForMakerBond() => TradeTitle.lockBondToPublish,
    MakerOrderPublic(paused: false) => TradeTitle.orderPublic,
    MakerOrderPublic(paused: true) => TradeTitle.orderPaused,
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(role: TradeRole.buyer) => TradeTitle.payout,
    WaitingForEscrow(role: TradeRole.buyer) => TradeTitle.infoGood,
    WaitingForBoth(role: TradeRole.seller) ||
    WaitingForEscrow(role: TradeRole.seller) => TradeTitle.lockEscrow,
    WaitingForPayout(role: TradeRole.seller) => TradeTitle.collateralLocked,
    Chatting(role: TradeRole.buyer) => TradeTitle.chat,
    Chatting(role: TradeRole.seller) => TradeTitle.chatWithBuyer,
    InDispute(statementSubmitted: true) => TradeTitle.statementReceived,
    InDispute() => TradeTitle.dispute,
    SendingSats(role: TradeRole.buyer) => TradeTitle.sendingSats,
    RoutingFailed(role: TradeRole.buyer) => TradeTitle.routingFailed,
    Succeeded() || SendingSats() || RoutingFailed() => TradeTitle.finished,
    WaitingDisputeResolution() => TradeTitle.statements,
    DisputeWon() => TradeTitle.disputeWon,
    DisputeLost() => TradeTitle.disputeLost,
    Expired() => TradeTitle.expired,
    _ => TradeTitle.unknown,
  };

  static TradePrompt promptOf(TradeStatus status) => switch (status) {
    // The maker bond at 0 is the same prompt (`Prompts/LockInvoice.tsx`, concept `bond`, `TradeBox/index.tsx:384-386`, #180).
    WaitingForTakerBond() || WaitingForMakerBond() => TradePrompt.lockInvoice,
    MakerOrderPublic(paused: false) => TradePrompt.publicWait,
    MakerOrderPublic(paused: true) => TradePrompt.paused,
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(role: TradeRole.buyer) => TradePrompt.payout,
    WaitingForEscrow(role: TradeRole.buyer) => TradePrompt.escrowWait,
    WaitingForBoth(role: TradeRole.seller) ||
    WaitingForEscrow(role: TradeRole.seller) => TradePrompt.lockEscrow,
    WaitingForPayout(role: TradeRole.seller) => TradePrompt.payoutWait,
    RoutingFailed(role: TradeRole.buyer) => TradePrompt.routingFailed,
    Chatting() => TradePrompt.chat,
    SendingSats(role: TradeRole.buyer) => TradePrompt.sendingSats,
    Succeeded() ||
    SendingSats(role: TradeRole.seller) ||
    RoutingFailed(role: TradeRole.seller) => TradePrompt.finished,
    InDispute(statementSubmitted: true) => TradePrompt.disputeWaitPeer,
    InDispute() => TradePrompt.disputeOpen,
    WaitingDisputeResolution() => TradePrompt.disputeWaitResolution,
    DisputeWon() => TradePrompt.disputeWon,
    DisputeLost() => TradePrompt.disputeLost,
    Expired() => TradePrompt.expired,
    _ => TradePrompt.later,
  };

  /// The bond line of `statusToContract`: locked from the bond's lock to the chat (a maker's public or paused order included, `TradeBox/index.tsx:403`, `:418`), settled in a dispute and after losing one, unlocked once the buyer is being paid (for the buyer only: the reference hides it from the seller at 13 and 15), hidden elsewhere.
  static TradeBondLine bondLineOf(TradeStatus status) => switch (status) {
    MakerOrderPublic() ||
    WaitingForBoth() ||
    WaitingForEscrow() ||
    WaitingForPayout() ||
    Chatting() => TradeBondLine.locked,
    InDispute() ||
    WaitingDisputeResolution() ||
    DisputeLost() => TradeBondLine.settled,
    SendingSats(role: TradeRole.buyer) ||
    RoutingFailed(role: TradeRole.buyer) => TradeBondLine.unlocked,
    _ => TradeBondLine.hide,
  };

  /// « Cancel » at 3, 6 and 7 (`CancelButton.tsx:27-29`), and for a maker at 0, 1 and 2 (`:27-29`): free with the reference's `Dialogs/CancelOrder.tsx` while no bond is locked (a taker's 3, a maker's 0, `:34-36`, `:74-78`, #180), free at once with no dialog for a maker's public or paused order, whose bond the coordinator returns (`:30`, `:79-80`, #182), losing the bond at 6 and 7 for either side (`:81`).
  static TradeCancelOffer cancelOf(TradeStatus status) => switch (status) {
    WaitingForTakerBond() || WaitingForMakerBond() => TradeCancelOffer.free,
    MakerOrderPublic() => TradeCancelOffer.immediate,
    WaitingForBoth() || WaitingForEscrow() => TradeCancelOffer.losesBond,
    _ => TradeCancelOffer.none,
  };
}

/// What the bond panel shows of the invoice of the step (design note § 4.4): the QR code and the copy only for a [CheckedInvoice] whose warnings allow it, or allow it after « Show anyway »; never for an [UnusableInvoice].
enum InvoiceDisplay {
  /// The QR code and the copy.
  shown,

  /// Hidden behind the warnings and « Show anyway ».
  hiddenUntilShownAnyway,

  /// Not shown at all.
  hidden,
}

/// Whether [invoice] can no longer be paid at [now], the screen's clock: past its `payableUntil` (the earlier of its expiry and the step's deadline).
///
/// The state machine finds an invoice expired only when a read computes its status ([InvoiceExpired]); the screen's clock moves every second, so an invoice that expires between two reads, or while the reads fail, is hidden at once (design note § 4.4: never show an expired invoice).
bool invoiceExpiredAt(StepInvoice invoice, DateTime now) => switch (invoice) {
  CheckedInvoice(:final payableUntil) => !now.isBefore(payableUntil),
  UnusableInvoice() => false,
};

/// How [invoice] is shown at [now], once the user pressed « Show anyway » when [shownAnyway]: never once it can no longer be paid ([invoiceExpiredAt]).
InvoiceDisplay invoiceDisplayOf(
  StepInvoice invoice, {
  required bool shownAnyway,
  required DateTime now,
}) => switch (invoice) {
  _ when invoiceExpiredAt(invoice, now) => InvoiceDisplay.hidden,
  UnusableInvoice() => InvoiceDisplay.hidden,
  CheckedInvoice() when invoice.mayShow => InvoiceDisplay.shown,
  CheckedInvoice() when invoice.mayShowAnyway =>
    shownAnyway ? InvoiceDisplay.shown : InvoiceDisplay.hiddenUntilShownAnyway,
  CheckedInvoice() => InvoiceDisplay.hidden,
};

/// The warnings a status shows at [now], each once (the three amount checks share one text, so they are kept apart here and worded by the screen), its invoice's own included, and [InvoiceExpired] once the screen's clock passed the invoice's `payableUntil` ([invoiceExpiredAt]).
List<TradeWarning> warningsOf(TradeStatus status, {required DateTime now}) {
  final seen = <Type>{};
  final invoice = status.invoice;
  return [
    for (final warning in [
      ...status.warnings,
      if (invoice case UnusableInvoice(:final reason)) reason,
      if (invoice case CheckedInvoice(:final warnings)) ...warnings,
      if (invoice != null && invoiceExpiredAt(invoice, now))
        const InvoiceExpired(),
    ])
      if (seen.add(warning.runtimeType)) warning,
  ];
}
