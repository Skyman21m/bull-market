import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'bolt11.dart';
import 'trade_answer.dart';
import 'trade_edges.dart';
import 'trade_record.dart';
import 'trade_terms.dart';
import 'trade_tolerances.dart';
import 'trade_warning.dart';

// The checked invoice is part of this library, so that only the state machine builds one (`_checkStepInvoice`).
part 'checked_invoice.dart';

/// What the trade remembers from one read to the next, so that each answer is checked against the trade's history and not only against itself.
///
/// It must outlive the app: the trade's use cases store its [record] after each read and resume a recorded trade with [restore], never with a fresh trail, or a coordinator could swap an invoice, or make a breach forgotten, across a restart (#86, review of #106).
/// A fresh trail comes only from [atTake], for the first read after this device took the order, and from [recovered], for a trade found by recovery, whose history is unknown and on which the wallet never pays.
@immutable
final class TradeTrail {
  /// Where the trade stood at its last status.
  final TradePosition position;

  /// When the answer of the last status was read (for [atTake], when the order was taken).
  final DateTime readAt;

  /// The payment hash of the first bond invoice and of the first escrow invoice of the trade: a step never changes its invoice.
  final String? bondHash;
  final String? escrowHash;

  /// The deadline (`expires_at`) of the last order read, for the position it was read at.
  final DateTime? deadline;

  /// When an answer last showed the pre-take, and the pre-take's deadline it gave: a pre-take that ended earlier than the escrow duration after it cannot have locked and lost the bond, and one past its deadline is gone.
  final DateTime? bondStepSeenAt;
  final DateTime? bondStepDeadline;

  /// Whether an answer of this trade was a breach of trust ([TradeWarning.isBreachOfTrust]): every later status then carries [CoordinatorInconsistent].
  final bool breached;

  /// Whether the trail started without the trade's history ([recovered]): every status then carries [TradeHistoryUnknown].
  final bool historyUnknown;

  const TradeTrail._({
    required this.position,
    required this.readAt,
    required this.bondHash,
    required this.escrowHash,
    required this.deadline,
    required this.bondStepSeenAt,
    required this.bondStepDeadline,
    required this.breached,
    required this.historyUnknown,
  });

  /// The trail of a trade this device has just taken, at [takenAt]: the first answer must be the take's own (the pre-take, or the order out of reach).
  factory TradeTrail.atTake(DateTime takenAt) => TradeTrail._(
    position: TradePosition.start,
    readAt: takenAt.toUtc(),
    bondHash: null,
    escrowHash: null,
    deadline: null,
    bondStepSeenAt: null,
    bondStepDeadline: null,
    breached: false,
    historyUnknown: false,
  );

  /// The trail of a trade found by recovery at [now], whose history is lost: any first answer is taken, and the wallet never pays on it.
  factory TradeTrail.recovered(DateTime now) => TradeTrail._(
    position: TradePosition.start,
    readAt: now.toUtc(),
    bondHash: null,
    escrowHash: null,
    deadline: null,
    bondStepSeenAt: null,
    bondStepDeadline: null,
    breached: false,
    historyUnknown: true,
  );

  /// The trail [record] holds, or [TradeRecordMalformed] when it is not one [TradeTrail.record] wrote: an unknown version or position, a payment hash that is not 64 lowercase hexadecimal characters, a time out of range.
  static Result<TradeTrail, TradeRecordMalformed> restore(
    TradeTrailRecord record,
  ) {
    const refused = Err<TradeTrail, TradeRecordMalformed>(
      TradeRecordMalformed(),
    );
    if (record.version != TradeTrailRecord.currentVersion) return refused;
    final position = TradePosition.values
        .where((value) => value.name == record.position)
        .firstOrNull;
    if (position == null) return refused;
    for (final hash in [record.bondHash, record.escrowHash]) {
      if (hash != null && !_hash.hasMatch(hash)) return refused;
    }
    final times = [
      record.readAtMicros,
      record.deadlineMicros,
      record.bondStepSeenAtMicros,
      record.bondStepDeadlineMicros,
    ];
    if (times.any(
      (micros) => micros != null && (micros < 0 || micros > _maxMicros),
    )) {
      return refused;
    }
    DateTime? at(int? micros) => micros == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    return Ok(
      TradeTrail._(
        position: position,
        readAt: DateTime.fromMicrosecondsSinceEpoch(
          record.readAtMicros,
          isUtc: true,
        ),
        bondHash: record.bondHash,
        escrowHash: record.escrowHash,
        deadline: at(record.deadlineMicros),
        bondStepSeenAt: at(record.bondStepSeenAtMicros),
        bondStepDeadline: at(record.bondStepDeadlineMicros),
        breached: record.breached,
        historyUnknown: record.historyUnknown,
      ),
    );
  }

  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');

  /// The year 9999, beyond any date a coordinator or the device's clock gives.
  static const _maxMicros = 253402300799999999;

  /// The exact, storable form of this trail: store it after each read (#87).
  TradeTrailRecord get record => TradeTrailRecord(
    version: TradeTrailRecord.currentVersion,
    position: position.name,
    readAtMicros: readAt.toUtc().microsecondsSinceEpoch,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadlineMicros: deadline?.toUtc().microsecondsSinceEpoch,
    bondStepSeenAtMicros: bondStepSeenAt?.toUtc().microsecondsSinceEpoch,
    bondStepDeadlineMicros: bondStepDeadline?.toUtc().microsecondsSinceEpoch,
    breached: breached,
    historyUnknown: historyUnknown,
  );

  TradeTrail _next({
    required TradePosition position,
    required DateTime readAt,
    String? bondHash,
    String? escrowHash,
    required DateTime? deadline,
    DateTime? bondStepSeenAt,
    DateTime? bondStepDeadline,
    required bool breached,
  }) => TradeTrail._(
    position: position,
    readAt: readAt.toUtc(),
    bondHash: this.bondHash ?? bondHash,
    escrowHash: this.escrowHash ?? escrowHash,
    deadline: deadline?.toUtc(),
    bondStepSeenAt: bondStepSeenAt?.toUtc() ?? this.bondStepSeenAt,
    bondStepDeadline: bondStepDeadline?.toUtc() ?? this.bondStepDeadline,
    breached: this.breached || breached,
    historyUnknown: historyUnknown,
  );

  TradeTrail _breach() => TradeTrail._(
    position: position,
    readAt: readAt,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadline: deadline,
    bondStepSeenAt: bondStepSeenAt,
    bondStepDeadline: bondStepDeadline,
    breached: true,
    historyUnknown: historyUnknown,
  );

  @override
  bool operator ==(Object other) =>
      other is TradeTrail && other.record == record;

  @override
  int get hashCode => record.hashCode;

  @override
  String toString() => 'TradeTrail(${position.name}, breached: $breached)';
}

/// What a screen may show, and the wallet may pay, of a taker's trade: one class per status a taker can see (design note § 3.2), built only by [TradeStatus.from] from the coordinator's answers, checked against the terms of the take and the trade's history.
///
/// The screens map each class to a panel and add no rule of their own (#88); [warnings] holds every check that failed, none of which ever triggers an action.
/// Nothing in a status is printed: its [toString] names its class and its warnings.
@immutable
sealed class TradeStatus {
  /// When the answer this status comes from was read.
  final DateTime seenAt;

  /// Every check that failed on that answer, and those carried from earlier answers of the trade ([CoordinatorInconsistent], [TradeHistoryUnknown]); an answer refused as a whole adds its own to the status it leaves in place.
  final List<TradeWarning> warnings;

  /// What the next read is checked against: store its [TradeTrail.record] after each read.
  final TradeTrail trail;

  const TradeStatus._(this.seenAt, this.warnings, this.trail);

  /// The status before any answer is understood on [trail]: a fresh trail at the take ([TradeTrail.atTake]) or after recovery ([TradeTrail.recovered]), or a trail restored when the app resumes a recorded trade ([TradeTrail.restore]). Pass it as `previous` to [from].
  static TradeStatus beforeFirstRead(TradeTrail trail) => StatusUnknown._(
    trail.readAt,
    [if (trail.breached) const CoordinatorInconsistent()],
    trail,
  );

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

  /// The status of the trade [terms] after [answer], read at [now], when the last status was [previous]: a pure function, with no clock, no I/O and no randomness, which [reader] decodes invoices for.
  ///
  /// [previous] is the last status, or [beforeFirstRead] of the trade's trail: there is no status without a trail, and a fresh trail only at the take or after recovery.
  /// - A terminal [previous] is never left: any answer returns [previous] as it is, but an order of the same status (5, 14, 17, 18), which refreshes it.
  /// - An answer refused as a whole leaves [previous] in place with the reason added ([TradeOrderMismatch], [TradeRoleMismatch], [TradeStatusRegressed], or [TradeStatusUnexpected] for an unlisted edge into a terminal position).
  /// - Any other answer gives its status, with [TradeStatusUnexpected] when its edge is not one of [TradeEdges], and the warnings of the order's checks and of its invoice.
  static TradeStatus from({
    required TradeStatus previous,
    required TradeAnswer answer,
    required TradeTerms terms,
    required DateTime now,
    required Bolt11Reader reader,
  }) {
    final trail = previous.trail;
    final from = trail.position;
    final to = _positionOf(answer, from: from, trail: trail, now: now);
    // An end is refreshed only by an order of the same status, which may say more (a summary, a transaction): being out of the order again says nothing new.
    if (previous.isTerminal &&
        (to != from ||
            answer is! TradeOrderRead ||
            to == TradePosition.publicAgain)) {
      return previous;
    }

    final refusal = _refusalOf(answer, terms, trail, to);
    if (refusal != null || to == null) {
      // [_refusalOf] refuses every answer without a position.
      final reason = refusal ?? const TradeStatusRegressed();
      return previous._rewarned([
        if (!previous.warnings.any(
          (warning) => warning.runtimeType == reason.runtimeType,
        ))
          reason,
      ], trail._breach());
    }

    final readWarnings = <TradeWarning>[
      if (trail.historyUnknown) const TradeHistoryUnknown(),
      if (trail.breached) const CoordinatorInconsistent(),
      if (!_allows(terms.role, trail, to)) const TradeStatusUnexpected(),
    ];
    TradeTrail outOfOrder() => trail._next(
      position: to,
      readAt: now,
      deadline: null,
      breached: _breaches(readWarnings),
    );
    switch (answer) {
      case TradeOrderCancelled():
        return Cancelled._(
          now,
          readWarnings,
          outOfOrder(),
          bondMayHaveBeenLost: _bondMayHaveBeenLost(trail, terms, now),
        );
      case TradeOrderNotAvailable():
        return switch (to) {
          TradePosition.preTakeUnavailable => PreTakeUnavailable._(
            now,
            readWarnings,
            outOfOrder(),
            finalFrom: _preTakeGoneAt(trail),
          ),
          _ when _isPreTake(from) => TakenByAnother._(
            now,
            readWarnings,
            outOfOrder(),
            bondMayHaveBeenLost: _bondMayHaveBeenLost(trail, terms, now),
          ),
          _ => BondForfeited._(
            now,
            readWarnings,
            outOfOrder(),
            position: TradePosition.notAvailable,
          ),
        };
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

  /// Whether [from] is a position of the pre-take: no bond locked yet, as far as the trade knows.
  static bool _isPreTake(TradePosition from) =>
      from == TradePosition.start ||
      from == TradePosition.bondStep ||
      from == TradePosition.preTakeUnavailable;

  /// Whether a trade of [role] may move from [trail]'s position to [to]: any first answer of a trade whose history is lost, otherwise the edges of [TradeEdges].
  static bool _allows(TradeRole role, TradeTrail trail, TradePosition to) =>
      (trail.historyUnknown && trail.position == TradePosition.start) ||
      TradeEdges.allows(role, trail.position, to);

  /// When error 1044 at the pre-take becomes final: the pre-take's deadline and [TradeTolerances.coordinatorLoops], by which the coordinator has expired the pre-take (`clean_orders.py:89-97`) or returned a bond that locked while the order was not public (`follow_invoices.py:252-261`); `null` while the deadline is unknown.
  static DateTime? _preTakeGoneAt(TradeTrail trail) =>
      trail.bondStepDeadline?.add(TradeTolerances.coordinatorLoops);

  /// The position an answer shows, or `null` for a status a taker is never shown: 0, 2, 4 and 12 in an order, or the order public with this robot still a participant.
  ///
  /// Error 1044 during the pre-take is [TradePosition.preTakeUnavailable] until the pre-take is certainly gone ([_preTakeGoneAt]): the maker paused the order (`api/views.py:269-275` tests `order.taker`, and a pause does not expire pre-takes, `api/logics.py:1758-1783`), or another robot's bond locked first; after the pause the pre-take shows again, with the same invoice.
  static TradePosition? _positionOf(
    TradeAnswer answer, {
    required TradePosition from,
    required TradeTrail trail,
    required DateTime now,
  }) => switch (answer) {
    TradeOrderCancelled() => TradePosition.cancelled,
    TradeOrderNotAvailable() when _isPreTake(from) => switch (_preTakeGoneAt(
      trail,
    )) {
      final gone? when !now.isBefore(gone) => TradePosition.notAvailable,
      _ => TradePosition.preTakeUnavailable,
    },
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
    TradeTrail trail,
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
    if (to == TradePosition.bondStep && !_isPreTake(trail.position)) {
      return const TradeStatusRegressed();
    }
    // A coordinator does not end a trade in this app's eyes by an answer that contradicts its history: such an answer is refused, and the reads go on.
    if (to.isTerminal && !_allows(terms.role, trail, to)) {
      return const TradeStatusUnexpected();
    }
    return null;
  }

  /// Whether this robot's bond may have locked and been lost by the read at [now], when the trade last stood at [trail]'s position.
  ///
  /// - At the take: no (the first answer is the take's own). After recovery: it cannot be said.
  /// - At the pre-take: only if the pre-take was last seen an escrow duration ago or more (less [TradeTolerances.coordinatorLoops]): the bond can lock up to that read, and a locked bond is lost at the earliest when a step is left undone that long (`api/logics.py:404-421`, `:445-458`).
  /// - At 6, 7 or 8: yes, since the order may have gone back to the book with the bond settled (a cancel or a timeout) before what followed.
  /// - Later: no; the bond is locked until the end, and settled only by a lost dispute, which its own status says.
  static bool _bondMayHaveBeenLost(
    TradeTrail trail,
    TradeTerms terms,
    DateTime now,
  ) {
    switch (trail.position) {
      case TradePosition.start:
        return trail.historyUnknown;
      case TradePosition.bondStep || TradePosition.preTakeUnavailable:
        final seen = trail.bondStepSeenAt;
        if (seen == null) return true;
        final earliestLoss = seen
            .add(terms.escrowDuration)
            .subtract(TradeTolerances.coordinatorLoops);
        return !now.isBefore(earliestLoss);
      case TradePosition.waitingForBoth ||
          TradePosition.waitingForEscrow ||
          TradePosition.waitingForPayout:
        return true;
      default:
        return false;
    }
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
          _ => _checkStepInvoice(
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

    TradeTrail nextTrail({
      StepInvoice? bond,
      StepInvoice? escrow,
    }) => trail._next(
      position: to,
      readAt: now,
      bondHash: hashOf(bond),
      escrowHash: hashOf(escrow),
      deadline: deadline,
      bondStepSeenAt: to == TradePosition.bondStep ? now : null,
      bondStepDeadline: to == TradePosition.bondStep ? deadline : null,
      // The invoice's own checks count too: a changed payment hash is a breach.
      breached: breached || _breaches(warningsWith(bond ?? escrow)),
    );

    StepInvoice? escrowForSeller() => role == TradeRole.seller
        ? invoiceOf(order.escrowInvoice, InvoiceStep.escrow)
        : null;

    switch (to) {
      case TradePosition.bondStep:
        // `package:robosats` gives status 3 only with its bond invoice.
        final bond = invoiceOf(order.bondInvoice, InvoiceStep.bond);
        if (bond == null) {
          return StatusUnknown._(now, readWarnings, nextTrail());
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
      case TradePosition.publicAgain when _isPreTake(from):
        return PreTakeEnded._(
          now,
          readWarnings,
          nextTrail(),
          bondMayHaveBeenLost: _bondMayHaveBeenLost(trail, terms, now),
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
          TradePosition.notAvailable ||
          TradePosition.preTakeUnavailable:
        // Not the position of an order read.
        return StatusUnknown._(now, readWarnings, nextTrail());
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
  /// Whether this robot's bond may have been lost before the order was cancelled: after 6, 7 or 8 the order may have gone back to the book with the bond settled, then been cancelled by its maker; never say « nothing was taken » then.
  final bool bondMayHaveBeenLost;

  const Cancelled._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.bondMayHaveBeenLost,
  }) : super._();

  @override
  TradePosition get position => TradePosition.cancelled;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      Cancelled._(
        seenAt,
        [...warnings, ...more],
        trail,
        bondMayHaveBeenLost: bondMayHaveBeenLost,
      );
}

/// Error 1044 once the pre-take is certainly gone ([PreTakeUnavailable.finalFrom]): another robot locked its bond first, or the order left the book otherwise (expired, or paused past the pre-take). Its bond invoice was cancelled: a payment of it comes back. Terminal.
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

/// No answer understood yet on the trade's trail: before the first read after the take, after recovery or when the app resumes a recorded trade ([TradeStatus.beforeFirstRead]), or after an answer refused then. The generic panel (« Troc cannot act on this status yet… », design note § 2.1) while it lasts; its position is the trail's, so the next answer is checked against the trade's history.
final class StatusUnknown extends TradeStatus {
  const StatusUnknown._(super.seenAt, super.warnings, super.trail) : super._();

  @override
  TradePosition get position => trail.position;

  @override
  bool get isTerminal => false;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      StatusUnknown._(seenAt, [...warnings, ...more], trail);
}

/// Error 1044 while this robot holds the pre-take: the order is out of this robot's reach for now, because its maker paused it or another robot's bond locked first. Not an end until [finalFrom]: after a pause the pre-take shows again with the same invoice, and if this robot's bond locked meanwhile the trade goes on at 6 (`api/views.py:269-275`, `api/logics.py:1758-1783`, `follow_invoices.py:243-261`).
final class PreTakeUnavailable extends TradeStatus {
  /// From when error 1044 means the pre-take is certainly gone (its deadline and [TradeTolerances.coordinatorLoops]), `null` while that deadline is unknown (no pre-take read yet).
  final DateTime? finalFrom;

  const PreTakeUnavailable._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.finalFrom,
  }) : super._();

  @override
  TradePosition get position => TradePosition.preTakeUnavailable;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      PreTakeUnavailable._(
        seenAt,
        [...warnings, ...more],
        trail,
        finalFrom: finalFrom,
      );
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
