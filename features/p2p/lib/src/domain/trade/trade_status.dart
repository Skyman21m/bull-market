import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'bolt11.dart';
import 'trade_answer.dart';
import 'trade_edges.dart';
import 'trade_storable.dart';
import 'trade_terms.dart';
import 'trade_tolerances.dart';
import 'trade_warning.dart';

// The checked invoice is part of this library, so that only the state machine builds one (`_checkStepInvoice`).
part 'checked_invoice.dart';

/// What the trade remembers from one read to the next, so that each answer is checked against the trade's history and not only against itself.
///
/// It must outlive the app: the trade's use cases store its [record] after each read, only when [TradeTrailRecord.mayReplace] allows it over the stored one, and resume a recorded trade with [restore], never with a fresh trail, or a coordinator could swap an invoice, or make a breach forgotten, across a restart (#86, reviews of #106).
/// A fresh trail comes only from the take's own answer ([TradeStatus.afterTake]), from [forPendingTake] for a take whose answer was lost and which has no trail yet, from the first read of an order made here ([TradeStatus.afterMake]), and from [recovered], for a trade found by recovery, whose history is unknown and on which the wallet never pays.
/// It belongs to one trade (order, coordinator, network, role, and whether it was taken or made here): [TradeStatus.from] refuses terms of another trade, and [restore] a record of another trade.
/// A maker's trail also keeps its current contract (design note `docs/design/phase-3-making-an-order.md` § 3.2): [take], [takeDeadline], [takerHashId], [takenAmount]; a taker's keeps 0 and none of them.
@immutable
final class TradeTrail {
  /// The trade this trail belongs to.
  final RobosatsNetwork network;
  final String coordinatorAlias;
  final int orderId;
  final TradeRole role;

  /// Whether the trade is a maker's, of an order made here: its terms are `TradeTerms<MadeSide>`, its edges [TradeEdges.allowsMade]. Not stored: it follows from the terms the trail is restored with.
  final bool made;

  /// Where the trade stood at its last status.
  final TradePosition position;

  /// When the answer of the last status was read (for a fresh trail, when the order was taken or found).
  final DateTime readAt;

  /// The payment hash of the first bond invoice and of the first escrow invoice of the trade: a step never changes its invoice.
  final String? bondHash;
  final String? escrowHash;

  /// The deadline (`expires_at`) of the last order read, for the position it was read at.
  final DateTime? deadline;

  /// When an answer last showed the pre-take, and the pre-take's deadline it gave (or, before any pre-take was read, the latest it can be: the take and [TradeTolerances.longestPreTake]): a pre-take that ended earlier than the escrow duration after it cannot have locked and lost the bond, and one past its deadline is gone.
  final DateTime? bondStepSeenAt;
  final DateTime? bondStepDeadline;

  /// Whether an answer of this trade was a breach of trust ([TradeWarning.isBreachOfTrust]): every later status then carries [CoordinatorInconsistent].
  final bool breached;

  /// Whether the trail started without the trade's history ([recovered]): every status then carries [TradeHistoryUnknown].
  final bool historyUnknown;

  /// A maker's current contract, each lock of a taker's bond making one (`Logics.finalize_contract`, `api/logics.py:1321-1380`): its index, 0 for the first contract this trail saw; the deadline the coordinator gave it at 6, 7 or 8 (the lock's time and the escrow duration, `:1338-1340`, which only the chat's start changes); its taker's hash id (`taker_hash_id`, `api/views.py:314-317`); and for a range, the amount its take chose (`:1329-1330`). `null` before any contract was read, and always for a taker.
  final int take;
  final DateTime? takeDeadline;
  final String? takerHashId;
  final double? takenAmount;

  const TradeTrail._({
    required this.network,
    required this.coordinatorAlias,
    required this.orderId,
    required this.role,
    required this.made,
    required this.position,
    required this.readAt,
    required this.bondHash,
    required this.escrowHash,
    required this.deadline,
    required this.bondStepSeenAt,
    required this.bondStepDeadline,
    required this.breached,
    required this.historyUnknown,
    required this.take,
    required this.takeDeadline,
    required this.takerHashId,
    required this.takenAmount,
  });

  /// A fresh trail of the trade [terms] at [at]: only [TradeStatus.afterTake], [TradeStatus.afterMake], [forPendingTake] and [recovered] make one.
  factory TradeTrail._fresh(
    TradeTerms terms,
    DateTime at, {
    required bool historyUnknown,
  }) => TradeTrail._(
    network: terms.network,
    coordinatorAlias: terms.coordinator.shortAlias,
    orderId: terms.orderId,
    role: terms.role,
    made: _isMade(terms),
    position: TradePosition.start,
    readAt: at.toUtc(),
    bondHash: null,
    escrowHash: null,
    deadline: null,
    bondStepSeenAt: null,
    bondStepDeadline: null,
    breached: false,
    historyUnknown: historyUnknown,
    take: 0,
    takeDeadline: null,
    takerHashId: null,
    takenAmount: null,
  );

  /// Whether [terms] are a maker's: every factory of [TradeTerms] instantiates the type of its side, so the side tells.
  static bool _isMade(TradeTerms terms) => terms.side is MadeSide;

  /// The trail of a take of [terms] made at [takenAt] whose answer was lost (the request timed out), for the first read of the order after it: the first answer must be one a take gives (the pre-take, or the order out of reach).
  ///
  /// Only for a pending take that has no trail recorded yet: a trade with a recorded trail resumes from it ([restore]), and a take whose answer came resumes from [TradeStatus.afterTake]. That is a written rule of #87, pinned by its architecture test (only the take use case and the resolution of a pending take name this factory): the domain cannot know whether a trail was recorded.
  factory TradeTrail.forPendingTake(TradeTerms terms, DateTime takenAt) =>
      TradeTrail._fresh(terms, takenAt, historyUnknown: false);

  /// The trail of a trade of [terms] found by recovery at [now], whose history is lost: any first answer is taken, and the wallet never pays on it.
  factory TradeTrail.recovered(TradeTerms terms, DateTime now) =>
      TradeTrail._fresh(terms, now, historyUnknown: true);

  /// The trail [record] holds for the trade [terms], resumed at [now], or why not:
  /// - [TradeRecordOfAnotherTrade] when the record is of another order, coordinator, network or role than [terms];
  /// - [TradeRecordMalformed] when it is not one [TradeTrail.record] wrote: an unknown version or position, a payment hash or a taker's hash id that is not 64 lowercase hexadecimal characters, a time out of range, a read after [now] by more than [TradeTolerances.clockStep], a last read of the pre-take after the last read, a contract index below 0 or above 0 without its deadline, an amount taken that is not a positive figure below 10^10, or any contract for terms of a taker.
  static Result<TradeTrail, TradeRecordRefusal> restore(
    TradeTrailRecord record, {
    required TradeTerms terms,
    required DateTime now,
  }) {
    const refused = Err<TradeTrail, TradeRecordRefusal>(TradeRecordMalformed());
    if (record.version != TradeTrailRecord.currentVersion) return refused;
    if (record.network != terms.network.name ||
        record.coordinatorAlias != terms.coordinator.shortAlias ||
        record.orderId != terms.orderId ||
        record.role != terms.role.name) {
      return const Err(TradeRecordOfAnotherTrade());
    }
    final position = TradePosition.values
        .where((value) => value.name == record.position)
        .firstOrNull;
    if (position == null) return refused;
    for (final hash in [
      record.bondHash,
      record.escrowHash,
      record.takerHashId,
    ]) {
      if (hash != null && !_hash.hasMatch(hash)) return refused;
    }
    final made = _isMade(terms);
    final amount = record.takenAmount;
    if (record.take < 0 ||
        (record.take > 0 && record.takeDeadlineMicros == null) ||
        (amount != null &&
            (!amount.isFinite || amount <= 0 || amount >= _maxAmount)) ||
        (!made &&
            (record.take != 0 ||
                record.takeDeadlineMicros != null ||
                record.takerHashId != null ||
                amount != null))) {
      return refused;
    }
    final times = [
      record.readAtMicros,
      record.deadlineMicros,
      record.bondStepSeenAtMicros,
      record.bondStepDeadlineMicros,
      record.takeDeadlineMicros,
    ];
    if (times.any(
      (micros) => micros != null && (micros < 0 || micros > _maxMicros),
    )) {
      return refused;
    }
    final latest = now.toUtc().add(TradeTolerances.clockStep);
    if (record.readAtMicros > latest.microsecondsSinceEpoch) return refused;
    if (record.bondStepSeenAtMicros case final seen?
        when seen > record.readAtMicros) {
      return refused;
    }
    DateTime? at(int? micros) => micros == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    return Ok(
      TradeTrail._(
        network: terms.network,
        coordinatorAlias: terms.coordinator.shortAlias,
        orderId: terms.orderId,
        role: terms.role,
        made: made,
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
        take: record.take,
        takeDeadline: at(record.takeDeadlineMicros),
        takerHashId: record.takerHashId,
        takenAmount: amount,
      ),
    );
  }

  static final RegExp _hash = RegExp(r'^[0-9a-f]{64}$');

  /// The bound of an amount taken, as `trade_trails` keeps it (`CHECK (taken_amount > 0 AND taken_amount < 10000000000)`, schema 8): above the order model's (`max_digits=18, decimal_places=8`, `api/models/order.py:77-84`).
  static const double _maxAmount = 1e10;

  /// The year 9999, beyond any date a coordinator or the device's clock gives.
  static const _maxMicros = 253402300799999999;

  /// Whether this trail belongs to the trade [terms], of the same side.
  bool isOf(TradeTerms terms) =>
      network == terms.network &&
      coordinatorAlias == terms.coordinator.shortAlias &&
      orderId == terms.orderId &&
      role == terms.role &&
      made == _isMade(terms);

  /// The exact, storable form of this trail: store it after each read, when it [TradeTrailRecord.mayReplace] the stored one (#87).
  TradeTrailRecord get record => TradeTrailRecord(
    version: TradeTrailRecord.currentVersion,
    network: network.name,
    coordinatorAlias: coordinatorAlias,
    orderId: orderId,
    role: role.name,
    position: position.name,
    readAtMicros: readAt.toUtc().microsecondsSinceEpoch,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadlineMicros: deadline?.toUtc().microsecondsSinceEpoch,
    bondStepSeenAtMicros: bondStepSeenAt?.toUtc().microsecondsSinceEpoch,
    bondStepDeadlineMicros: bondStepDeadline?.toUtc().microsecondsSinceEpoch,
    breached: breached,
    historyUnknown: historyUnknown,
    take: take,
    takeDeadlineMicros: takeDeadline?.toUtc().microsecondsSinceEpoch,
    takerHashId: takerHashId,
    takenAmount: takenAmount,
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
    _Contract? contract,
  }) => TradeTrail._(
    network: network,
    coordinatorAlias: coordinatorAlias,
    orderId: orderId,
    role: role,
    made: made,
    position: position,
    readAt: readAt.toUtc(),
    bondHash: this.bondHash ?? bondHash,
    // A maker's next contract replaces the escrow's pinned hash, in the same write: with the new contract's, or with none (design note `docs/design/phase-3-making-an-order.md` § 3.5).
    escrowHash: contract != null && contract.isNext
        ? escrowHash
        : this.escrowHash ?? escrowHash,
    deadline: deadline?.toUtc(),
    bondStepSeenAt: bondStepSeenAt?.toUtc() ?? this.bondStepSeenAt,
    bondStepDeadline: bondStepDeadline?.toUtc() ?? this.bondStepDeadline,
    breached: this.breached || breached,
    historyUnknown: historyUnknown,
    take: contract?.take ?? take,
    takeDeadline: contract?.deadline?.toUtc() ?? takeDeadline,
    takerHashId: contract?.taker ?? takerHashId,
    takenAmount: contract?.amount ?? takenAmount,
  );

  /// The same trail after a refused answer read at [now]: the breach recorded, and the read too, so that a later write never looks older.
  TradeTrail _breach(DateTime now) => TradeTrail._(
    network: network,
    coordinatorAlias: coordinatorAlias,
    orderId: orderId,
    role: role,
    made: made,
    position: position,
    readAt: now.toUtc().isAfter(readAt) ? now.toUtc() : readAt,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadline: deadline,
    bondStepSeenAt: bondStepSeenAt,
    bondStepDeadline: bondStepDeadline,
    breached: true,
    historyUnknown: historyUnknown,
    take: take,
    takeDeadline: takeDeadline,
    takerHashId: takerHashId,
    takenAmount: takenAmount,
  );

  @override
  bool operator ==(Object other) =>
      other is TradeTrail && other.made == made && other.record == record;

  @override
  int get hashCode => Object.hash(made, record);

  @override
  String toString() =>
      'TradeTrail($coordinatorAlias#$orderId, ${position.name}, breached: $breached)';
}

/// What a maker's read of 6 or later says of its contract, against the one its trail keeps (design note `docs/design/phase-3-making-an-order.md` § 3.2): the trail's contract after the read ([take], [deadline], [taker], [amount], each `null` to keep the trail's), whether the read opens the next contract ([isNext]), whether it moves the contract's deadline back ([movedBack]), and why it is refused ([refusal]), if it is.
@immutable
final class _Contract {
  final int take;
  final DateTime? deadline;
  final String? taker;
  final double? amount;
  final bool isNext;
  final bool movedBack;
  final TradeWarning? refusal;

  const _Contract({
    required this.take,
    this.deadline,
    this.taker,
    this.amount,
    this.isNext = false,
    this.movedBack = false,
    this.refusal,
  });
}

/// What a screen may show, and the wallet may pay, of a trade: one class per status a taker can see (design note § 3.2), and those a maker sees of its own order (`docs/design/phase-3-making-an-order.md` § 3.2: [WaitingForMakerBond], [MakerOrderPublic]), built only by [TradeStatus.from] from the coordinator's answers, checked against the terms of the take or of the make and the trade's history.
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

  /// The status before any answer is understood on [trail]: a trail restored when the app resumes a recorded trade ([TradeTrail.restore]), a fresh one after recovery ([TradeTrail.recovered]) or for a pending take ([TradeTrail.forPendingTake]). Pass it as `previous` to [from]. A restored trail at an end gives an end at once.
  static TradeStatus beforeFirstRead(TradeTrail trail) => StatusUnknown._(
    trail.readAt,
    [if (trail.breached) const CoordinatorInconsistent()],
    trail,
  );

  /// The first status of a trade this device has just taken: [started], the take's own answer (`OrderTakeStarted`, which only `CoordinatorClient.takeOrder` gives), read at [now] on a fresh trail of [terms].
  ///
  /// The only way to start a trade from its take: a trade whose take answered `OrderAlreadyTakenByThisRobot` resumes from its recorded trail, or as [TradeTrail.recovered] when none was recorded; `OrderNotTaken` makes no trade.
  static TradeStatus afterTake(
    OrderTakeStarted started, {
    required TradeTerms terms,
    required DateTime now,
    required Bolt11Reader reader,
  }) => from(
    previous: beforeFirstRead(
      TradeTrail._fresh(terms, now, historyUnknown: false),
    ),
    answer: TradeOrderRead(started.order),
    terms: terms,
    now: now,
    reader: reader,
  );

  /// The first status of an order this device has just made: [firstRead], the first answer about it once the make is known to have made it (design note `docs/design/phase-3-making-an-order.md` § 3.4), read at [now] on a fresh trail of [terms].
  ///
  /// The only way to start a maker's trade, named only where § 3.4 starts its trail (after the make's own answer, at the resolution of a make whose answer was lost, and for a confirmed make whose first trail was not written): the first read can only be the maker bond (0), the order expired at 0 (5) or error 1043, since no bond invoice exists before that read; anything else is refused or warned as an edge the reference never takes. Error 1043 ends the trade but proves nothing about the maker (its answer names no participant, `api/views.py:258-260`), so it never confirms a make.
  static TradeStatus afterMake(
    TradeAnswer firstRead, {
    required TradeTerms<MadeSide> terms,
    required DateTime now,
    required Bolt11Reader reader,
  }) => from(
    previous: beforeFirstRead(
      TradeTrail._fresh(terms, now, historyUnknown: false),
    ),
    answer: firstRead,
    terms: terms,
    now: now,
    reader: reader,
  );

  /// Where the trade stands for the edges of [TradeEdges].
  TradePosition get position;

  /// Whether the trade is over for this robot: a terminal status is never left by [from].
  bool get isTerminal => position.isTerminal;

  /// The hold invoice this robot must lock at this status, checked: the bond at the pre-take, the maker bond at 0, the escrow of a seller at 6 and 7; `null` elsewhere.
  StepInvoice? get invoice => null;

  /// Whether this status has a warning of type [T].
  bool has<T extends TradeWarning>() => warnings.any((warning) => warning is T);

  /// The same status with [more] warnings and [trail]: the invoice it holds, if any, takes them too.
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail);

  /// The status of the trade [terms] after [answer], read at [now], when the last status was [previous]: a pure function, with no clock, no I/O and no randomness, which [reader] decodes invoices for.
  ///
  /// [previous] is the last status, or [beforeFirstRead] of the trade's trail: there is no status without a trail, and a fresh trail only at the take ([afterTake]), at the first read of an order made here ([afterMake]), for a pending take, or after recovery.
  /// Terms of another trade than the trail's are refused ([TradeOrderMismatch]), and the trail is left as it is. Terms of a maker (`TradeTerms<MadeSide>`) are followed along a maker's edges ([TradeEdges.allowsMade]) with a maker's checks (design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3), the rules below applying the same.
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
    if (!trail.isOf(terms)) {
      return previous._rewarned([
        if (!previous.has<TradeOrderMismatch>()) const TradeOrderMismatch(),
      ], trail);
    }
    // A maker's trade has its own positions, edges and checks (#178). Every factory of [TradeTerms] instantiates the type of its side, so these tests are those of the side.
    if (terms is TradeTerms<MadeSide>) {
      return _fromMade(previous, answer, terms, now, reader);
    }
    // No other side exists: refused, as of a role this state machine does not know, and the trail left as it is.
    if (terms is! TradeTerms<TakenSide>) {
      return previous._rewarned([
        if (!previous.has<TradeRoleMismatch>()) const TradeRoleMismatch(),
      ], trail);
    }
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
      ], trail._breach(now));
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
      // Error 1044 before any pre-take was read: the pre-take ends at the latest a longest pre-take after the take.
      bondStepDeadline:
          to == TradePosition.preTakeUnavailable &&
              trail.bondStepDeadline == null
          ? trail.readAt.add(TradeTolerances.longestPreTake)
          : null,
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
          TradePosition.preTakeUnavailable => switch (outOfOrder()) {
            final onHold => PreTakeUnavailable._(
              now,
              readWarnings,
              onHold,
              finalFrom: _preTakeGoneAt(onHold),
            ),
          },
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

  /// When error 1044 at the pre-take becomes final: the pre-take's deadline (or, before any pre-take was read, the take and [TradeTolerances.longestPreTake]) and [TradeTolerances.coordinatorLoops], by which the coordinator has expired the pre-take (`clean_orders.py:89-97`) or returned a bond that locked while the order was not public (`follow_invoices.py:252-261`); `null` only before the first answer.
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
    TradeTerms<TakenSide> terms,
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
  static bool _termsChanged(
    CoordinatorOrder order,
    TradeTerms<TakenSide> terms,
  ) {
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
    required TradeTerms<TakenSide> terms,
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
          currency: terms.currency,
          escrowDuration: terms.escrowDuration,
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
          currency: terms.currency,
          escrowDuration: terms.escrowDuration,
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
          amount: terms.amount,
          currency: terms.currency,
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
        return DisputeWon._(
          now,
          readWarnings,
          nextTrail(),
          position: TradePosition.makerLostDispute,
        );
      case TradePosition.takerLostDispute:
        return DisputeLost._(
          now,
          readWarnings,
          nextTrail(),
          position: TradePosition.takerLostDispute,
        );
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
      case TradePosition.makerBondStep ||
          TradePosition.public ||
          TradePosition.paused:
        // Never the position of a taker's read ([_positionOf]).
        return StatusUnknown._(now, readWarnings, nextTrail());
    }
  }

  // A maker's trade (#178; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3): the same rules as a taker's, along a maker's edges, with a maker's checks.

  /// [from] for a maker's [terms].
  static TradeStatus _fromMade(
    TradeStatus previous,
    TradeAnswer answer,
    TradeTerms<MadeSide> terms,
    DateTime now,
    Bolt11Reader reader,
  ) {
    final trail = previous.trail;
    final maker = terms.side.maker;
    final from = trail.position;
    final to = _madePositionOf(answer);
    // An end is refreshed only by an order of the same status, as a taker's.
    if (previous.isTerminal && (to != from || answer is! TradeOrderRead)) {
      return previous;
    }
    final contract = switch (answer) {
      TradeOrderRead(:final order) when to != null => _contractOf(
        order,
        to,
        trail,
        maker,
      ),
      _ => null,
    };
    final refusal = _madeRefusalOf(answer, terms, trail, to, contract);
    if (refusal != null || to == null) {
      // [_madeRefusalOf] refuses every answer without a position.
      final reason = refusal ?? const TradeStatusRegressed();
      return previous._rewarned([
        if (!previous.warnings.any(
          (warning) => warning.runtimeType == reason.runtimeType,
        ))
          reason,
      ], trail._breach(now));
    }
    final readWarnings = <TradeWarning>[
      if (trail.historyUnknown) const TradeHistoryUnknown(),
      if (trail.breached) const CoordinatorInconsistent(),
      if (!_allowsMade(terms.role, trail, to)) const TradeStatusUnexpected(),
    ];
    switch (answer) {
      case TradeOrderRead(:final order):
        return _ofMadeOrder(
          order,
          to: to,
          trail: trail,
          terms: terms,
          now: now,
          reader: reader,
          contract: contract,
          readWarnings: [
            ...readWarnings,
            ..._madeOrderWarnings(order, maker, to, from, trail, contract),
          ],
        );
      case TradeOrderCancelled():
        return Cancelled._(
          now,
          readWarnings,
          trail._next(
            position: TradePosition.cancelled,
            readAt: now,
            deadline: null,
            breached: _breaches(readWarnings),
          ),
          bondMayHaveBeenLost: _bondMayHaveBeenLost(trail, terms, now),
        );
      case TradeOrderNotAvailable():
        // Refused above: a maker is never given error 1044.
        return previous;
    }
  }

  /// Whether a maker's trade of [role] may move from [trail]'s position to [to]: any first answer of a trade whose history is lost, otherwise the edges of [TradeEdges.allowsMade].
  static bool _allowsMade(TradeRole role, TradeTrail trail, TradePosition to) =>
      (trail.historyUnknown && trail.position == TradePosition.start) ||
      TradeEdges.allowsMade(role, trail.position, to);

  /// The position an answer shows to a maker, or `null` for what a maker is never shown: error 1044, and 3, 4 or 12 in an order (status 3 is shown only to a robot that holds a pre-take, which a maker cannot, `api/views.py:381-396`, `api/logics.py:75-100`; 4 and 12 are error 1043, `api/views.py:258-260`).
  static TradePosition? _madePositionOf(TradeAnswer answer) => switch (answer) {
    TradeOrderCancelled() => TradePosition.cancelled,
    TradeOrderNotAvailable() => null,
    TradeOrderRead(:final order) => switch (order.status) {
      CoordinatorOrderStatus.waitingForMakerBond => TradePosition.makerBondStep,
      CoordinatorOrderStatus.public => TradePosition.public,
      CoordinatorOrderStatus.paused => TradePosition.paused,
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
      CoordinatorOrderStatus.waitingForTakerBond ||
      CoordinatorOrderStatus.cancelled ||
      CoordinatorOrderStatus.collaborativelyCancelled => null,
    },
  };

  /// Why a maker's [answer] is refused as a whole, or `null` when it is not.
  static TradeWarning? _madeRefusalOf(
    TradeAnswer answer,
    TradeTerms<MadeSide> terms,
    TradeTrail trail,
    TradePosition? to,
    _Contract? contract,
  ) {
    if (answer case TradeOrderRead(:final order)) {
      if (order.coordinator != terms.coordinator ||
          order.network != terms.network ||
          order.id != terms.orderId) {
        return const TradeOrderMismatch();
      }
      // `package:robosats` has checked that the roles agree with each other, with the order's type and with the robot that asked: a maker's answer shows this robot as the maker, on the side its order gives it (a buy order's maker buys), the mirror of a taker's rule.
      if (!order.isMaker || order.isBuyer != (terms.role == TradeRole.buyer)) {
        return const TradeRoleMismatch();
      }
    }
    // Error 1044 goes only to a robot that is neither the maker nor the taker of an order that is not public (`api/views.py:269-275`): never to a maker.
    if (answer is TradeOrderNotAvailable) return const TradeStatusUnexpected();
    if (to == null) return const TradeStatusRegressed();
    // The maker bond is one invoice for the order's whole life (`api/logics.py:1259-1263`), asked only until it locks (`follow_invoices.py:233-240`): the bond step is never shown again after it.
    if (to == TradePosition.makerBondStep &&
        trail.position != TradePosition.start &&
        trail.position != TradePosition.makerBondStep) {
      return const TradeStatusRegressed();
    }
    // A coordinator does not end a trade in this app's eyes by an answer that contradicts its history, as for a taker.
    if (to.isTerminal && !_allowsMade(terms.role, trail, to)) {
      return const TradeStatusUnexpected();
    }
    return contract?.refusal;
  }

  /// The positions of a maker's contract that carry its deadline (`api/logics.py:1338-1340`, unchanged from 6 to 7, 6 to 8 and at 7 and 8, `:920-924`, `:946`, `:1471-1473`), and those a next contract is read from (as `trade_trails_forward` lets `take` move, schema 8).
  static const _contractSteps = {
    TradePosition.waitingForBoth,
    TradePosition.waitingForEscrow,
    TradePosition.waitingForPayout,
  };
  static const _beforeNextContract = {
    TradePosition.public,
    TradePosition.paused,
    TradePosition.waitingForBoth,
    TradePosition.waitingForEscrow,
    TradePosition.waitingForPayout,
  };

  /// What a maker's read of [order] at [to] says of its contract against the one [trail] keeps (design note `docs/design/phase-3-making-an-order.md` § 3.2), or `null` for a read that names none: 0, 1, 2, and 5, which may name a contract the trail never saw (one that expired at 6, 7 or 8 after a return to the book) and says nothing of the current one.
  ///
  /// At 6, 7 or 8, against the kept contract's deadline: none kept yet, this read opens one (its deadline, taker and amount kept, `take` unchanged); the same deadline and the same taker, the same contract; a later deadline, the next contract (`take` + 1, its deadline, taker and amount), whatever the positions read before, the taker possibly the same robot (a taker whose bond was settled may take again, `api/logics.py:471-483`), but only from the positions a next contract is read from, the chat never going back to the book; the same or an earlier deadline with another taker, [TradeTakerChanged]; an earlier one with the same taker, the same contract, its deadline moved back ([DeadlineMovedBack]); after a return to the book, a deadline that is not later, refused ([TradeStatusUnexpected]): the book never gives back a contract it ended.
  /// From 9 on: the kept taker, or [TradeTakerChanged]; with none kept (the maker's step done elsewhere, with the Garage Key), this read's taker and amount kept, and no deadline.
  /// A range's order that names no amount taken at 6 or later is refused ([TradeTermsChanged]): the reference always gives it (`api/logics.py:1329-1330`), and the contract cannot be told without it.
  static _Contract? _contractOf(
    CoordinatorOrder order,
    TradePosition to,
    TradeTrail trail,
    MakerTerms maker,
  ) {
    final atStep = _contractSteps.contains(to);
    final afterStep = !atStep && order.status.wire >= 9;
    // `package:robosats` refuses a participant's answer at 6 or later that names no taker.
    final taker = order.taker?.hex;
    if ((!atStep && !afterStep) || taker == null) return null;
    final double? amount;
    switch (maker.amount) {
      case FixedOrderAmount():
        amount = null;
      case RangeOrderAmount():
        final taken = order.takenAmount;
        if (taken == null) {
          return _Contract(take: trail.take, refusal: const TradeTermsChanged());
        }
        amount = taken.value;
    }
    final keptTaker = trail.takerHashId;
    final kept = trail.takeDeadline;
    if (afterStep || kept == null) {
      if (keptTaker != null && keptTaker != taker) {
        return _Contract(take: trail.take, refusal: const TradeTakerChanged());
      }
      return _Contract(
        take: trail.take,
        deadline: kept ?? (atStep ? order.expiresAt : null),
        taker: keptTaker ?? taker,
        amount: trail.takenAmount ?? amount,
      );
    }
    final deadline = order.expiresAt;
    if (deadline.isAfter(kept)) {
      if (!_beforeNextContract.contains(trail.position)) {
        // From the chat on, no contract comes back to a step: the edge says it ([TradeStatusUnexpected]), and nothing of the contract is written.
        return _Contract(take: trail.take);
      }
      return _Contract(
        take: trail.take + 1,
        deadline: deadline,
        taker: taker,
        amount: amount,
        isNext: true,
      );
    }
    if (trail.position == TradePosition.public ||
        trail.position == TradePosition.paused) {
      return _Contract(
        take: trail.take,
        refusal: const TradeStatusUnexpected(),
      );
    }
    if (keptTaker != null && keptTaker != taker) {
      return _Contract(take: trail.take, refusal: const TradeTakerChanged());
    }
    return _Contract(
      take: trail.take,
      taker: keptTaker ?? taker,
      amount: trail.takenAmount ?? amount,
      movedBack: deadline.isBefore(kept),
    );
  }

  /// The checks of a maker's [order] against what the maker asked and the trade's history (design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3).
  ///
  /// No check compares the trade's sats with a price: the coordinator fixes them at the take, at its price then, up to a day after the make (`api/logics.py:1332-1335`), and a warning on them would fire after any move of the market (§ 3.3); the gap from the rate of the creation is information ([MakerTerms.rateGap]), and the wallet's ceiling bounds what it pays ([MakerTerms.escrowCeilingFor]).
  static List<TradeWarning> _madeOrderWarnings(
    CoordinatorOrder order,
    MakerTerms maker,
    TradePosition to,
    TradePosition from,
    TradeTrail trail,
    _Contract? contract,
  ) {
    final warnings = <TradeWarning>[];
    if (_madeTermsChanged(order, maker, to, trail, contract)) {
      warnings.add(const TradeTermsChanged());
    }
    // The maker bond, made at the maker's first read seconds after the make, at the coordinator's price then (`api/logics.py:1266-1268`).
    if (order.bondInvoice case final bond? when to == TradePosition.makerBondStep) {
      if (!maker.bondAgrees(bond.satoshis)) {
        warnings.add(const BondAmountOutsideOrder());
      }
    }
    final trade = order.tradeSatoshis;
    final Sats? paid;
    switch (maker.role) {
      case TradeRole.seller:
        final escrow = order.escrowInvoice?.satoshis;
        if (escrow != null && escrow != trade) {
          warnings.add(const EscrowAmountMismatch());
        }
        paid = escrow ?? trade;
      case TradeRole.buyer:
        final payout = order.payoutInvoiceAmount;
        if (payout != null && payout != trade) {
          warnings.add(const PayoutAmountMismatch());
        }
        paid = payout ?? trade;
    }
    // From the take on, `satoshis_now` is the order's `last_satoshis`, the trade's sats fixed then (`api/views.py:324`): the fee is what the escrow adds to them, or the payout takes from them (`api/logics.py:650-668`, `:733-749`).
    if (order.isParticipant && order.status.wire >= 6) {
      final last = order.satoshisNow;
      if (last == null ||
          (paid != null && !maker.feeAgrees(tradeSatoshis: last, paid: paid))) {
        warnings.add(const MakerFeeAboveAnnounced());
      }
    }
    final movedBack =
        (contract?.movedBack ?? false) ||
        switch (trail.deadline) {
          final earlier? => from == to && order.expiresAt.isBefore(earlier),
          null => false,
        };
    if (movedBack) warnings.add(const DeadlineMovedBack());
    return warnings;
  }

  /// Whether a maker's [order] read at [to] is not the order it asked: its type, currency, premium (an order made here is never priced in sats), bond size, escrow duration, payment method text as sent, password (none before issue #189), public duration where the read gives it (5, 13 to 15, `api/views.py:490-498`), fixed amount or range's bounds; and for a range, an amount taken before any take (0 to 2), outside the range, or other than the one the trail keeps for the same contract (another amount at a next contract being that contract's own).
  static bool _madeTermsChanged(
    CoordinatorOrder order,
    MakerTerms maker,
    TradePosition to,
    TradeTrail trail,
    _Contract? contract,
  ) {
    if (order.currency != maker.currency || order.type != maker.type) {
      return true;
    }
    if (!_samePercent(order.bondSize.percent, maker.bondSize.percent) ||
        order.escrowDuration != maker.escrowDuration) {
      return true;
    }
    if (order.isExplicit || order.explicitSatoshis != null) return true;
    final premium = order.premium;
    if (premium == null ||
        !_samePercent(premium.percent, maker.premium.percent)) {
      return true;
    }
    if (order.paymentMethods.text != maker.request.paymentMethod) return true;
    if (order.hasPassword) return true;
    if (order.publicDuration case final shown?
        when shown != maker.publicDuration) {
      return true;
    }
    switch ((maker.amount, order.amount)) {
      case (
        FixedOrderAmount(amount: final asked),
        FixedOrderAmount(:final amount),
      ):
        return !_sameFiat(amount.value, asked.value);
      case (
        RangeOrderAmount(min: final askedMin, max: final askedMax),
        RangeOrderAmount(:final min, :final max),
      ):
        if (!_sameFiat(min.value, askedMin.value) ||
            !_sameFiat(max.value, askedMax.value)) {
          return true;
        }
        final taken = order.takenAmount;
        if (taken == null) return false;
        if (to == TradePosition.makerBondStep ||
            to == TradePosition.public ||
            to == TradePosition.paused) {
          return true;
        }
        if (maker.contractAmount(taken) == null) return true;
        final kept = trail.takenAmount;
        return contract != null &&
            !contract.isNext &&
            kept != null &&
            !_sameFiat(taken.value, kept);
      default:
        return true;
    }
  }

  static TradeStatus _ofMadeOrder(
    CoordinatorOrder order, {
    required TradePosition to,
    required TradeTrail trail,
    required TradeTerms<MadeSide> terms,
    required DateTime now,
    required Bolt11Reader reader,
    required _Contract? contract,
    required List<TradeWarning> readWarnings,
  }) {
    final maker = terms.side.maker;
    final breached = _breaches(readWarnings);
    final deadline = order.expiresAt;
    final role = terms.role;
    final isNext = contract?.isNext ?? false;

    StepInvoice? invoiceOf(HoldInvoice? hold, InvoiceStep step) {
      if (hold == null) return null;
      final invoice = _checkStepInvoice(
        hold: hold,
        step: step,
        terms: terms,
        reader: reader,
        // A next contract asks a new escrow (`api/logics.py:1218`, `:1491-1495`): the pinned one is compared below, not kept.
        pinnedHash: switch (step) {
          InvoiceStep.bond => trail.bondHash,
          InvoiceStep.escrow => isNext ? null : trail.escrowHash,
        },
        stepDeadline: deadline,
        now: now,
        readWarnings: readWarnings,
      );
      // An escrow of a contract after the first is one only when it is the one its contract opened with: never the contract before's, and never one first shown after an opening read that carried none, which nothing can compare with the escrows of earlier contracts (the trail keeps the current one only, schema 8).
      if (step == InvoiceStep.escrow &&
          invoice is CheckedInvoice &&
          (isNext
              ? invoice.paymentHash == trail.escrowHash
              : trail.take > 0 && trail.escrowHash == null)) {
        return invoice.withMoreWarnings(const [EscrowNotOfThisContract()]);
      }
      return invoice;
    }

    List<TradeWarning> warningsWith(StepInvoice? invoice) => switch (invoice) {
      CheckedInvoice(:final warnings) => warnings,
      UnusableInvoice(:final reason) => [...readWarnings, reason],
      null => readWarnings,
    };

    // An escrow not of this contract is never pinned, so that each later read of it is refused again.
    String? hashOf(StepInvoice? invoice) => switch (invoice) {
      CheckedInvoice(:final paymentHash, :final warnings)
          when !warnings.any((w) => w is EscrowNotOfThisContract) =>
        paymentHash,
      _ => null,
    };

    TradeTrail nextTrail({StepInvoice? bond, StepInvoice? escrow}) =>
        trail._next(
          position: to,
          readAt: now,
          bondHash: hashOf(bond),
          escrowHash: hashOf(escrow),
          deadline: deadline,
          // The invoice's own checks count too: a changed payment hash, or an escrow not of this contract, is a breach.
          breached: breached || _breaches(warningsWith(bond ?? escrow)),
          contract: contract,
        );

    StepInvoice? escrowForSeller() => role == TradeRole.seller
        ? invoiceOf(order.escrowInvoice, InvoiceStep.escrow)
        : null;

    switch (to) {
      case TradePosition.makerBondStep:
        final bond = invoiceOf(order.bondInvoice, InvoiceStep.bond);
        if (bond == null) {
          return StatusUnknown._(now, readWarnings, nextTrail());
        }
        return WaitingForMakerBond._(
          now,
          warningsWith(bond),
          nextTrail(bond: bond),
          bond: bond,
          deadline: deadline,
          stepDuration: order.stepDuration,
        );
      case TradePosition.public || TradePosition.paused:
        final next = nextTrail();
        return MakerOrderPublic._(
          now,
          readWarnings,
          next,
          paused: to == TradePosition.paused,
          deadline: deadline,
          backInBook: next.takeDeadline != null,
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
          currency: terms.currency,
          escrowDuration: terms.escrowDuration,
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
          currency: terms.currency,
          escrowDuration: terms.escrowDuration,
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
        final next = nextTrail();
        // The contract's fiat amount: the order's fixed amount, or the range's amount its take chose, kept with the contract ([_contractOf] refuses a range's order without it).
        final amount = switch (maker.amount) {
          FixedOrderAmount(:final amount) => amount,
          RangeOrderAmount() => switch (next.takenAmount) {
            final kept? => FiatAmount.tryCreate(kept),
            null => null,
          },
        };
        if (amount == null) return StatusUnknown._(now, readWarnings, next);
        return Chatting._(
          now,
          readWarnings,
          next,
          role: role,
          fiatSent: to == TradePosition.fiatSent,
          askedToCancel: order.askedToCancel ?? false,
          peerAskedToCancel: order.peerAskedToCancel ?? false,
          chatLastIndex: order.chatLastIndex,
          deadline: deadline,
          amount: amount,
          currency: terms.currency,
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
      // 17 and 18 by side: for a maker, 17 « Maker lost dispute » is its loss and 18 its win (`api/models/order.py:52-53`).
      case TradePosition.makerLostDispute:
        return DisputeLost._(
          now,
          readWarnings,
          nextTrail(),
          position: TradePosition.makerLostDispute,
        );
      case TradePosition.takerLostDispute:
        return DisputeWon._(
          now,
          readWarnings,
          nextTrail(),
          position: TradePosition.takerLostDispute,
        );
      case TradePosition.expired:
        return Expired._(
          now,
          readWarnings,
          nextTrail(),
          reason: order.expiryReason,
        );
      case TradePosition.start ||
          TradePosition.cancelled ||
          TradePosition.notAvailable ||
          TradePosition.preTakeUnavailable ||
          TradePosition.bondStep ||
          TradePosition.publicAgain:
        // Never the position of a maker's read ([_madePositionOf]).
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

/// 0, for a maker: the order waits for this robot's maker bond, [bond], before [deadline] (« Lock {{amountSats}} Sats to PUBLISH order »), the order's own, 300 s after the make by default (`api/views.py:190`); paying it publishes the order (`follow_invoices.py:233-240`).
final class WaitingForMakerBond extends TradeStatus {
  /// The maker bond invoice, checked: shown and paid only as its warnings allow.
  final StepInvoice bond;

  /// When the order expires unpaid (`expires_at`), and how long the step lasts in all (`total_secs_exp`).
  final DateTime deadline;
  final Duration stepDuration;

  const WaitingForMakerBond._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.bond,
    required this.deadline,
    required this.stepDuration,
  }) : super._();

  @override
  TradePosition get position => TradePosition.makerBondStep;

  @override
  StepInvoice get invoice => bond;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      WaitingForMakerBond._(
        seenAt,
        [...warnings, ...more],
        trail,
        bond: _invoiceWith(bond, more),
        deadline: deadline,
        stepDuration: stepDuration,
      );
}

/// 1 and 2, for a maker: the order is public (« Your order is public »), or paused (« Your order is paused »), with this robot's maker bond locked; not an end, even when the order came back to the book after a contract.
final class MakerOrderPublic extends TradeStatus {
  /// 2: the maker paused it, and nobody can take it until it resumes.
  final bool paused;

  /// When the order expires untaken, its bond returned (`expires_at`): the make's time and the public duration, the same after a return to the book (`api/logics.py:1207-1209`).
  final DateTime deadline;

  /// Whether the order went back to the book after a contract (the taker cancelled at 6 or 7, or let its step run out, `api/logics.py:404-421`, `:445-458`, `:1108-1130`): the maker bond still locked, and the next take a new contract.
  final bool backInBook;

  const MakerOrderPublic._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.paused,
    required this.deadline,
    required this.backInBook,
  }) : super._();

  @override
  TradePosition get position =>
      paused ? TradePosition.paused : TradePosition.public;

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      MakerOrderPublic._(
        seenAt,
        [...warnings, ...more],
        trail,
        paused: paused,
        deadline: deadline,
        backInBook: backInBook,
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

  /// The trade's currency and the escrow's time as its terms fixed them at the take, what the user accepted: the seller's escrow panel is worded from these, never from a read (#96, as `Chatting.currency`).
  final RobosatsCurrency currency;
  final Duration escrowDuration;

  const WaitingForBoth._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.escrow,
    required this.payoutAmount,
    required this.tradeSatoshis,
    required this.deadline,
    required this.currency,
    required this.escrowDuration,
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
        currency: currency,
        escrowDuration: escrowDuration,
      );
}

/// 7: the buyer's payout is in; the seller's escrow is awaited (a buyer waits, « Your info looks good! »; a seller must lock [escrow]).
final class WaitingForEscrow extends TradeStatus {
  final TradeRole role;
  final StepInvoice? escrow;
  final Sats? tradeSatoshis;
  final DateTime deadline;

  /// As [WaitingForBoth.currency] and [WaitingForBoth.escrowDuration].
  final RobosatsCurrency currency;
  final Duration escrowDuration;

  const WaitingForEscrow._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.role,
    required this.escrow,
    required this.tradeSatoshis,
    required this.deadline,
    required this.currency,
    required this.escrowDuration,
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
        currency: currency,
        escrowDuration: escrowDuration,
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

  /// The fiat amount and currency of the trade as its terms fixed them at the take (`TradeTerms.amount`, `TradeTerms.currency`), what the user accepted: « Confirm {{amount}} {{currencyCode}} sent » is worded from these, never from a read, which a coordinator could change (review of #95's second pull request).
  final FiatAmount amount;
  final RobosatsCurrency currency;

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
    required this.amount,
    required this.currency,
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
        amount: amount,
        currency: currency,
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

/// This robot won the dispute (« You have won the dispute »): 17 for a taker, the maker having lost it; 18 for a maker, the taker having lost it ([position] keeps the coordinator's name). Terminal.
final class DisputeWon extends TradeStatus {
  @override
  final TradePosition position;

  const DisputeWon._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.position,
  }) : super._();

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      DisputeWon._(seenAt, [...warnings, ...more], trail, position: position);
}

/// This robot lost the dispute (« You have lost the dispute »): 18 for a taker, 17 for a maker ([position] keeps the coordinator's name). Terminal.
final class DisputeLost extends TradeStatus {
  @override
  final TradePosition position;

  const DisputeLost._(
    super.seenAt,
    super.warnings,
    super.trail, {
    required this.position,
  }) : super._();

  @override
  TradeStatus _rewarned(List<TradeWarning> more, TradeTrail trail) =>
      DisputeLost._(seenAt, [...warnings, ...more], trail, position: position);
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
