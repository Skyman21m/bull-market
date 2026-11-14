import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show CoordinatorOrderStatus;

import '../p2p_failure.dart';
import '../robot_binding.dart';
import '../trade_record.dart';
import 'trade_storable.dart';
import 'trade_watch.dart';

/// The user's confirmation that a cancel now loses the taker bond (status 6 or 7, design note § 1.4), for one trade at the status the user saw: the trade screen builds it only from its confirmation dialog, after the user confirmed it (#88; `robot_bindings_architecture_test.dart` pins the file that may build it).
///
/// `CancelTradeUsecase` refuses such a cancel without it, and refuses one given for another trade or at another status than the one it cancels with ([CancelAcknowledgementMismatch]); a free cancel (the pre-take, 3) needs none.
@immutable
final class BondLossAcknowledged {
  /// The robot of the trade the user confirmed for (its key's fingerprint, index and network) and the order.
  final RobotSlot robot;
  final int orderId;

  /// The status of the order the user saw, and when that status was read.
  final CoordinatorOrderStatus status;
  final DateTime seenAt;

  /// The acknowledgement for [record] at [seen], which must come from an order (`TradeSeen.order`).
  BondLossAcknowledged.fromConfirmationDialog(
    TradeRecord record,
    TradeSeen seen,
  ) : robot = record.robot,
      orderId = record.orderId,
      status = switch (seen.order) {
        final order? => order.status,
        null => throw ArgumentError('a status seen from no order'),
      },
      seenAt = seen.status.seenAt;

  /// Whether this acknowledgement was given for [record] at [seen].
  bool covers(TradeRecord record, TradeSeen seen) =>
      robot == record.robot &&
      orderId == record.orderId &&
      status == seen.order?.status &&
      seenAt == seen.status.seenAt;

  @override
  String toString() => 'BondLossAcknowledged(${status.name})';
}

/// Why a cancel was not sent: a type for each reason, which the screen words (#88).
sealed class CancelRefusal extends Failure {
  const CancelRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The status seen comes from no order the coordinator described (error 1043 or 1044, a trail restored and not read yet): read the order first.
final class CancelNeedsARead extends CancelRefusal {
  const CancelNeedsARead();
}

/// The bond is locked and the escrow is not (6 or 7): a cancel now loses the bond, and needs [BondLossAcknowledged].
final class CancelLosesTheBond extends CancelRefusal {
  const CancelLosesTheBond();
}

/// The acknowledgement given is for another trade, or another status, than the cancel's: nothing is sent; the screen asks again.
final class CancelAcknowledgementMismatch extends CancelRefusal {
  const CancelAcknowledgementMismatch();
}

/// The escrow is locked (8 or 9): only a collaborative cancel exists, a later slice.
final class CancelOnlyTogether extends CancelRefusal {
  const CancelOnlyTogether();
}

/// No cancel exists at the status seen (from « fiat sent » on, a dispute, an end): the coordinator refuses it (1021, `api/logics.py:1019-1032`).
final class CancelNotPossible extends CancelRefusal {
  const CancelNotPossible();
}

/// The order seen is not the trade's.
final class CancelOfAnotherTrade extends CancelRefusal {
  const CancelOfAnotherTrade();
}

/// The trade cannot be opened: [failure] says why (the records cannot be read, the key is missing, the binding refuses the coordinator).
final class CancelTradeUnavailable extends CancelRefusal {
  final P2pFailure failure;

  const CancelTradeUnavailable(this.failure);

  @override
  String toString() => 'CancelTradeUnavailable(${failure.runtimeType})';
}

/// The trade's stored records cannot be restored: it is shown read-only, and nothing is sent.
final class CancelTradeUnrestorable extends CancelRefusal {
  final TradeRecordRefusal reason;

  const CancelTradeUnrestorable(this.reason);

  @override
  String toString() => 'CancelTradeUnrestorable(${reason.runtimeType})';
}

/// What a cancel sent gave, with the trade as the read after it shows it.
@immutable
sealed class CancelOutcome {
  /// The trade's record as stored once the cancel's writes are over.
  TradeRecord get record;

  /// The status after the cancel and the read that followed it.
  TradeSeen get seen;

  /// A write that failed after the coordinator answered (the trail, the close).
  P2pFailure? get recordProblem;

  const CancelOutcome();
}

/// The coordinator cancelled: the order ended (4 or 12), or it accepted the cancel and the order goes on without this robot (public again; at 6 or 7 the bond is lost).
final class CancelDone extends CancelOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const CancelDone(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'CancelDone($record, ${seen.status})';
}

/// Nothing was done: the coordinator refused before acting (the status moved since the read seen, 1020, …) or the request was never sent (a busy transport); [cause] says which.
final class CancelNotDone extends CancelOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;
  final Failure cause;

  const CancelNotDone(
    this.record,
    this.seen, {
    required this.cause,
    this.recordProblem,
  });

  @override
  String toString() => 'CancelNotDone($record, ${cause.runtimeType})';
}

/// The cancel may have happened: the read after it shows [seen] when it told something; otherwise the watch of the trade resolves it.
final class CancelOutcomeUnknown extends CancelOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const CancelOutcomeUnknown(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'CancelOutcomeUnknown($record, ${seen.status})';
}
