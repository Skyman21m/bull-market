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

/// The adapter had no connection to give to this request for now: the places it keeps for Tor sessions, which bound how many it opens, were all in use.
///
/// It is not proof that the coordinator works: those places go to the requests in flight, so a coordinator that holds the connections of its robots open, or drops them so that they are made again on new sessions, uses up the places of the robots it serves, up to the limits of the adapter.
/// Nothing was sent on the attempt that got this failure, and a request that is not a `GET` was not sent at all, so sending the request again is safe.
/// A caller sends it again later with an exponential backoff, caps the attempts of each request and the attempts made to each coordinator, and takes busy answers that repeat on one coordinator as a sign about that coordinator, not as a passing shortage.
final class CoordinatorTransportBusy extends CoordinatorTransportFailure {
  const CoordinatorTransportBusy();
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

/// No robot can be made from the Garage Key in the range searched: every token failed the entropy rule or had no nickname.
///
/// It takes 100 such indexes in a row, which does not happen with a Garage Key drawn at random.
final class NoUsableAccountIndex extends RobosatsFailure {
  const NoUsableAccountIndex();
}

/// The coordinator answered an authenticated request about a robot, and did not give the robot the request was made for.
///
/// As every [CoordinatorFailure], none carries text or key material the coordinator sent.
sealed class CoordinatorRobotFailure extends CoordinatorFailure {
  const CoordinatorRobotFailure();
}

/// The coordinator has no robot for this token: only a first contact, with the keys of the robot, creates one.
///
/// It is what a request with the short `Authorization` header gets from a coordinator that never saw the robot (error 7001).
final class RobotUnknown extends CoordinatorRobotFailure {
  const RobotUnknown();
}

/// The coordinator did not accept the `Authorization` header: it found no well-formed token hash in it (error 7000), did not find the three keys of a first contact (error 7001), or answered that the request is not authenticated (error 7003, or HTTP 401 or 403).
///
/// With headers built by this package it means a coordinator that reads them in another way, such as an older version.
final class RobotCredentialsRejected extends CoordinatorRobotFailure {
  const RobotCredentialsRejected();
}

/// Why a coordinator refused the OpenPGP keys of a first contact.
enum RobotKeysRefusal {
  /// GnuPG, or the shape check before it, did not accept one of the two keys (error 1034).
  invalidKey,

  /// Another robot of this coordinator already uses the public key (error 1055).
  keyAlreadyUsed,

  /// The key is less than 12 hours old for the clock of the coordinator (error 1056): the clock of this device is probably more than 12 hours ahead.
  keyTooRecent,

  /// The coordinator gave no reason this package knows.
  unspecified,
}

/// The coordinator refused the OpenPGP keys of a first contact, and created no robot (error 7002).
final class RobotKeysRefused extends CoordinatorRobotFailure {
  final RobotKeysRefusal reason;

  const RobotKeysRefused(this.reason);
}

/// The coordinator already has a user with the nickname of this robot, and created no robot (error 7004).
///
/// Two tokens share a nickname about once in 60 billion: take the next robot of the Garage Key.
final class RobotNicknameTaken extends CoordinatorRobotFailure {
  const RobotNicknameTaken();
}

/// The coordinator refused a request about an order with one of its error codes (`api/errors.py`, commit ff1998c).
///
/// Only the code is read, and for 1012 the number of seconds the coordinator writes in its message: the message itself is never kept.
/// After a take or a cancel, the client wraps it in an [OrderActionFailure], which says whether the action was done or may have been.
sealed class CoordinatorOrderFailure extends CoordinatorFailure {
  const CoordinatorOrderFailure();
}

/// The robot already has an order in progress on this coordinator, which RoboSats allows one at a time (`Logics.validate_already_maker_or_taker`, `api/logics.py:75-135`, HTTP 409).
sealed class RobotHasActiveOrder extends CoordinatorOrderFailure {
  const RobotHasActiveOrder();
}

/// The robot is the maker of an order not yet finished (error 1000).
final class RobotAlreadyMaker extends RobotHasActiveOrder {
  const RobotAlreadyMaker();
}

/// The robot is the taker of an order not yet finished (error 1001).
final class RobotAlreadyTaker extends RobotHasActiveOrder {
  const RobotAlreadyTaker();
}

/// The robot holds a live pre-take, of this order or another (error 1002): a second take of the same order while the first one waits for its bond gets this too.
final class RobotAlreadyTaking extends RobotHasActiveOrder {
  const RobotAlreadyTaking();
}

/// The robot is the buyer of an order whose payout is being sent or has failed (error 1003).
final class RobotPayoutPending extends RobotHasActiveOrder {
  const RobotPayoutPending();
}

/// The amount asked is outside the range of the order (error 1011).
final class OrderAmountOutOfRange extends CoordinatorOrderFailure {
  const OrderAmountOutOfRange();
}

/// The coordinator puts the robot on hold after it cancelled a pre-take, and refuses its takes until then (error 1012).
final class OrderTakePenalty extends CoordinatorOrderFailure {
  /// The seconds left, 0 to 86 399, read from the coordinator's message when it has the reference's exact wording, else `null`.
  final int? secondsLeft;

  const OrderTakePenalty(this.secondsLeft);
}

/// The cancel asked for the order in one status and the coordinator has it in another (error 1020): nothing was cancelled.
final class OrderStatusChanged extends CoordinatorOrderFailure {
  const OrderStatusChanged();
}

/// The order cannot be cancelled in its current status (error 1021).
final class OrderNotCancellable extends CoordinatorOrderFailure {
  const OrderNotCancellable();
}

/// The order ran out of time before the coordinator could give the taker's bond (error 1025).
final class OrderTakeExpired extends CoordinatorOrderFailure {
  const OrderTakeExpired();
}

/// The time to lock the escrow ran out before the coordinator could give the escrow (error 1026).
final class OrderEscrowExpired extends CoordinatorOrderFailure {
  const OrderEscrowExpired();
}

/// The coordinator's Lightning node cannot make the invoice now (errors 1023 and 1024).
final class CoordinatorNodeUnavailable extends CoordinatorOrderFailure {
  const CoordinatorNodeUnavailable();
}

/// The coordinator has no order with this number (error 1042).
final class OrderNotFound extends CoordinatorOrderFailure {
  const OrderNotFound();
}

/// The order has been cancelled, by one side or by both (error 1043): the coordinator shows it to nobody any more.
final class OrderCancelled extends CoordinatorOrderFailure {
  const OrderCancelled();
}

/// The order is not public and this robot is neither its maker nor its taker (error 1044): taken by another robot, paused, or not yet public.
///
/// A pre-taker whose order another robot took first gets this too.
final class OrderNotAvailable extends CoordinatorOrderFailure {
  const OrderNotAvailable();
}

/// The password sent does not open the order (error 1045).
final class OrderWrongPassword extends CoordinatorOrderFailure {
  const OrderWrongPassword();
}

/// The order is no longer public (error 1046), which the reference coordinator builds and never sends: see `TakeOrderOutcome`.
final class OrderNotPublic extends CoordinatorOrderFailure {
  const OrderNotPublic();
}

/// The order given to a cancel as its last read was read by another robot: nothing was sent.
final class OrderReadElsewhere extends CoordinatorOrderFailure {
  const OrderReadElsewhere();
}

/// The coordinator refused the request about the order with a code this package does not map, or with no code at all, as when its form check refuses the body with an empty `400`.
final class OrderRequestRefused extends CoordinatorOrderFailure {
  /// The code the coordinator gave, a number it chose, or `null`.
  final int? errorCode;

  const OrderRequestRefused(this.errorCode);
}

/// The robot the coordinator describes is not the one computed on this device: a security warning, and a robot not to use on this coordinator.
sealed class RobotMismatchFailure extends CoordinatorRobotFailure {
  const RobotMismatchFailure();
}

/// The hash id the coordinator returns is not the one derived from the token.
final class RobotHashIdMismatch extends RobotMismatchFailure {
  const RobotHashIdMismatch();
}

/// The nickname the coordinator returns is not the one derived from the hash id, which the official client and this package use to tell who wrote a chat message.
final class RobotNicknameMismatch extends RobotMismatchFailure {
  const RobotNicknameMismatch();
}

/// The OpenPGP key pair the coordinator returned for this robot is not the one this device has just sent, and the robot's token does not prove it.
///
/// A coordinator keeps the first key pair it received for a token and ignores every later one, so a robot first created by another device or client comes back with that pair.
/// Such a pair is taken only when its private key unlocks with the robot's token and holds the secret values of its public key, each of its two parts locked by an iterated and salted S2K: a coordinator receives the SHA-256 of the token, never the token, and such an S2K is salted and iterated over the token itself, so only a holder of the token can have made it.
/// A simple S2K over SHA-256 would derive exactly the token hash the coordinator holds, which is why only that S2K counts.
/// This pair was not proven: the token does not unlock both its parts, its two blocks are not the same key, a part is locked another way, it is a kind of key this package does not read, or unlocking it would hash more than `PgpLimits.proofHashedBytes`.
/// So the coordinator is not honest, or the robot was made by a client that locked its key some other way: do not use this robot there.
/// The official client silently adopts whatever pair the coordinator returns; this package does not.
final class RobotPgpKeyNotProven extends RobotMismatchFailure {
  const RobotPgpKeyNotProven();
}

/// Why an action on an order, a take or a cancel, gave no outcome: refused before anything was done, or ended in a way that does not say whether it was done.
///
/// The answer to a take or a cancel is the read of the order that follows the action (`api/views.py:593`, `:695`), so a refusal of that read, a malformed answer, a server error or a lost connection can come after the action happened: 1043 when the maker cancelled meanwhile, 1044 when another robot's bond locked between the take and the read, or when a pre-taker cancels a paused order, `kick_taker` succeeding before the read refuses (`api/views.py:270-275`).
/// Only the failures known to come before the action are an [OrderActionRefused]; every other one is an [OrderActionOutcomeUnknown].
sealed class OrderActionFailure extends RobosatsFailure {
  /// What went wrong, without any text of the coordinator.
  CoordinatorFailure get cause;

  const OrderActionFailure();
}

/// Nothing was done: the coordinator refused before the action, or the request was never sent.
///
/// That is [RobotHasActiveOrder] (1000 to 1003), [OrderAmountOutOfRange] (1011), [OrderTakePenalty] (1012), [OrderStatusChanged] (1020), [OrderNotFound] for an order number out of range, which is never sent (a 1042 received after a `POST` comes from the read that follows the action, `api/views.py:542`, and is an [OrderActionOutcomeUnknown]), [OrderWrongPassword] (1045), [OrderRequestRefused] without a code (the empty `400` of the form check), [RobotCredentialsRejected] (7000, 7003, `401`, `403`), [RobotUnknown] (7001), [OrderReadElsewhere], [CoordinatorNotOnNetwork] and [CoordinatorTransportBusy], which a transport gives only before it sends a request that is not a `GET`.
final class OrderActionRefused extends OrderActionFailure {
  @override
  final CoordinatorFailure cause;

  const OrderActionRefused(this.cause);
}

/// The action may have happened: read the order again before telling the user anything, and never send the action again blindly.
///
/// 1021 is here too: the reference coordinator answers it after side effects on some paths, as when settling a bond fails after the on-chain payout was cancelled (`api/logics.py:1108-1130`, `:1178-1181`).
final class OrderActionOutcomeUnknown extends OrderActionFailure {
  @override
  final CoordinatorFailure cause;

  const OrderActionOutcomeUnknown(this.cause);
}
