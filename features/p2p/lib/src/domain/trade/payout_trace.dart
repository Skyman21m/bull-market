import 'package:meta/meta.dart';

/// Where the payout of the contract a buyer's trade stands at came from, as this device's records say (schema 9, #204; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis): what « Confirm … sent » is preceded by.
///
/// The coordinator never gives the buyer's invoice back in a read (`api/views.py:345-371`, `:470-488`), so this device's own record of what it submitted is the only way to know: a contract with no record was not given from this device. A contract under way before schema 9 is [PayoutUnrecorded], never [PayoutNotGivenHere]. Its [toString] names no hash and no time.
@immutable
sealed class PayoutTrace {
  const PayoutTrace();
}

/// The payout of the contract was given from this device, an invoice or an address this wallet gave during the run that submitted it, at [at].
final class PayoutFromThisWallet extends PayoutTrace {
  final PayoutTraceKind kind;
  final DateTime at;

  const PayoutFromThisWallet(this.kind, this.at);

  @override
  bool operator ==(Object other) =>
      other is PayoutFromThisWallet && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(PayoutFromThisWallet, kind, at);

  @override
  String toString() => 'PayoutFromThisWallet(${kind.name})';
}

/// The payout of the contract was given from this device, a text pasted (any wallet's, this one's included when copied by hand), at [at]: the sats go to the wallet that made it.
final class PayoutPasted extends PayoutTrace {
  final PayoutTraceKind kind;
  final DateTime at;

  const PayoutPasted(this.kind, this.at);

  @override
  bool operator ==(Object other) =>
      other is PayoutPasted && other.kind == kind && other.at == at;

  @override
  int get hashCode => Object.hash(PayoutPasted, kind, at);

  @override
  String toString() => 'PayoutPasted(${kind.name})';
}

/// No payout of the contract was given from this device since payouts are recorded: it was given from another client with the same Garage Key, or not by this device at all.
final class PayoutNotGivenHere extends PayoutTrace {
  const PayoutNotGivenHere();

  @override
  bool operator ==(Object other) => other is PayoutNotGivenHere;

  @override
  int get hashCode => (PayoutNotGivenHere).hashCode;

  @override
  String toString() => 'PayoutNotGivenHere';
}

/// The contract was under way before payouts were recorded (a trade of a schema 8 file, marked by the step to schema 9): where its payout came from is unknown, never « given elsewhere ».
final class PayoutUnrecorded extends PayoutTrace {
  const PayoutUnrecorded();

  @override
  bool operator ==(Object other) => other is PayoutUnrecorded;

  @override
  int get hashCode => (PayoutUnrecorded).hashCode;

  @override
  String toString() => 'PayoutUnrecorded';
}

/// The records could not be read: where the payout came from is unknown.
final class PayoutTraceUnreadable extends PayoutTrace {
  const PayoutTraceUnreadable();

  @override
  bool operator ==(Object other) => other is PayoutTraceUnreadable;

  @override
  int get hashCode => (PayoutTraceUnreadable).hashCode;

  @override
  String toString() => 'PayoutTraceUnreadable';
}

/// What a payout was: a Lightning invoice or an on-chain address.
enum PayoutTraceKind { invoice, address }

/// Where a payout given from this device came from.
enum PayoutTraceSource {
  /// An invoice or an address this wallet gave during the run that submitted it.
  thisWallet,

  /// Anything else, pasted.
  pasted,
}
