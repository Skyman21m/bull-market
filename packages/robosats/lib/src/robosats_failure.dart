import 'package:primitives/primitives.dart';
import 'package:robosats/src/robot_token.dart';

/// Every modeled, recoverable failure of the RoboSats identity primitives.
///
/// No failure carries the rejected input: a Garage Key or a token with a typo is still a secret.
sealed class RobosatsFailure extends Failure {
  const RobosatsFailure();
}

/// A string or byte sequence that is not a RoboSats Garage Key.
sealed class GarageKeyFailure extends RobosatsFailure {
  const GarageKeyFailure();
}

/// The Garage Key string is empty.
final class GarageKeyEmpty extends GarageKeyFailure {
  const GarageKeyEmpty();
}

/// The string does not start with `robo1`, or its bech32 human-readable part is not `robo`.
final class GarageKeyWrongPrefix extends GarageKeyFailure {
  const GarageKeyWrongPrefix();
}

/// The string is not between 55 and 65 characters long.
final class GarageKeyWrongLength extends GarageKeyFailure {
  const GarageKeyWrongLength();
}

/// The string is not bech32: mixed case, a character outside the charset, or invalid padding.
final class GarageKeyMalformed extends GarageKeyFailure {
  const GarageKeyMalformed();
}

/// The bech32 checksum does not match: most likely a typo.
final class GarageKeyBadChecksum extends GarageKeyFailure {
  const GarageKeyBadChecksum();
}

/// The key material is not exactly 32 bytes long.
final class GarageKeyWrongByteLength extends GarageKeyFailure {
  const GarageKeyWrongByteLength();
}

/// The robot index is not an integer between 0 and 2 147 483 647.
final class AccountIndexOutOfRange extends RobosatsFailure {
  const AccountIndexOutOfRange();
}

/// The token fails the client-side entropy rule of RoboSats, so the official client would never send it to a coordinator.
final class TokenEntropyTooLow extends RobosatsFailure {
  final TokenEntropy entropy;

  const TokenEntropyTooLow(this.entropy);
}

/// The string is not a robot hash id: 64 lowercase hexadecimal characters.
final class HashIdMalformed extends RobosatsFailure {
  const HashIdMalformed();
}

/// The RoboSats nickname generator has no nickname for this hash id, so no coordinator can have created a robot for it.
final class NicknameUnavailable extends RobosatsFailure {
  const NicknameUnavailable();
}

/// A failure of the OpenPGP operations of a robot: its key, its signed messages and its chat.
///
/// No failure carries the rejected input, a passphrase or a plaintext.
sealed class PgpFailure extends RobosatsFailure {
  const PgpFailure();
}

/// The input is larger than anything a robot exchanges, and was not read: see the bounds of `PgpLimits`.
final class PgpInputTooLarge extends PgpFailure {
  const PgpInputTooLarge();
}

/// The clock, or the time given as `now`, is outside what an OpenPGP date can hold: 1970 to 2106.
///
/// A key is dated one day back, so generating one also fails during the first day of 1970.
final class PgpClockOutOfRange extends PgpFailure {
  const PgpClockOutOfRange();
}

/// The text is not one ASCII-armored block of the expected kind: wrong or missing header lines, a cleartext message without `Hash` header, invalid base64, or a CRC-24 that does not match.
final class PgpArmorMalformed extends PgpFailure {
  const PgpArmorMalformed();
}

/// The block holds OpenPGP data this package does not handle.
///
/// A key must be the kind the official client generates: version 4, an Ed25519 primary key with a self-certified user ID and a Curve25519 encryption subkey bound by it, with SHA-2 and AES as KDF parameters and a point that is not of low order, and, for a private key, a passphrase-protected secret part (S2K usage 254, iterated and salted, AES).
final class PgpKeyUnsupported extends PgpFailure {
  const PgpKeyUnsupported();
}

/// A key cannot be used at the given time: it is dated after it, it has expired, or the signature that certifies or binds it has.
///
/// The official client refuses to encrypt to such a key.
final class PgpKeyOutOfDate extends PgpFailure {
  const PgpKeyOutOfDate();
}

/// The private key does not belong to the public key it was given with.
final class PgpKeyPairMismatch extends PgpFailure {
  const PgpKeyPairMismatch();
}

/// The robot token does not unlock the private key.
final class PgpWrongPassphrase extends PgpFailure {
  const PgpWrongPassphrase();
}

/// The text cannot be clear-signed for a coordinator, whose parser would not hand it back intact: it is empty, starts or ends with whitespace, has a line that starts with a dash or ends with a space, or contains a carriage return.
final class PgpCleartextUnsuitable extends PgpFailure {
  const PgpCleartextUnsuitable();
}

/// The cleartext signature is not a valid signature of the text by the primary key of the given public key, or it is dated in the future, expired, or older than the key.
final class PgpSignatureInvalid extends PgpFailure {
  const PgpSignatureInvalid();
}

/// The chat message contains the robot token: the official client refuses to send it, and so does this package.
final class PgpPlaintextContainsToken extends PgpFailure {
  const PgpPlaintextContainsToken();
}

/// The message cannot be opened with this key: it is not encrypted to it, it was tampered with, or it is not an integrity-protected OpenPGP message.
final class PgpMessageUndecryptable extends PgpFailure {
  const PgpMessageUndecryptable();
}

/// A failure to read what a coordinator publishes: it could not be reached, or what it sent cannot be trusted.
///
/// Coordinators are untrusted: no failure carries text they sent, only fixed labels and numbers.
/// A failure concerns one coordinator and one request, never the rest of the federation.
sealed class CoordinatorFailure extends RobosatsFailure {
  const CoordinatorFailure();
}

/// The coordinator has no onion address on the selected network, so no request was sent.
final class CoordinatorNotOnNetwork extends CoordinatorFailure {
  const CoordinatorNotOnNetwork();
}

/// The request did not complete: the transport adapter maps what went wrong into one of these.
sealed class CoordinatorTransportFailure extends CoordinatorFailure {
  const CoordinatorTransportFailure();
}

/// The coordinator could not be reached: no circuit, the onion service is down, or the connection was refused or reset.
final class CoordinatorUnreachable extends CoordinatorTransportFailure {
  const CoordinatorUnreachable();
}

/// The request did not complete within the deadline the adapter enforces for the whole exchange.
final class CoordinatorTimedOut extends CoordinatorTransportFailure {
  const CoordinatorTimedOut();
}

/// The response body is larger than the request allowed: the adapter stopped reading it, or this package refused it.
final class CoordinatorResponseTooLarge extends CoordinatorTransportFailure {
  const CoordinatorResponseTooLarge();
}

/// Any other transport failure, including an exception the adapter let through.
final class CoordinatorTransportFailed extends CoordinatorTransportFailure {
  const CoordinatorTransportFailed();
}

/// The coordinator answered with an HTTP status this request does not expect.
final class CoordinatorUnexpectedStatus extends CoordinatorFailure {
  /// The HTTP status code, a number the coordinator chose.
  final int statusCode;

  const CoordinatorUnexpectedStatus(this.statusCode);
}

/// The response is not JSON: wrong or missing content type, invalid UTF-8, or a body that does not parse.
final class CoordinatorNotJson extends CoordinatorFailure {
  const CoordinatorNotJson();
}

/// The response is JSON but not what the endpoint returns: a required field is missing, has the wrong type or is out of range.
final class CoordinatorResponseMalformed extends CoordinatorFailure {
  /// The name of the first rejected field, as this package spells it: never text from the coordinator.
  final String field;

  const CoordinatorResponseMalformed(this.field);
}

/// The coordinator answered, but not as the coordinator of the federation list: a security warning for the user.
sealed class CoordinatorIdentityFailure extends CoordinatorFailure {
  const CoordinatorIdentityFailure();
}

/// The coordinator announces another network than the one selected, or one this package does not know.
final class CoordinatorNetworkMismatch extends CoordinatorIdentityFailure {
  const CoordinatorNetworkMismatch();
}

/// The Lightning node the coordinator announces is not one the federation list gives for it on this network.
final class CoordinatorNodeIdMismatch extends CoordinatorIdentityFailure {
  const CoordinatorNodeIdMismatch();
}
