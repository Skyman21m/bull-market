import 'package:bull_logger/bull_logger.dart';
import 'package:robosats/robosats.dart';

/// The support log's lines on the outcome of a make or a take (`log.fine`, written to disk), so that one attempt on a phone tells why it ended as it did.
///
/// Fixed words only, with Dart type names, the names of the app's enum values, an HTTP status by hundred and a coordinator's error code (0 to 99999): never a coordinator, a robot, an order number, an amount or a text a coordinator sent.
abstract final class ActionOutcomeLog {
  /// `P2P <action>: <issue> (<cause>)`, the answer to the request of a make or a take.
  static void answered(String action, String issue, Object? cause) =>
      log.fine('P2P $action: $issue (${causeOf(cause)})');

  /// `P2P <action> resolved: <issue> (<reason>)`, what the read after an outcome unknown concluded.
  static void resolved(String action, String issue, String reason) =>
      log.fine('P2P $action resolved: $issue ($reason)');

  static final RegExp _fieldName = RegExp(r'^[a-z_]{1,40}$');

  /// A fixed label for [cause]: its type, with the status by hundred of an unexpected status, the name of the field a malformed answer was refused on (one of the package's own field names), the code of a refusal.
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
