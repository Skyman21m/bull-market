import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
import '../domain/trade/trade_edges.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_storable.dart';
import '../domain/trade/trade_warning.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade_record.dart';

/// The bond line of a contract (`TradeBox/BondStatus.tsx`): hidden, or « Your taker bond is locked / unlocked / settled ».
enum TradeBondLine { hide, locked, unlocked, settled }

/// What « Cancel » does at a status (`TradeBox/CancelButton.tsx`): absent, free (« Cancel order », the dialog of `Dialogs/CancelOrder.tsx`), or losing the bond (« Unilateral cancelation (bond at risk!) », `TradeBox/Dialogs/ConfirmCancel.tsx`).
enum TradeCancelOffer { none, free, losesBond }

/// The title of a contract (`TradeBox/index.tsx`, `statusToContract`).
enum TradeTitle {
  lockBond,
  payout,
  infoGood,
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

/// The prompt under a title: the bond's invoice, the payout's (`Prompts/Payout.tsx`), the wait for the escrow, the expiry's reason, a failed payout's (`Prompts/RoutingFailed.tsx`, #91), or a step a later version shows.
enum TradePrompt {
  lockInvoice,
  payout,
  escrowWait,
  expired,
  routingFailed,
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

  /// The step and the steps of a taker (`TradeBox/stepXofY.ts`): 3 → 1 of 4, 6 to 8 → 2, 9 → 3, 10 → 4; none elsewhere.
  (int, int)? get step => switch (status.position) {
    TradePosition.bondStep => (1, 4),
    TradePosition.waitingForBoth ||
    TradePosition.waitingForEscrow ||
    TradePosition.waitingForPayout => (2, 4),
    TradePosition.chatting => (3, 4),
    TradePosition.fiatSent => (4, 4),
    _ => null,
  };

  /// The title the official client gives a taker of the buyer's side at [status] (`statusToContract`); a seller's step, which a take never makes here, has the reference's default.
  static TradeTitle titleOf(TradeStatus status) => switch (status) {
    WaitingForTakerBond() => TradeTitle.lockBond,
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(role: TradeRole.buyer) => TradeTitle.payout,
    WaitingForEscrow(role: TradeRole.buyer) => TradeTitle.infoGood,
    Chatting(role: TradeRole.buyer) => TradeTitle.chat,
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
    WaitingForTakerBond() => TradePrompt.lockInvoice,
    WaitingForBoth(role: TradeRole.buyer) ||
    WaitingForPayout(role: TradeRole.buyer) => TradePrompt.payout,
    WaitingForEscrow(role: TradeRole.buyer) => TradePrompt.escrowWait,
    RoutingFailed(role: TradeRole.buyer) => TradePrompt.routingFailed,
    Expired() => TradePrompt.expired,
    _ => TradePrompt.later,
  };

  /// The bond line of `statusToContract`: locked from the bond's lock to the chat, settled in a dispute and after losing one, unlocked once the buyer is being paid, hidden elsewhere.
  static TradeBondLine bondLineOf(TradeStatus status) => switch (status) {
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

  /// « Cancel » at 3, 6 and 7 only (`CancelButton.tsx:27-29`): free while the bond is not locked, losing it after.
  static TradeCancelOffer cancelOf(TradeStatus status) => switch (status) {
    WaitingForTakerBond() => TradeCancelOffer.free,
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
