import 'package:bull_logger/bull_logger.dart';
import 'package:robosats/robosats.dart';

/// The support log's lines on the outcome of a make or a take (`log.fine`, written to disk), so that one attempt on a phone tells why it ended as it did.
///
/// Fixed words only, with Dart type names, the names of the app's enum values, an HTTP status by hundred and a coordinator's error code (0 to 99999): never a coordinator, a robot, an order number, an amount or a text a coordinator sent.
/// The error code is the one part of a line that a coordinator chooses (any number up to 99999, so a few bits of its choice); every other part is the app's own. The log is timed to the microsecond, so a coordinator that received the requests could tie a shared log to its robot and its order: it is a support file, never published.
abstract final class ActionOutcomeLog {
  /// `P2P <action>: <issue> (<cause>)`, the answer to the request of a make or a take.
  static void answered(String action, String issue, Object? cause) =>
      _write(() => 'P2P $action: $issue (${causeOf(cause)})');

  /// `P2P <action>: notSent (<type of the refusal>)`, a make or a take that the use case refused before its request left.
  static void notSent(String action, Object refusal) =>
      _write(() => 'P2P $action: notSent (${refusal.runtimeType})');

  /// `P2P <action> resolved: <issue> (<reason>)`, what the read after an outcome unknown concluded.
  static void resolved(String action, String issue, String reason) =>
      _write(() => 'P2P $action resolved: $issue ($reason)');

  /// [resolved], only the first time for [action], [issue] and [once] (a trade's robot, say) in the life of the process: for a line that every read would write again while nothing changes.
  ///
  /// [once] is held in memory only, and never written.
  static void resolvedOnce(
    String action,
    String issue,
    String reason, {
    required Object once,
  }) {
    if (!_saidOnce.add((action, issue, once))) return;
    resolved(action, issue, reason);
  }

  static final Set<(String, String, Object)> _saidOnce = {};

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
    _ => '${cause.runtimeType}',
  };
}
