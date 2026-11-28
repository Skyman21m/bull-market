import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_status.dart';
import 'trade_terms.dart';
import 'trade_warning.dart';

export 'trade_terms.dart' show TakenTradeTerms;

/// The amount chosen in the range of an order, in the order's currency (bitcoin, not sats, for an order in bitcoin), as the take sends it.
///
/// The reference client sends the number typed (`Number(takeAmount)`, `frontend/src/models/Order.model.ts:241`, divided by 10⁸ for an order in sats) and the coordinator keeps 8 decimals, refusing more (`DecimalField(decimal_places=8)`, `api/serializers.py:684`): the amount is rounded to 8 decimals here, and the take checks it against the range of the order read just before it (`min_amount ≤ amount ≤ max_amount`, `api/logics.py:190-194`).
@immutable
final class TakeAmount {
  /// The decimals the coordinator keeps.
  static const int decimals = 8;

  /// The largest amount taken, far above any order's (`max_order_size` is in sats; a fiat amount of 10¹² is no order).
  static const double maxValue = 1e12;

  final FiatAmount amount;

  const TakeAmount._(this.amount);

  /// [value] rounded to [decimals] decimals, or `null` when it is not finite, not above zero, or above [maxValue].
  static TakeAmount? tryCreate(double value) {
    if (!value.isFinite || value <= 0 || value > maxValue) return null;
    final rounded = (value * 1e8).roundToDouble() / 1e8;
    return switch (FiatAmount.tryCreate(rounded)) {
      final amount? => TakeAmount._(amount),
      null => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is TakeAmount && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'TakeAmount(${amount.value})';
}

/// The password the user typed for a protected order, held only as its SHA-256 ([OrderPasswordHash.of]): the take sends that hash (`OrderDetails/TakeButton.tsx:333`, the very hash a make sends, #189), never the text, which this value does not keep (#245).
///
/// Any text but the empty one, neither trimmed nor bounded, as the reference's field takes it (`components/OrderDetails/index.tsx:546-571`); never stored, never printed.
@immutable
final class OrderPassword {
  final OrderPasswordHash hash;

  const OrderPassword._(this.hash);

  /// The hash of [text] as typed, or `null` when it is empty, which the reference sends as no password.
  static OrderPassword? tryCreate(String text) =>
      switch (OrderPasswordHash.of(text)) {
        final hash? => OrderPassword._(hash),
        null => null,
      };

  @override
  bool operator ==(Object other) =>
      other is OrderPassword && other.hash == hash;

  @override
  int get hashCode => hash.hashCode;

  @override
  String toString() => 'OrderPassword(<redacted>)';
}

/// Why a take was not sent: nothing left with a robot, and no trade was started.
///
/// A type for each reason, which the screen words (#88); none carries a coordinator's text.
sealed class TakeRefusal extends Failure {
  const TakeRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The coordinator could not be read just before the take (its book or its `/api/info/`): nothing was sent with a robot.
final class TakeCoordinatorUnreadable extends TakeRefusal {
  final CoordinatorFailure cause;

  const TakeCoordinatorUnreadable(this.cause);

  @override
  String toString() => 'TakeCoordinatorUnreadable(${cause.runtimeType})';
}

/// The order already has an open trade on this device, [record]: a pending take, or a trade taken here or taken over (one open trade per order, review of #117); open it rather than take again.
final class TakeOrderAlreadyTraded extends TakeRefusal {
  final TradeRecord record;

  const TakeOrderAlreadyTraded(this.record);

  @override
  String toString() => 'TakeOrderAlreadyTraded($record)';
}

/// The prepared take given to `TakeOrderUsecase.confirm` is not, or no longer, one this app prepared: confirmed already, abandoned, replaced by a newer preparation of the same order, or prepared before the app restarted; nothing was sent: prepare again (#119).
final class TakePreparationGone extends TakeRefusal {
  const TakePreparationGone();
}

/// The order has a password and none was given: nothing was read or sent, and the take stays prepared (#245); the screen asks for the password.
final class TakePasswordMissing extends TakeRefusal {
  const TakePasswordMissing();
}

/// An order that no book received, reached by its URL and read by the robot that will take it (#245): the order the page shows, in place of the public book.
///
/// A password-protected order, which no book ever lists (`api/views.py:788-790`), or a public order without a password that the book in memory does not hold yet (the book is read again only on the user's gesture, and a coordinator caches its book for 10 s, `api/views.py:85`, `:824`), as the reference's order page shows either (`basic/OrderPage/index.tsx:75-96`).
/// Only a public order that the robot takes no part in, read whole as the book would list it ([PublicOrder.ofRead]); a protected one's description and location are hidden from such a robot (`api/views.py:294-298`), and come with the take, once the robot is a participant (`:248-252`, `:280`, `:320-321`).
/// It holds no robot: the robot that read it stays with the use case (`PreparedTakes`), kept for the take of that order.
@immutable
final class UnlistedOrder {
  /// The order as the book would list it, what the order details show and the take is compared with.
  final PublicOrder order;

  /// Whether a password protects the order (`has_password`): its take then asks for the password and sends its hash; otherwise it sends none.
  final bool hasPassword;

  /// The network it was read on.
  final RobosatsNetwork network;

  /// When the robot read it.
  final DateTime readAt;

  const UnlistedOrder._(
    this.order,
    this.hasPassword,
    this.network,
    this.readAt,
  );

  /// [read] as an order no book received, or `null` when it is not a public order that the robot reading it takes no part in.
  static UnlistedOrder? ofRead(CoordinatorOrder read, {required DateTime at}) =>
      switch (PublicOrder.ofRead(read)) {
        final order? => UnlistedOrder._(
          order,
          read.hasPassword,
          read.network,
          at,
        ),
        null => null,
      };

  @override
  String toString() =>
      'UnlistedOrder(${order.coordinator.shortAlias}, ${order.id})';
}

/// What a take in two steps is doing while it runs (#119), for the screen to say: a step, never anything of the robot or of its token.
///
/// Only the parts that take real time are steps: requests over Tor, and the making of a robot's key pair; the checks and the writes on the device are not.
enum TakeStep {
  /// The order read again from the coordinator's book, with its taker fee: two anonymous requests, at once.
  checkingOrder,

  /// A fresh robot for the take: reserved on the device, then put on the coordinator over a Tor session of its own (read back, its key pair made away from the UI isolate, its first contact).
  creatingRobot,

  /// The order read by the robot that will take it.
  readingOrder,

  /// At the confirmation, the order read again by the same robot.
  readingOrderAgain,

  /// The take sent, once its records are written, and its answer awaited.
  sendingTake,
}

/// Told each [TakeStep] as it starts.
typedef TakeProgress = void Function(TakeStep step);

/// The order is no longer in the coordinator's book read just before the take: taken, paused, cancelled or expired.
final class TakeOrderGone extends TakeRefusal {
  const TakeOrderGone();
}

/// The order read just before the take is not the one the user accepted on the order's page: another type, currency, amount or range, premium, bond size, escrow duration, sats of an order priced in sats, or sats at the current price moved by more than `TradeTolerances.price`; the user opens the order again and sees its new amounts.
final class TakeOrderChanged extends TakeRefusal {
  const TakeOrderChanged();
}

/// An amount was given for a fixed order, none for a range, or one outside the range of the order read just before the take.
final class TakeAmountRefused extends TakeRefusal {
  const TakeAmountRefused();
}

/// The terms of the take cannot be checked, so the take is not made: [reason] is [TakerFeeTooHigh] or [TradeTermsUnusable].
final class TakeTermsRefused extends TakeRefusal {
  final TradeTermsRefusal reason;

  const TakeTermsRefused(this.reason);

  @override
  String toString() => 'TakeTermsRefused(${reason.runtimeType})';
}

/// No robot could be reserved for the trade, or one reserved could not be put on the coordinator or recorded with its take: [failure] says why.
///
/// A robot reserved stays bound to that coordinator, without a trade, and is never used again; its first contact may have reached the coordinator, never a take.
final class TakeRobotRefused extends TakeRefusal {
  final P2pFailure failure;

  const TakeRobotRefused(this.failure);

  @override
  String toString() => 'TakeRobotRefused(${failure.runtimeType})';
}

/// The coordinator refused the robot's first contact, or could not be reached for it: [cause] says why; no take was sent.
final class TakeRobotNotPut extends TakeRefusal {
  final CoordinatorFailure cause;

  const TakeRobotNotPut(this.cause);

  @override
  String toString() => 'TakeRobotNotPut(${cause.runtimeType})';
}

/// The trade records could not be read before the take, or the pending take, its terms or its first trail could not be written: the take was not sent (`TradeRecordRepository.recordPendingTake`, #87).
final class TakeNotRecorded extends TakeRefusal {
  final P2pFailure failure;

  const TakeNotRecorded(this.failure);

  @override
  String toString() => 'TakeNotRecorded(${failure.runtimeType})';
}

/// What a take sent to the coordinator gave.
@immutable
sealed class TakeOutcome {
  /// The trade's record as stored once the take's writes are over (pending, taken or closed).
  TradeRecord get record;

  const TakeOutcome();
}

/// The take started a trade: [status] is the pre-take with its bond (`TradeStatus.afterTake`), once its trail is stored.
///
/// [recordProblem] is set when the trail or the confirmation could not be written: the trade runs on the coordinator all the same, and the next read of the trade writes them. When the trail could not be stored, [status] is the stored pending trail's (`StatusUnknown`, no invoice) and [stored] is false: an invoice is shown or offered to the wallet only from a status marked [stored] (review of #117); a failed confirmation leaves [stored] true.
final class TakeStarted extends TakeOutcome {
  @override
  final TradeRecord record;
  final TradeStatus status;
  final P2pFailure? recordProblem;

  /// Whether [status] is the one stored with its trail by this take (`TradeSeen.stored`): show an invoice, or offer a payment, only when it is.
  final bool stored;

  const TakeStarted(
    this.record,
    this.status, {
    this.recordProblem,
    this.stored = false,
  });

  @override
  String toString() => 'TakeStarted($record, $status)';
}

/// The order was already this robot's: the trade goes on at [status], resumed from its recorded trail.
final class TakeResumed extends TakeOutcome {
  @override
  final TradeRecord record;
  final TradeStatus status;
  final P2pFailure? recordProblem;

  /// Whether [status] is the one stored with its trail by this take (`TradeSeen.stored`): show an invoice, or offer a payment, only when it is.
  final bool stored;

  const TakeResumed(
    this.record,
    this.status, {
    this.recordProblem,
    this.stored = false,
  });

  @override
  String toString() => 'TakeResumed($record, $status)';
}

/// The take certainly did not happen: the coordinator answered with the order as it is, this robot not its taker ([OrderNotTaken]), or refused the take before acting ([refusal]: a penalty, a wrong password, an amount out of range, another active order, a busy transport…).
///
/// The pending take is closed ([TakeOutcome.record] closed), or stays pending when the close could not be written ([closeProblem]), for the next read to close.
final class TakeNotMade extends TakeOutcome {
  @override
  final TradeRecord record;

  /// Why the coordinator refused, or `null` when it answered with the order as it is.
  final Failure? refusal;
  final P2pFailure? closeProblem;

  const TakeNotMade(this.record, {required this.refusal, this.closeProblem});

  @override
  String toString() => 'TakeNotMade($record, ${refusal?.runtimeType})';
}

/// The take was sent and what it did is unknown (a timeout, a broken answer…): the pending take stays, and the next read of the trade tells whether this robot holds the pre-take (`WatchTradeUsecase`).
final class TakeOutcomeUnknown extends TakeOutcome {
  @override
  final TradeRecord record;

  const TakeOutcomeUnknown(this.record);

  @override
  String toString() => 'TakeOutcomeUnknown($record)';
}

/// A take prepared and not sent (#119): the order as the trade's fresh robot read it on its coordinator, after the robot was reserved and put there, for the user to see before confirming.
///
/// The public book carries neither the maker's description nor figures fresher than its last refresh: this read does, by the robot that will take, and its terms are the ones a confirmed take is sent with and checked against.
/// It holds no robot: the robot and its reservation stay with the use case (`PreparedTakes`), out of reach of a screen; a prepared take is confirmed or abandoned through `TakeOrderUsecase`, once.
@immutable
final class PreparedTake {
  /// The order as the robot read it (`GET /api/order/`), a public order this robot takes no part in yet.
  final CoordinatorOrder order;

  /// The terms of the take, built from [order] (`TradeTerms.takeRead`): what the take is sent with and checked against once confirmed.
  final TradeTerms<TakenSide> terms;

  /// The amount chosen in the range of the order, or `null` for a fixed order.
  final TakeAmount? amount;

  /// When [order] was read.
  final DateTime readAt;

  /// The nickname of the robot that read [order] and will take it, when it is not the robot the Garage showed before the take reserved it (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.2): the order page then says « A fresh robot for this order »; `null` otherwise, or when the Garage's robot could not be told. Public, never a token.
  final String? freshRobot;

  /// Whether the robot that read [order] and will take it is of the external Garage Key, the key the vault keeps, as its reservation said (`ReservedRobot.externalKey`): « Store your garage key » is shown before the take only then, a key of the wallet's words coming back with the words (#318, decided on 2026-11-28). Public, never the key.
  final bool externalKey;

  const PreparedTake({
    required this.order,
    required this.terms,
    required this.amount,
    required this.readAt,
    required this.externalKey,
    this.freshRobot,
  });

  /// The maker's description, as the robot's read gave it: at most 240 code points, cleaned by the package (`displayText`), or `null` when there is none. The maker's own words: shown as plain text, never acted on.
  String? get description => order.description;

  /// The bond the terms expect, in sats at the read's price: an estimate; the bond invoice states the amount to lock.
  double get expectedBond => terms.expectedBond;

  /// The largest bond, in sats, that the state machine takes for these terms without a [BondAmountOutsideOrder] warning: [TradeTerms.bondCeiling], the very value the wallet's payment of the bond accepts (#100), never a second computation.
  int get bondCeiling => terms.bondCeiling.value.toInt();

  /// Whether [other] shows the user what this read shows: the same payment methods, maker, description, price and premium, sats, expiry, escrow duration, amount, bond and taker fee (security reviews of #133: a read made again must say when it changed).
  bool showsTheSameAs(PreparedTake other) {
    final a = order;
    final b = other.order;
    return a.paymentMethods == b.paymentMethods &&
        a.maker == b.maker &&
        a.description == b.description &&
        a.priceNow == b.priceNow &&
        a.satoshisNow == b.satoshisNow &&
        a.expiresAt == b.expiresAt &&
        a.escrowDuration == b.escrowDuration &&
        terms.premium == other.terms.premium &&
        terms.explicitSatoshis == other.terms.explicitSatoshis &&
        amount?.amount == other.amount?.amount &&
        bondCeiling == other.bondCeiling &&
        expectedBond.round() == other.expectedBond.round() &&
        terms.takerFee == other.terms.takerFee;
  }

  @override
  String toString() => 'PreparedTake($terms)';
}
