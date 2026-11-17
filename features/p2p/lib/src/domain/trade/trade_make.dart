import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'maker_terms.dart';
import 'trade_status.dart';

/// Why a make was not sent: nothing left with a robot, and no order was asked for (design note `docs/design/phase-3-making-an-order.md` § 3.4).
///
/// A type for each reason, which a screen words (#181, #182); none carries a coordinator's text.
sealed class MakeRefusal extends Failure {
  const MakeRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The coordinator has no address on the network of the make: nothing was sent.
final class MakeCoordinatorNotOnNetwork extends MakeRefusal {
  const MakeCoordinatorNotOnNetwork();
}

/// The coordinator's `/api/info/` or `/api/limits/` could not be read just before the make: nothing was sent with a robot.
final class MakeCoordinatorUnreadable extends MakeRefusal {
  final CoordinatorFailure cause;

  const MakeCoordinatorUnreadable(this.cause);

  @override
  String toString() => 'MakeCoordinatorUnreadable(${cause.runtimeType})';
}

/// The coordinator's `/api/limits/` gives no price for the order's currency: the terms cannot be checked, and nothing was sent with a robot.
final class MakePriceUnknown extends MakeRefusal {
  const MakePriceUnknown();
}

/// The terms of the make are refused ([MakerTerms.create]): a maker fee above its ceiling, a price or a fee that is no usable figure.
final class MakeTermsRefused extends MakeRefusal {
  final MakerTermsRefusal reason;

  const MakeTermsRefused(this.reason);

  @override
  String toString() => 'MakeTermsRefused(${reason.runtimeType})';
}

/// The amount, or a bound of the range, is outside the limits the reference's form allows at the coordinator's price ([MakerAmountLimits]): the coordinator would refuse it (1004 to 1008) once a robot is spent.
final class MakeAmountOutsideLimits extends MakeRefusal {
  final MakerAmountLimits limits;

  const MakeAmountOutsideLimits(this.limits);

  @override
  String toString() => 'MakeAmountOutsideLimits';
}

/// No fresh robot could be had for the make: [failure] says why (no Garage Key, a key from elsewhere, the robot already known to the coordinator, the records unreadable…).
final class MakeRobotRefused extends MakeRefusal {
  final P2pFailure failure;

  const MakeRobotRefused(this.failure);

  @override
  String toString() => 'MakeRobotRefused(${failure.runtimeType})';
}

/// The fresh robot could not be put on the coordinator: [cause] says why.
final class MakeRobotNotPut extends MakeRefusal {
  final CoordinatorFailure cause;

  const MakeRobotNotPut(this.cause);

  @override
  String toString() => 'MakeRobotNotPut(${cause.runtimeType})';
}

/// The pending make or its terms could not be written: [failure] says why, and nothing was sent (a pending make whose terms were not written is closed at once).
final class MakeNotRecorded extends MakeRefusal {
  final P2pFailure failure;

  const MakeNotRecorded(this.failure);

  @override
  String toString() => 'MakeNotRecorded(${failure.runtimeType})';
}

/// The limits of an amount the reference's form allows at a coordinator's price (`MakerForm.tsx:96`, `:140-158`, `AmountRange.tsx:57-77`, commit ff1998c), in the order's currency.
///
/// [min] is the coordinator's smallest order (`/api/limits/`'s `min_amount`, `MIN_ORDER_SIZE` at its price, `api/views.py:1177-1197`) with the premium, times 1.03; [max] is its largest order with the premium, capped by the coordinator's size limit at its price (`CoordinatorSizeLimit`, `calculateSizeLimit` of `models/Coordinator.model.ts:110-127`, without the premium as the reference writes it), times 0.98. A fixed amount must lie within them; a range's minimum must be at least 0.99 × [min] and its maximum at most 1.01 × [max], as the range's fields check them (the ratios of a range, 1.6 and 14.8 in the form, are the form's of #183; the package keeps the coordinator's 1.5 and 15).
@immutable
final class MakerAmountLimits {
  final double min;
  final double max;

  const MakerAmountLimits._(this.min, this.max);

  /// The thresholds the reference applies to the coordinator's bounds, « to ensure good request » (`amountSafeThresholds`, `MakerForm.tsx:96`).
  static const double minThreshold = 1.03;
  static const double maxThreshold = 0.98;

  /// The margins of a range's own fields over those limits (`AmountRange.tsx:61`, `:72`).
  static const double rangeMinMargin = 0.99;
  static const double rangeMaxMargin = 1.01;

  /// The limits of [limit] for a make at [premium], on a coordinator whose size limit is [sizeLimitSats] sats.
  factory MakerAmountLimits.of(
    CurrencyLimit limit, {
    required Premium premium,
    required double sizeLimitSats,
  }) {
    final factor = 1 + premium.percent / 100;
    final sizeLimit = sizeLimitSats / 100000000 * limit.price;
    final upper = limit.maxAmount * factor;
    return MakerAmountLimits._(
      limit.minAmount * factor * minThreshold,
      (sizeLimit < upper ? sizeLimit : upper) * maxThreshold,
    );
  }

  /// Whether [amount] is within these limits, as the reference's form checks it (a fixed amount within [min] and [max], a range's bounds within their margins of them).
  bool allows(OrderAmount amount) => switch (amount) {
    FixedOrderAmount(:final amount) =>
      amount.value >= min && amount.value <= max,
    RangeOrderAmount(min: final low, max: final high) =>
      low.value >= min * rangeMinMargin && high.value <= max * rangeMaxMargin,
  };

  @override
  bool operator ==(Object other) =>
      other is MakerAmountLimits && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'MakerAmountLimits($min, $max)';
}

/// What a make that was sent, or the resolution of a pending make, gave (design note `docs/design/phase-3-making-an-order.md` § 3.4).
@immutable
sealed class MakeOutcome {
  const MakeOutcome();
}

/// The order is this robot's: a read of it showed this robot as its maker, the make was confirmed with its order id ([record]), and [status] is its first status, `TradeStatus.afterMake` of that read.
///
/// Only a status marked [stored] may show an invoice or offer a payment: when the first trail could not be stored, [status] is the one of no trail on disk, with no invoice, and [recordProblem] says why; the next read of the trade starts it again from its first read (`TradeTrail.forConfirmedMake`).
final class MakeStarted extends MakeOutcome {
  final TradeRecord record;
  final TradeStatus status;
  final bool stored;

  /// A write that failed once the order was confirmed (its first trail).
  final P2pFailure? recordProblem;

  const MakeStarted(
    this.record,
    this.status, {
    required this.stored,
    this.recordProblem,
  });

  @override
  String toString() => 'MakeStarted($record, $status, stored: $stored)';
}

/// The make certainly made no order that this app could ever show a bond for, and [make] is closed: the coordinator refused it before making anything ([refusal]: an `OrderActionRefused`'s cause, a busy transport), or the robot names no order, read after the make's request ended, or its order is cancelled (error 1043, which proves nothing but leaves nothing to pay).
///
/// [closeProblem] when the close could not be written: [make] then stays pending, for a later resolution to close.
/// A request still in flight that lands after the robot's read makes an order this app never shows: it waits at 0 for a bond invoice nobody sees, and the coordinator expires it 300 seconds after its creation with nothing paid (`api/logics.py:329-338`).
final class MakeNotMade extends MakeOutcome {
  final PendingMake make;
  final Failure? refusal;
  final P2pFailure? closeProblem;

  const MakeNotMade(this.make, {this.refusal, this.closeProblem});

  @override
  String toString() =>
      'MakeNotMade($make, ${refusal?.runtimeType}, problem: ${closeProblem?.runtimeType})';
}

/// The make's pending record [make] was written and never sent: its terms were never written (`MakeOrderUsecase.resolve` of a make killed between its two writes); it is closed at once ([closed] false when the close could not be written).
final class MakeNeverSent extends MakeOutcome {
  final PendingMake make;
  final bool closed;

  const MakeNeverSent(this.make, {required this.closed});

  @override
  String toString() => 'MakeNeverSent($make, closed: $closed)';
}

/// Whether [make] made an order is not known yet: it stays pending, and its resolution (`MakeOrderUsecase.resolve`) reads the robot again; no bond is shown for it.
final class MakePending extends MakeOutcome {
  final PendingMake make;
  final MakePendingReason reason;

  const MakePending(this.make, this.reason);

  @override
  String toString() => 'MakePending($make, ${reason.name})';
}

/// Why a make stays pending.
enum MakePendingReason {
  /// The make's answer was lost or did not prove anything (an outcome unknown): an order may exist.
  outcomeUnknown,

  /// The robot, or the order it names, could not be read (no answer, a busy coordinator, an answer that says nothing).
  unread,

  /// The coordinator named an order that a read does not show as this robot's own made after the make (another robot's order, this robot not its maker, another coordinator, network or number than asked, or an order created before the make was written): a coordinator that lies; no bond is shown, and the robot is read again at the next resolution.
  notRecognized,

  /// A read showed this robot as the maker, and the confirmation of the make could not be written.
  notConfirmed,
}

/// A pending make of the « Active trades » list (#179): [make], and whether its terms were never written, so that its request never left ([neverSent], closed at its resolution).
@immutable
final class ActivePendingMake {
  final PendingMake make;
  final bool neverSent;

  const ActivePendingMake(this.make, {required this.neverSent});

  @override
  bool operator ==(Object other) =>
      other is ActivePendingMake &&
      other.make == make &&
      other.neverSent == neverSent;

  @override
  int get hashCode => Object.hash(make, neverSent);

  @override
  String toString() => 'ActivePendingMake($make, neverSent: $neverSent)';
}
