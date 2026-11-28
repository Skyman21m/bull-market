import 'package:bull_logger/bull_logger.dart';
import 'package:robosats/robosats.dart';

import '../../trade/trade_edges.dart' show TradePosition;
import '../../trade/trade_make.dart' show MakePendingReason;

/// The action a line of [ActionOutcomeLog] is about, written by its name.
enum OutcomeAction { make, take }

/// What the answer to the request of a make or a take gave, as [ActionOutcomeLog.answered] writes it.
enum OutcomeAnswer {
  /// The request never left: the transport was busy every time, or the robot was released.
  notSent('notSent'),

  /// The coordinator refused it before it changed anything.
  refused('refused'),

  /// Its outcome is not known.
  pending('pending'),

  /// The coordinator answered a make with an order.
  answered('answered'),

  /// The coordinator answered a take with [OrderTakeStarted].
  takeStarted('answered OrderTakeStarted'),

  /// The coordinator answered a take with [OrderAlreadyTakenByThisRobot].
  alreadyTaken('answered OrderAlreadyTakenByThisRobot'),

  /// The coordinator answered a take with [OrderNotTaken].
  notTaken('answered OrderNotTaken');

  /// The words of the line, fixed here.
  final String words;

  const OutcomeAnswer(this.words);

  /// The answer of a take that the coordinator answered with [outcome].
  static OutcomeAnswer ofTake(TakeOrderOutcome outcome) => switch (outcome) {
    OrderTakeStarted() => takeStarted,
    OrderAlreadyTakenByThisRobot() => alreadyTaken,
    OrderNotTaken() => notTaken,
  };
}

/// What the read after an outcome unknown concluded, as [ActionOutcomeLog.resolved] writes it by its name (`pending` followed by the reason of a make left pending).
enum OutcomeResolution {
  started,
  notMade,
  neverSent,
  pending,
  noLongerPending,
  taker,
}

/// Why the resolution of a make concluded as it did, written by its name (followed by its cause for [robot] and [robotUnread]).
enum OutcomeReason {
  notActive,
  noLongerListed,
  recordsUnread,
  termsUnread,
  noTerms,
  coordinatorNotListed,
  robot,
  answerOrder,
  robotUnread,
  noOrderNamed,
  orderNamed,
  notTheMaker,
  cancelled,
  orderUnread,
}

/// The support log's lines on the outcome of a make or a take (`log.fine`, written to disk), so that one attempt on a phone tells why it ended as it did.
///
/// Fixed words only, with Dart type names, the names of the app's enum values, an HTTP status by hundred and a coordinator's error code (0 to 99999): never a coordinator, a robot, an order number, an amount or a text a coordinator sent.
/// No method takes a `String` (review of #303, S2): the words of a line are the names of this file's enums and of the app's, so that no caller can write a text of its own, an order number for instance (`action_outcome_log_test.dart` pins it).
/// The error code is the one part of a line that a coordinator chooses (any number up to 99999, so a few bits of its choice); every other part is the app's own. The log is timed to the microsecond, so a coordinator that received the requests could tie a shared log to its robot and its order: it is a support file, never published.
abstract final class ActionOutcomeLog {
  /// `P2P <action>: <answer> (<cause>)`, the answer to the request of a make or a take.
  static void answered(
    OutcomeAction action,
    OutcomeAnswer answer,
    Object? cause,
  ) => _write(() => 'P2P ${action.name}: ${answer.words} (${causeOf(cause)})');

  /// `P2P <action>: notSent (<type of the refusal>)`, a make or a take that the use case refused before its request left.
  static void notSent(OutcomeAction action, Object refusal) =>
      _write(() => 'P2P ${action.name}: notSent (${refusal.runtimeType})');

  /// `P2P <action> resolved: <issue> (<reason>)`, what the read after an outcome unknown of a make concluded: [pending] follows the issue `pending`, and [cause] ([causeOf]) follows the reason when there is one.
  static void resolved(
    OutcomeAction action,
    OutcomeResolution issue,
    OutcomeReason reason, {
    MakePendingReason? pending,
    Object? cause,
  }) => _write(
    () =>
        'P2P ${action.name} resolved: ${issue.name}'
        '${pending == null ? '' : ' ${pending.name}'} '
        '(${reason.name}${cause == null ? '' : ' ${causeOf(cause)}'})',
  );

  /// `P2P <action> resolved: <issue> (<position>)`, what a read of a pending take concluded, at [position].
  static void resolvedAt(
    OutcomeAction action,
    OutcomeResolution issue,
    TradePosition position,
  ) => _write(
    () => 'P2P ${action.name} resolved: ${issue.name} (${position.name})',
  );

  /// [resolvedAt], only the first time for [action], [issue] and [once] (a trade's robot, say) in the life of the process: for a line that every read would write again while nothing changes.
  ///
  /// [once] is held in memory only, and never written.
  static void resolvedOnceAt(
    OutcomeAction action,
    OutcomeResolution issue,
    TradePosition position, {
    required Object once,
  }) {
    if (!_saidOnce.add((action, issue, once))) return;
    resolvedAt(action, issue, position);
  }

  static final Set<(OutcomeAction, OutcomeResolution, Object)> _saidOnce = {};

  /// Writes [line] to the support log, and nothing else: whatever the log or the line throws is dropped.
  ///
  /// An `Error` is caught here on purpose: an exception to rule 11 of `AGENTS.md` bounded to the support log's lines, in this helper and in `TorCoordinatorTransport`'s only, since a line of diagnostics must never cost a make, a take or a request, nor change how one ends.
  static void _write(String Function() line) {
    try {
      log.fine(line());
    } on Object catch (_) {
      // Dropped: see above.
    }
  }

  static final RegExp _fieldName = RegExp(r'^[a-z_]{1,40}$');

  /// A fixed label for [cause]: its type, with the status by hundred of an unexpected status, the name of the field a malformed answer was refused on (one of the package's own field names), the code of a refusal (the one figure a coordinator chooses, see the class).
  static String causeOf(Object? cause) => switch (cause) {
    null => 'none',
    OrderActionOutcomeUnknown(:final cause) => 'unknown, ${causeOf(cause)}',
    OrderActionRefused(:final cause) => 'refused, ${causeOf(cause)}',
    CoordinatorUnexpectedStatus(:final statusCode) =>
      'status ${statusCode ~/ 100}xx',
    CoordinatorResponseMalformed(:final field)
        when _fieldName.hasMatch(field) =>
      'malformed $field',
    OrderRequestRefused(errorCode: final code?)
        when code >= 0 && code <= 99999 =>
      'OrderRequestRefused $code',
    // The refusal of the action's signature (GHSA-22q8-9ghc-jg3h) with its code, a fixed number of the app's table (1048, 1059, 1060, 1061), or `notSigned` when this app could not sign.
    ActionSignatureRefused(:final reason) =>
      'ActionSignatureRefused ${reason.code ?? reason.name}',
    _ => '${cause.runtimeType}',
  };
}
