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

/// The text cannot be clear-signed for a coordinator, whose extraction (`api/utils.py:642-644`) would not hand it back intact: it is empty; it starts or ends with whitespace as Dart's `String.trim` sees it, or with U+001C to U+001F, which Python's `str.strip` removes; it contains a carriage return, `-----BEGIN PGP SIGNED MESSAGE-----` or `-----BEGIN PGP SIGNATURE-----` anywhere; or one of its lines starts with a dash or ends with a space or a tab.
///
/// Nothing else is refused: other control characters, U+0000 included, lone surrogates and any non-ASCII text are signed, and a coordinator may then refuse the message (its form check or its GnuPG fails), but it never reads another text from it. A payout's text is ASCII by construction (`UnlockedRobotPgpKey.signPayoutInvoice`, `signPayoutAddress`).
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

/// The robot is neither the maker nor the taker of the order (error 1047, HTTP 403, `api/views.py:617-619`), which the coordinator checks before any action but a take or a cancel: a pre-taker is not yet the taker.
final class OrderNotParticipant extends CoordinatorOrderFailure {
  const OrderNotParticipant();
}

/// The coordinator refused the buyer's payout, an invoice or an address, or this package refused to send it (`Logics.update_invoice` and `Logics.update_address`, `api/logics.py:752-907`, commit ff1998c).
///
/// Each is a kind, never the coordinator's text: the reference sends some of these refusals without any code, as a bare `bad_invoice` or `bad_address` text, which is compared with the reference's exact wording and never kept.
/// Every one of them comes before the coordinator records a payout, so after a submission refused this way the order has no new payout (see `CoordinatorClient.submitPayoutInvoice`).
/// Some are decided by this package before anything is sent: [fromLastRead] says which come from the last read of the order, which may be stale.
sealed class PayoutRefused extends CoordinatorOrderFailure {
  const PayoutRefused();

  /// Whether this package refused from the last read of the order, sending nothing, rather than the coordinator: [PayoutNotBuyer] and [PayoutNotNow] decided locally, and [PayoutSwapUnavailable].
  ///
  /// A last read may be stale: after such a refusal, read the order again and decide from the fresh read before telling the user anything.
  bool get fromLastRead => false;
}

/// Why a payout invoice was refused.
enum PayoutInvoiceRefusal {
  /// The signed text holds no invoice (error 3000).
  empty,

  /// The coordinator's node cannot decode it: not an invoice, or, on a node that checks it, an invoice of another network (`validate_ln_invoice`, `api/lightning/lnd.py:463-469`, no code).
  notAnInvoice,

  /// The invoice's private route hints cost more than the routing budget allows (`lnd.py:486-506`, no code).
  routeHintsUnpayable,

  /// The invoice has no amount (`lnd.py:508-512`, no code).
  noAmount,

  /// The invoice is not for the amount the coordinator computes from the trade and the routing budget (`lnd.py:514-520`, no code).
  wrongAmount,

  /// The invoice has already expired (`lnd.py:529-533`, no code); the coordinator does not check how long it has left.
  expired,

  /// The invoice is the one already given, the same payment hash (error 3002): a new one is needed, as after a failed payout.
  alreadySubmitted,

  /// The invoice is for another network than the order's: refused by this package before anything is sent.
  wrongNetwork,

  /// A `bad_invoice` text the reference does not write.
  unspecified,
}

/// The payout invoice was refused for [reason].
final class PayoutInvoiceRefused extends PayoutRefused {
  final PayoutInvoiceRefusal reason;

  const PayoutInvoiceRefused(this.reason);
}

/// Why a payout address was refused.
enum PayoutAddressRefusal {
  /// The signed text holds no address (error 4000).
  empty,

  /// The coordinator's bitcoind says it is not an address (`validate_onchain_address`, `api/utils.py:113-114`, no code; 4004 is defined for it but not sent at the reference).
  invalid,

  /// The coordinator could not ask its bitcoind (`api/utils.py:115-119`, no code; 4005 is defined for it but not sent at the reference): nothing is wrong with the address as far as anyone knows.
  unverifiable,

  /// The address is for another network than the order's: refused by this package before anything is sent.
  wrongNetwork,

  /// A `bad_address` text the reference does not write.
  unspecified,
}

/// The payout address was refused for [reason].
final class PayoutAddressRefused extends PayoutRefused {
  final PayoutAddressRefusal reason;

  const PayoutAddressRefused(this.reason);
}

/// The mining fee rate is below what the coordinator accepts now, the larger of 2 sat/vB and its economy estimate (error 4001, `api/logics.py:780-793`).
final class PayoutMiningFeeTooLow extends PayoutRefused {
  /// The coordinator's minimum in sat/vB, 2 to 1,000, read from its message when it has the reference's exact wording, else `null`.
  final double? minimumSatPerVbyte;

  const PayoutMiningFeeTooLow(this.minimumSatPerVbyte);
}

/// The mining fee rate is above 500 sat/vB (error 4002, `api/logics.py:794-799`).
final class PayoutMiningFeeTooHigh extends PayoutRefused {
  const PayoutMiningFeeTooHigh();
}

/// What the address would receive after the swap fee and the mining fee of 280 vB is under 20,000 sats (error 4003, `api/logics.py:806-820`).
final class PayoutBelowDustLimit extends PayoutRefused {
  const PayoutBelowDustLimit();
}

/// The signed text is not a valid signature by the robot's key, as the coordinator's GnuPG reads it (error 1048, `api/utils.py:628-648`).
final class PayoutSignatureRefused extends PayoutRefused {
  const PayoutSignatureRefused();
}

/// The robot is not the buyer of the order (errors 1015 and 1017), or the last read does not show it as the buyer ([fromLastRead]).
final class PayoutNotBuyer extends PayoutRefused {
  @override
  final bool fromLastRead;

  const PayoutNotBuyer({required this.fromLastRead});
}

/// The order is not at a step that takes this payout: both bonds not locked (1018, 1019, 1016), a status other than 6 or 8, or 15 for an invoice once the failed one expired (3001, 1016), or a payout being sent (3001); or the last read already shows so ([fromLastRead]).
final class PayoutNotNow extends PayoutRefused {
  @override
  final bool fromLastRead;

  const PayoutNotNow({required this.fromLastRead});
}

/// The last read of the order does not offer an on-chain payout (`swap_allowed`): refused by this package before anything is sent, since the reference coordinator then fails with a `500` (`api/logics.py:800-803`, `order.payout_tx` is `None`).
final class PayoutSwapUnavailable extends PayoutRefused {
  const PayoutSwapUnavailable();

  @override
  bool get fromLastRead => true;
}

/// The payout was signed by the key of another robot than the one that submits it: refused by this package before anything is sent, since the coordinator checks the signature against the submitting robot's key (1048).
final class PayoutSignedByAnotherRobot extends PayoutRefused {
  const PayoutSignedByAnotherRobot();
}

/// A payout destination, an on-chain address or a Lightning invoice, that this package refuses to sign: checked before anything is signed or sent.
///
/// None carries the text: an address or an invoice is not secret, but it is never logged.
sealed class PayoutDestinationFailure extends RobosatsFailure {
  const PayoutDestinationFailure();
}

/// Not an address or an invoice of a kind this package reads: too long, a character outside the encoding, whitespace, mixed case, an unknown prefix or version, a program of the wrong length, or an invoice amount BOLT11 forbids (a leading zero, a `p` amount not ending in 0, not a whole number of satoshis).
final class PayoutDestinationMalformed extends PayoutDestinationFailure {
  const PayoutDestinationMalformed();
}

/// The checksum does not match: most likely a typo.
final class PayoutDestinationBadChecksum extends PayoutDestinationFailure {
  const PayoutDestinationBadChecksum();
}

/// A valid address or invoice of another network than the trade's: the other of mainnet and testnet, regtest, or, for an invoice, signet.
final class PayoutDestinationWrongNetwork extends PayoutDestinationFailure {
  const PayoutDestinationWrongNetwork();
}

/// A Lightning invoice without an amount: the coordinator refuses one (`validate_ln_invoice`, `api/lightning/lnd.py:508-512`), and the payout's amount is fixed by the order, so it is refused before signing.
final class PayoutDestinationNoAmount extends PayoutDestinationFailure {
  const PayoutDestinationNoAmount();
}

/// A valid segwit address of a kind this package does not sign for a payout: version 1 with a program other than 32 bytes, or versions 2 to 16.
final class PayoutDestinationUnsupported extends PayoutDestinationFailure {
  const PayoutDestinationUnsupported();
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

/// Why an action on an order, a take, a cancel or a payout, gave no outcome: refused before anything was done, or ended in a way that does not say whether it was done.
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
/// For a payout, also every [PayoutRefused] and [OrderNotParticipant] (1047).
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

/// Why a request about the chat of an order was refused, by the coordinator (errors 6000 to 6003, `chat/views.py`, commit ff1998c) or by this package before anything was sent.
enum ChatRefusal {
  /// The coordinator read no order number in a read (error 6000, `chat/views.py:48-49`): this package always sends one, so it means a coordinator that reads the request in another way.
  ///
  /// A post never gets it from the reference, whose serializer refuses a missing order number first with 6003 (`:121-129`).
  orderIdMissing,

  /// The robot is neither the maker nor the taker of the order (error 6001, `:53-54`, `:133-134`), or the last read of the order does not show it as one of them with a named peer.
  notParticipant,

  /// The order is not at a status where the coordinator takes this request (error 6002, `:56-62`, `:136-137`), or the last read is not at one: reading at 9, 10, 11 and 16, posting at 9 and 10.
  notInChat,

  /// The coordinator's serializer refused the body of a post (error 6003, `:121-124`, `chat/serializers.py:279-302`), which a body built by this package always passes.
  invalidRequest,

  /// The offset is not between 0 and `ChatPage.maxIndex`: refused by this package before anything is sent.
  offsetOutOfRange,

  /// The message was encrypted and signed by another robot's key than the one posting it: refused by this package before anything is sent.
  messageOfAnotherRobot,

  /// The encrypted message would take more than `OutgoingChatMessage.maxWireChars` characters on the wire: refused by this package when encrypting it.
  messageTooLong,
}

/// A request about the chat of an order was refused for [reason]: nothing was stored (see `CoordinatorClient.postChat`).
///
/// Only the code is read, never the coordinator's text.
final class ChatRefused extends CoordinatorOrderFailure {
  final ChatRefusal reason;

  const ChatRefused(this.reason);
}
