import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'bolt11.dart';
import 'checked_invoice.dart';
import 'trade_answer.dart';
import 'trade_edges.dart';
import 'trade_terms.dart';
import 'trade_tolerances.dart';
import 'trade_warning.dart';

/// What the trade remembers from one read to the next, so that each answer is checked against the trade's history and not only against itself.
@immutable
final class TradeTrail {
  /// The payment hash of the first bond invoice and of the first escrow invoice of the trade: a step never changes its invoice.
  final String? bondHash;
  final String? escrowHash;

  /// The deadline (`expires_at`) of the last order read, for the position it was read at.
  final DateTime? deadline;

  /// When an answer last showed the pre-take: a pre-take that ended earlier than the escrow duration after it cannot have locked and lost the bond.
  final DateTime? bondStepSeenAt;

  /// Whether an answer of this trade was a breach of trust ([TradeWarning.isBreachOfTrust]): every later status then carries [CoordinatorInconsistent].
  final bool breached;

  const TradeTrail._({
    required this.bondHash,
    required this.escrowHash,
    required this.deadline,
    required this.bondStepSeenAt,
    required this.breached,
  });

  static const empty = TradeTrail._(
    bondHash: null,
    escrowHash: null,
    deadline: null,
    bondStepSeenAt: null,
    breached: false,
  );

  TradeTrail _next({
    String? bondHash,
    String? escrowHash,
    required DateTime? deadline,
    DateTime? bondStepSeenAt,
    required bool breached,
  }) => TradeTrail._(
    bondHash: this.bondHash ?? bondHash,
    escrowHash: this.escrowHash ?? escrowHash,
    deadline: deadline,
    bondStepSeenAt: bondStepSeenAt ?? this.bondStepSeenAt,
    breached: this.breached || breached,
  );

  TradeTrail _breach() => TradeTrail._(
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadline: deadline,
    bondStepSeenAt: bondStepSeenAt,
    breached: true,
  );

  @override
  String toString() => 'TradeTrail(breached: $breached)';
}

/// What a screen may show, and the wallet may pay, of a taker's trade: one class per status a taker can see (design note § 3.2), built only by [TradeStatus.from] from the coordinator's answers, checked against the terms of the take and the trade's history.
///
/// The screens map each class to a panel and add no rule of their own (#88); [warnings] holds every check that failed, none of which ever triggers an action.
/// Nothing in a status is printed: its [toString] names its class and its warnings.
@immutable
sealed class TradeStatus {
  /// When the answer this status comes from was read.
  final DateTime seenAt;

  /// Every check that failed on that answer, and those carried from earlier answers of the trade ([CoordinatorInconsistent]); an answer refused as a whole adds its own to the status it leaves in place.
  final List<TradeWarning> warnings;

  /// What the next read is checked against.
  final TradeTrail trail;

  const TradeStatus._(this.seenAt, this.warnings, this.trail);

  /// Where the trade stands for the edges of [TradeEdges].
  TradePosition get position;

  /// Whether the trade is over for this robot: a terminal status is never left by [from].
  bool get isTerminal => position.isTerminal;

  /// The hold invoice this robot must lock at this status, checked: the bond at the pre-take, the escrow of a seller at 6 and 7; `null` elsewhere.
  StepInvoice? get invoice => null;

  /// Whether this status has a warning of type [T].
  bool has<T extends TradeWarning>() => warnings.any((warning) => warning is T);

  /// The same status with [more] warnings and [trail]: the invoice it holds, if any, takes them too.
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail);

  /// The status of the trade [terms] after [answer], read at [now], when the last status was [previous] (`null` before the first answer): a pure function, with no clock, no I/O and no randomness, which [reader] decodes invoices for.
  ///
  /// - A terminal [previous] is never left: any answer returns [previous] as it is, but an order of the same status (5, 14, 17, 18), which refreshes it.
  /// - An answer refused as a whole leaves [previous] in place with the reason added ([TradeOrderMismatch], [TradeRoleMismatch], [TradeStatusRegressed], or [TradeStatusUnexpected] for an unlisted edge into a terminal position), or gives a [StatusNotUnderstood] when there is none.
  /// - Any other answer gives its status, with [TradeStatusUnexpected] when its edge is not one of [TradeEdges], and the warnings of the order's checks and of its invoice.
  static TradeStatus from({
    required TradeStatus? previous,
    required TradeAnswer answer,
    required TradeTerms terms,
    required DateTime now,
    required Bolt11Reader reader,
  }) {
    final from = previous?.position ?? TradePosition.start;
    final trail = previous?.trail ?? TradeTrail.empty;
    final to = _positionOf(answer);
    // An end is refreshed only by an order of the same status, which may say more (a summary, a transaction): being out of the order again says nothing new.
    if (previous != null &&
        previous.isTerminal &&
        (to != from ||
            answer is! TradeOrderRead ||
            to == TradePosition.publicAgain)) {
      return previous;
    }

    final refusal = _refusalOf(answer, terms, from, to);
    if (refusal != null || to == null) {
      // [_refusalOf] refuses every answer without a position.
      final reason = refusal ?? const TradeStatusRegressed();
      return switch (previous) {
        null => StatusNotUnderstood._(now, [reason], trail._breach()),
        _ => previous._rewarned([
          if (!previous.warnings.any(
            (warning) => warning.runtimeType == reason.runtimeType,
          ))
            reason,
        ], trail._breach()),
      };
    }

    final readWarnings = <TradeWarning>[
      if (trail.breached) const CoordinatorInconsistent(),
      if (!TradeEdges.allows(terms.role, from, to))
        const TradeStatusUnexpected(),
    ];
    switch (answer) {
      case TradeOrderCancelled():
        return Cancelled._(
          now,
          readWarnings,
          trail._next(deadline: null, breached: _breaches(readWarnings)),
        );
      case TradeOrderNotAvailable()
          when from == TradePosition.bondStep || from == TradePosition.start:
        return TakenByAnother._(
          now,
          readWarnings,
          trail._next(deadline: null, breached: _breaches(readWarnings)),
          bondMayHaveBeenLost: _bondMayHaveBeenLost(from, trail, terms, now),
        );
      case TradeOrderNotAvailable():
        return BondForfeited._(
          now,
          readWarnings,
          trail._next(deadline: null, breached: _breaches(readWarnings)),
          position: TradePosition.notAvailable,
        );
      case TradeOrderRead(:final order):
        return _ofOrder(
          order,
          from: from,
          to: to,
          trail: trail,
          terms: terms,
          now: now,
          reader: reader,
          readWarnings: [
            ...readWarnings,
            ..._orderWarnings(order, terms, to, from, trail),
          ],
        );
    }
  }

  static bool _breaches(List<TradeWarning> warnings) =>
      warnings.any((warning) => warning.isBreachOfTrust);

  /// The position an answer shows, or `null` for a status a taker is never shown: 0, 2, 4 and 12 in an order, or the order public with this robot still a participant.
  static TradePosition? _positionOf(TradeAnswer answer) => switch (answer) {
    TradeOrderCancelled() => TradePosition.cancelled,
    TradeOrderNotAvailable() => TradePosition.notAvailable,
    TradeOrderRead(:final order) => switch (order.status) {
      CoordinatorOrderStatus.public when !order.isParticipant =>
        TradePosition.publicAgain,
      CoordinatorOrderStatus.waitingForTakerBond => TradePosition.bondStep,
      CoordinatorOrderStatus.expired => TradePosition.expired,
      CoordinatorOrderStatus.waitingForCollateralAndInvoice =>
        TradePosition.waitingForBoth,
      CoordinatorOrderStatus.waitingForCollateral =>
        TradePosition.waitingForEscrow,
      CoordinatorOrderStatus.waitingForInvoice =>
        TradePosition.waitingForPayout,
      CoordinatorOrderStatus.sendingFiat => TradePosition.chatting,
      CoordinatorOrderStatus.fiatSent => TradePosition.fiatSent,
      CoordinatorOrderStatus.inDispute => TradePosition.inDispute,
      CoordinatorOrderStatus.sendingSats => TradePosition.sendingSats,
      CoordinatorOrderStatus.successful => TradePosition.succeeded,
      CoordinatorOrderStatus.routingFailed => TradePosition.routingFailed,
      CoordinatorOrderStatus.waitingForDisputeResolution =>
        TradePosition.waitingDisputeResolution,
      CoordinatorOrderStatus.makerLostDispute => TradePosition.makerLostDispute,
      CoordinatorOrderStatus.takerLostDispute => TradePosition.takerLostDispute,
      CoordinatorOrderStatus.waitingForMakerBond ||
      CoordinatorOrderStatus.public ||
      CoordinatorOrderStatus.paused ||
      CoordinatorOrderStatus.cancelled ||
      CoordinatorOrderStatus.collaborativelyCancelled => null,
    },
  };

  /// Why [answer] is refused as a whole, or `null` when it is not.
  static TradeWarning? _refusalOf(
    TradeAnswer answer,
    TradeTerms terms,
    TradePosition from,
    TradePosition? to,
  ) {
    if (answer case TradeOrderRead(:final order)) {
      if (order.coordinator != terms.coordinator ||
          order.network != terms.network ||
          order.id != terms.orderId) {
        return const TradeOrderMismatch();
      }
      // `package:robosats` has checked that the roles agree with each other, with the order's type and with the robot that asked; what it cannot know is the role this robot took.
      if (order.isMaker ||
          (order.isParticipant &&
              order.isBuyer != (terms.role == TradeRole.buyer))) {
        return const TradeRoleMismatch();
      }
    }
    if (to == null) return const TradeStatusRegressed();
    if (to == TradePosition.bondStep &&
        from != TradePosition.start &&
        from != TradePosition.bondStep) {
      return const TradeStatusRegressed();
    }
    // A coordinator does not end a trade in this app's eyes by an answer that contradicts its history: such an answer is refused, and the reads go on.
    if (to.isTerminal && !TradeEdges.allows(terms.role, from, to)) {
      return const TradeStatusUnexpected();
    }
    return null;
  }

  /// Whether a pre-take that ended at [now] may have locked its bond and lost it since the last read that showed it: the bond can lock up to that read's end, and a bond is lost at the earliest an escrow duration later (a step left undone, `api/logics.py:404-421`, `:445-458`), with a minute of margin for the coordinator's loops.
  static bool _bondMayHaveBeenLost(
    TradePosition from,
    TradeTrail trail,
    TradeTerms terms,
    DateTime now,
  ) {
    final seen = trail.bondStepSeenAt;
    if (from != TradePosition.bondStep || seen == null) return true;
    final earliestLoss = seen
        .add(terms.escrowDuration)
        .subtract(const Duration(minutes: 1));
    return !now.isBefore(earliestLoss);
  }

  /// Whether [a] and [b] are within [tolerance] of each other, both ways, plus [TradeTolerances.roundingSats].
  static bool _near(num a, num b, double tolerance) =>
      (a - b).abs() <= b.abs() * tolerance + TradeTolerances.roundingSats;

  static bool _sameFiat(double a, double b) =>
      (a - b).abs() <= TradeTolerances.fiatAmount * math.max(1, a.abs());

  static bool _samePercent(double a, double b) =>
      (a - b).abs() <= TradeTolerances.percent;

  /// The checks of an order against the terms of the take and the trade's history (design note § 3.2, as #86 states them).
  static List<TradeWarning> _orderWarnings(
    CoordinatorOrder order,
    TradeTerms terms,
    TradePosition to,
    TradePosition from,
    TradeTrail trail,
  ) {
    final warnings = <TradeWarning>[];
    if (_termsChanged(order, terms)) warnings.add(const TradeTermsChanged());

    if (order.bondInvoice case final bond? when to == TradePosition.bondStep) {
      if (!_near(
        bond.satoshis.value.toInt(),
        terms.expectedBond,
        TradeTolerances.price,
      )) {
        warnings.add(const BondAmountOutsideOrder());
      }
    }

    // From the bond's lock on, `satoshis_now` is the order's `last_satoshis`, the trade's sats fixed then (`api/views.py:324`, `api/logics.py:1332-1335`); before it, at the pre-take, it is a stale figure and is not read.
    final fixed = order.isParticipant && order.status.wire >= 6;
    final last = order.satoshisNow?.value.toInt();
    if (fixed) {
      if (last == null ||
          !_near(last, terms.expectedSatoshis, TradeTolerances.price)) {
        warnings.add(const TradePriceOutsideOrder());
      }
    }

    final trade = order.tradeSatoshis?.value.toInt();
    final int? paid;
    switch (terms.role) {
      case TradeRole.seller:
        final escrow = order.escrowInvoice?.satoshis.value.toInt();
        if (escrow != null && escrow != trade) {
          warnings.add(const EscrowAmountMismatch());
        }
        paid = escrow ?? trade;
      case TradeRole.buyer:
        final payout = order.payoutInvoiceAmount?.value.toInt();
        if (payout != null && payout != trade) {
          warnings.add(const PayoutAmountMismatch());
        }
        paid = payout ?? trade;
    }
    if (fixed && last != null && paid != null) {
      // The seller locks the trade and its fee; the buyer receives the trade less its fee (`api/logics.py:650-669`, `:733-749`).
      final fee = terms.role == TradeRole.seller ? paid - last : last - paid;
      if (fee < 0 || fee > last * terms.takerFee + TradeTolerances.feeSats) {
        warnings.add(const TakerFeeAboveAnnounced());
      }
    }

    if (trail.deadline case final earlier?
        when from == to && order.expiresAt.isBefore(earlier)) {
      warnings.add(const DeadlineMovedBack());
    }
    return warnings;
  }

  /// Whether the order's own terms are not those of the public order taken.
  static bool _termsChanged(CoordinatorOrder order, TradeTerms terms) {
    if (order.currency != terms.currency || order.type != terms.type) {
      return true;
    }
    if (!_samePercent(order.bondSize.percent, terms.bondSize.percent) ||
        order.escrowDuration != terms.escrowDuration) {
      return true;
    }
    switch (terms.explicitSatoshis) {
      case final sats?:
        if (order.explicitSatoshis != sats) return true;
      case null:
        if (order.isExplicit) return true;
        if (order.premium case final premium?
            when !_samePercent(premium.percent, terms.premium.percent)) {
          return true;
        }
    }
    switch (order.amount) {
      case FixedOrderAmount(:final amount):
        if (terms.isRange || !_sameFiat(amount.value, terms.amount.value)) {
          return true;
        }
      case RangeOrderAmount():
        if (!terms.isRange) return true;
        // A participant's answer gives the amount taken (`api/views.py:384`, `api/logics.py:1328-1329`).
        if (order.isParticipant) {
          final taken = order.takenAmount;
          if (taken == null || !_sameFiat(taken.value, terms.amount.value)) {
            return true;
          }
        }
    }
    return false;
  }

  static TradeStatus _ofOrder(
    CoordinatorOrder order, {
    required TradePosition from,
    required TradePosition to,
    required TradeTrail trail,
    required TradeTerms terms,
    required DateTime now,
    required Bolt11Reader reader,
    required List<TradeWarning> readWarnings,
  }) {
    final breached = _breaches(readWarnings);
    final deadline = order.expiresAt;
    final role = terms.role;

    StepInvoice? invoiceOf(HoldInvoice? hold, InvoiceStep step) =>
        switch (hold) {
          null => null,
          _ => checkStepInvoice(
            hold: hold,
            step: step,
            terms: terms,
            reader: reader,
            pinnedHash: switch (step) {
              InvoiceStep.bond => trail.bondHash,
              InvoiceStep.escrow => trail.escrowHash,
            },
            stepDeadline: deadline,
            now: now,
            readWarnings: readWarnings,
          ),
        };

    List<TradeWarning> warningsWith(StepInvoice? invoice) => switch (invoice) {
      CheckedInvoice(:final warnings) => warnings,
      UnusableInvoice(:final reason) => [...readWarnings, reason],
      null => readWarnings,
    };

    String? hashOf(StepInvoice? invoice) => switch (invoice) {
      CheckedInvoice(:final paymentHash) => paymentHash,
      _ => null,
    };

    TradeTrail nextTrail({StepInvoice? bond, StepInvoice? escrow}) =>
        trail._next(
          bondHash: hashOf(bond),
          escrowHash: hashOf(escrow),
          deadline: deadline,
          bondStepSeenAt: to == TradePosition.bondStep ? now : null,
          breached: breached,
        );

    StepInvoice? escrowForSeller() => role == TradeRole.seller
        ? invoiceOf(order.escrowInvoice, InvoiceStep.escrow)
        : null;

    switch (to) {
      case TradePosition.bondStep:
        // `package:robosats` gives status 3 only with its bond invoice.
        final bond = invoiceOf(order.bondInvoice, InvoiceStep.bond);
        if (bond == null) {
          return StatusNotUnderstood._(now, readWarnings, nextTrail());
        }
        return WaitingForTakerBond._(
          now,
          warningsWith(bond),
          nextTrail(bond: bond),
          bond: bond,
          deadline: deadline,
          stepDuration: order.stepDuration,
        );
      case TradePosition.waitingForBoth:
        final escrow = escrowForSeller();
        return WaitingForBoth._(
          now,
          warningsWith(escrow),
          nextTrail(escrow: escrow),
          role: role,
          escrow: escrow,
          payoutAmount: order.payoutInvoiceAmount,
          tradeSatoshis: order.tradeSatoshis,
          deadline: deadline,
        );
      case TradePosition.waitingForEscrow:
        final escrow = escrowForSeller();
        return WaitingForEscrow._(
          now,
          warningsWith(escrow),
          nextTrail(escrow: escrow),
          role: role,
          escrow: escrow,
          tradeSatoshis: order.tradeSatoshis,
          deadline: deadline,
        );
      case TradePosition.waitingForPayout:
        return WaitingForPayout._(
          now,
          readWarnings,
          nextTrail(),
          role: role,
          payoutAmount: order.payoutInvoiceAmount,
          tradeSatoshis: order.tradeSatoshis,
          deadline: deadline,
        );
      case TradePosition.chatting || TradePosition.fiatSent:
        return Chatting._(
          now,
          readWarnings,
          nextTrail(),
          role: role,
          fiatSent: to == TradePosition.fiatSent,
          askedToCancel: order.askedToCancel ?? false,
          peerAskedToCancel: order.peerAskedToCancel ?? false,
          chatLastIndex: order.chatLastIndex,
          deadline: deadline,
        );
      case TradePosition.inDispute:
        return InDispute._(
          now,
          readWarnings,
          nextTrail(),
          statementSubmitted: order.statementSubmitted ?? false,
        );
      case TradePosition.sendingSats:
        return SendingSats._(
          now,
          readWarnings,
          nextTrail(),
          role: role,
          summary: order.summary,
        );
      case TradePosition.routingFailed:
        return RoutingFailed._(
          now,
          readWarnings,
          nextTrail(),
          role: role,
          retries: order.payoutRetries,
          nextAttempt: order.nextPayoutRetry,
          reason: order.payoutFailureReason,
          invoiceExpired: order.payoutInvoiceExpired ?? false,
          tradeSatoshis: order.tradeSatoshis,
          summary: order.summary,
        );
      case TradePosition.succeeded:
        return Succeeded._(
          now,
          readWarnings,
          nextTrail(),
          role: role,
          summary: order.summary,
          onchainPayout: order.onchainPayout,
        );
      case TradePosition.waitingDisputeResolution:
        return WaitingDisputeResolution._(now, readWarnings, nextTrail());
      case TradePosition.makerLostDispute:
        return DisputeWon._(now, readWarnings, nextTrail());
      case TradePosition.takerLostDispute:
        return DisputeLost._(now, readWarnings, nextTrail());
      case TradePosition.expired:
        return Expired._(
          now,
          readWarnings,
          nextTrail(),
          reason: order.expiryReason,
        );
      case TradePosition.publicAgain
          when from == TradePosition.bondStep || from == TradePosition.start:
        return PreTakeEnded._(
          now,
          readWarnings,
          nextTrail(),
          bondMayHaveBeenLost: _bondMayHaveBeenLost(from, trail, terms, now),
        );
      case TradePosition.publicAgain:
        return BondForfeited._(
          now,
          readWarnings,
          nextTrail(),
          position: TradePosition.publicAgain,
        );
      case TradePosition.start ||
          TradePosition.cancelled ||
          TradePosition.notAvailable:
        // Not the position of an order read.
        return StatusNotUnderstood._(now, readWarnings, nextTrail());
    }
  }

  @override
  String toString() =>
      '$runtimeType(${warnings.isEmpty ? 'no warning' : warnings.join(', ')})';
}

/// 3: this robot holds the pre-take and must lock [bond] before [deadline] (« Lock {{amountSats}} Sats to TAKE order »).
final class WaitingForTakerBond extends TradeStatus {
  /// The bond invoice, checked: shown and paid only as its warnings allow.
  final StepInvoice bond;

  /// When the pre-take ends (`expires_at`), and how long it lasts in all (`total_secs_exp`).
  final DateTime deadline;
  final Duration stepDuration;

  const WaitingForTakerBond._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.bond,
    required this.deadline,
    required this.stepDuration,
  }) : super._();

  @override
  TradePosition get position => TradePosition.bondStep;

  @override
  StepInvoice get invoice => bond;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingForTakerBond._(
        seenAt,
        [...warnings, ...more],
        trail,
        bond: _invoiceWith(bond, more),
        deadline: deadline,
        stepDuration: stepDuration,
      );
}

/// 6: both bonds are locked; the seller's escrow and the buyer's payout are awaited.
///
/// A seller must lock [escrow]; a buyer must give a payout of [payoutAmount] (slice 2).
final class WaitingForBoth extends TradeStatus {
  final TradeRole role;

  /// The escrow invoice, for a seller once the coordinator gives it.
  final StepInvoice? escrow;

  /// What the buyer's payout must carry (`invoice_amount`).
  final Sats? payoutAmount;

  /// What this robot sends (seller) or receives (buyer).
  final Sats? tradeSatoshis;
  final DateTime deadline;

  const WaitingForBoth._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.escrow,
    required this.payoutAmount,
    required this.tradeSatoshis,
    required this.deadline,
  }) : super._();

  @override
  TradePosition get position => TradePosition.waitingForBoth;

  @override
  StepInvoice? get invoice => escrow;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingForBoth._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        escrow: _optionalInvoiceWith(escrow, more),
        payoutAmount: payoutAmount,
        tradeSatoshis: tradeSatoshis,
        deadline: deadline,
      );
}

/// 7: the buyer's payout is in; the seller's escrow is awaited (a buyer waits, « Your info looks good! »; a seller must lock [escrow]).
final class WaitingForEscrow extends TradeStatus {
  final TradeRole role;
  final StepInvoice? escrow;
  final Sats? tradeSatoshis;
  final DateTime deadline;

  const WaitingForEscrow._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.escrow,
    required this.tradeSatoshis,
    required this.deadline,
  }) : super._();

  @override
  TradePosition get position => TradePosition.waitingForEscrow;

  @override
  StepInvoice? get invoice => escrow;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingForEscrow._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        escrow: _optionalInvoiceWith(escrow, more),
        tradeSatoshis: tradeSatoshis,
        deadline: deadline,
      );
}

/// 8: the escrow is locked; the buyer's payout is awaited (a buyer must give it, « Submit payout info »; a seller waits, « The trade collateral is locked! »).
final class WaitingForPayout extends TradeStatus {
  final TradeRole role;
  final Sats? payoutAmount;
  final Sats? tradeSatoshis;
  final DateTime deadline;

  const WaitingForPayout._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.payoutAmount,
    required this.tradeSatoshis,
    required this.deadline,
  }) : super._();

  @override
  TradePosition get position => TradePosition.waitingForPayout;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingForPayout._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        payoutAmount: payoutAmount,
        tradeSatoshis: tradeSatoshis,
        deadline: deadline,
      );
}

/// 9 and 10: everything is locked, the buyer sends the fiat and both talk (« Chat with the seller » / « Chat with the buyer »).
final class Chatting extends TradeStatus {
  final TradeRole role;

  /// 10: the buyer said the fiat is sent.
  final bool fiatSent;

  /// Whether this robot asked to cancel together, and whether the peer did.
  final bool askedToCancel;
  final bool peerAskedToCancel;
  final int? chatLastIndex;

  /// When the chat's time ends: a dispute opens then (`api/logics.py:460-468`).
  final DateTime deadline;

  const Chatting._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.fiatSent,
    required this.askedToCancel,
    required this.peerAskedToCancel,
    required this.chatLastIndex,
    required this.deadline,
  }) : super._();

  @override
  TradePosition get position =>
      fiatSent ? TradePosition.fiatSent : TradePosition.chatting;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      Chatting._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        fiatSent: fiatSent,
        askedToCancel: askedToCancel,
        peerAskedToCancel: peerAskedToCancel,
        chatLastIndex: chatLastIndex,
        deadline: deadline,
      );
}

/// 11: a dispute is open (« A dispute has been opened » / « We have received your statement »).
final class InDispute extends TradeStatus {
  final bool statementSubmitted;

  const InDispute._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.statementSubmitted,
  }) : super._();

  @override
  TradePosition get position => TradePosition.inDispute;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      InDispute._(
        seenAt,
        [...warnings, ...more],
        trail,
        statementSubmitted: statementSubmitted,
      );
}

/// 13: the coordinator pays the buyer (« Attempting Lightning Payment » for a buyer, « Trade finished! » for a seller).
final class SendingSats extends TradeStatus {
  final TradeRole role;
  final TradeSummary? summary;

  const SendingSats._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.summary,
  }) : super._();

  @override
  TradePosition get position => TradePosition.sendingSats;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      SendingSats._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        summary: summary,
      );
}

/// 15: the coordinator could not pay the buyer's invoice (« Lightning Routing Failed » for a buyer, « Trade finished! » for a seller).
final class RoutingFailed extends TradeStatus {
  final TradeRole role;
  final int? retries;
  final DateTime? nextAttempt;
  final PayoutFailureReason? reason;

  /// The invoice expired or the attempts are over: the buyer must give a new one, of [tradeSatoshis].
  final bool invoiceExpired;
  final Sats? tradeSatoshis;
  final TradeSummary? summary;

  const RoutingFailed._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.retries,
    required this.nextAttempt,
    required this.reason,
    required this.invoiceExpired,
    required this.tradeSatoshis,
    required this.summary,
  }) : super._();

  @override
  TradePosition get position => TradePosition.routingFailed;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      RoutingFailed._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        retries: retries,
        nextAttempt: nextAttempt,
        reason: reason,
        invoiceExpired: invoiceExpired,
        tradeSatoshis: tradeSatoshis,
        summary: summary,
      );
}

/// 14: the trade is over and the buyer paid (« Trade finished! »). Terminal.
final class Succeeded extends TradeStatus {
  final TradeRole role;
  final TradeSummary? summary;
  final OnchainPayout? onchainPayout;

  const Succeeded._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.summary,
    required this.onchainPayout,
  }) : super._();

  @override
  TradePosition get position => TradePosition.succeeded;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      Succeeded._(
        seenAt,
        [...warnings, ...more],
        trail,
        role: role,
        summary: summary,
        onchainPayout: onchainPayout,
      );
}

/// 16: both statements are in (« We have the statements »).
final class WaitingDisputeResolution extends TradeStatus {
  const WaitingDisputeResolution._(super.seenAt, super.warnings, super.trail)
    : super._();

  @override
  TradePosition get position => TradePosition.waitingDisputeResolution;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingDisputeResolution._(seenAt, [...warnings, ...more], trail);
}

/// 17: the maker lost the dispute, so this taker won it (« You have won the dispute »). Terminal.
final class DisputeWon extends TradeStatus {
  const DisputeWon._(super.seenAt, super.warnings, super.trail) : super._();

  @override
  TradePosition get position => TradePosition.makerLostDispute;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      DisputeWon._(seenAt, [...warnings, ...more], trail);
}

/// 18: this taker lost the dispute (« You have lost the dispute »). Terminal.
final class DisputeLost extends TradeStatus {
  const DisputeLost._(super.seenAt, super.warnings, super.trail) : super._();

  @override
  TradePosition get position => TradePosition.takerLostDispute;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      DisputeLost._(seenAt, [...warnings, ...more], trail);
}

/// 5: the order ran out of time (« The order has expired »), for [reason]. Terminal.
final class Expired extends TradeStatus {
  final OrderExpiryReason? reason;

  const Expired._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.reason,
  }) : super._();

  @override
  TradePosition get position => TradePosition.expired;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      Expired._(seenAt, [...warnings, ...more], trail, reason: reason);
}

/// Error 1043: the order is cancelled, by one side or by both (« This order has been cancelled »). Terminal.
final class Cancelled extends TradeStatus {
  const Cancelled._(super.seenAt, super.warnings, super.trail) : super._();

  @override
  TradePosition get position => TradePosition.cancelled;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      Cancelled._(seenAt, [...warnings, ...more], trail);
}

/// Error 1044 after the pre-take: another robot locked its bond first, or the order left the book otherwise (expired, paused) while this robot held the pre-take. Its bond invoice was cancelled: a payment of it comes back. Terminal.
final class TakenByAnother extends TradeStatus {
  /// Whether this robot's bond may have locked and been lost since the last read that showed the pre-take (see [PreTakeEnded.bondMayHaveBeenLost]).
  final bool bondMayHaveBeenLost;

  const TakenByAnother._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.bondMayHaveBeenLost,
  }) : super._();

  @override
  TradePosition get position => TradePosition.notAvailable;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      TakenByAnother._(
        seenAt,
        [...warnings, ...more],
        trail,
        bondMayHaveBeenLost: bondMayHaveBeenLost,
      );
}

/// The order is public again after the pre-take, this robot no longer its taker: the time to lock the bond ran out, or the pre-take was cancelled. Terminal.
final class PreTakeEnded extends TradeStatus {
  /// Whether the bond may have locked and been lost meanwhile: `false` only when this status follows a read of the pre-take by less than the order's escrow duration, which no loss of a locked bond can take less than; otherwise « Nothing was taken from you » cannot be said.
  final bool bondMayHaveBeenLost;

  const PreTakeEnded._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.bondMayHaveBeenLost,
  }) : super._();

  @override
  TradePosition get position => TradePosition.publicAgain;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      PreTakeEnded._(
        seenAt,
        [...warnings, ...more],
        trail,
        bondMayHaveBeenLost: bondMayHaveBeenLost,
      );
}

/// This robot is no longer the taker after its bond locked: the order is public again ([TradePosition.publicAgain]) or no longer this robot's to see ([TradePosition.notAvailable]). Every path of the reference that leads there settles the taker's bond: this robot cancelled alone at 6 or 7, or let its own step time out (`api/logics.py:404-421`, `:445-458`, `:1108-1130`). Terminal.
final class BondForfeited extends TradeStatus {
  @override
  final TradePosition position;

  const BondForfeited._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.position,
  }) : super._();

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      BondForfeited._(
        seenAt,
        [...warnings, ...more],
        trail,
        position: position,
      );
}

/// The first answer of the trade was refused, or showed a status this app does not handle: the generic panel (« Troc cannot act on this status yet… », design note § 2.1); any next answer may follow it.
final class StatusNotUnderstood extends TradeStatus {
  const StatusNotUnderstood._(super.seenAt, super.warnings, super.trail)
    : super._();

  @override
  TradePosition get position => TradePosition.start;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      StatusNotUnderstood._(seenAt, [...warnings, ...more], trail);
}

StepInvoice _invoiceWith(StepInvoice invoice, List<TradeWarning> more) =>
    switch (invoice) {
      CheckedInvoice() => invoice.withMoreWarnings(more),
      UnusableInvoice() => invoice,
    };

StepInvoice? _optionalInvoiceWith(
  StepInvoice? invoice,
  List<TradeWarning> more,
) => invoice == null ? null : _invoiceWith(invoice, more);
