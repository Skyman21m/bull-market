import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart' show Sats;
import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// A Lightning invoice (BOLT11) that the trade's state machine decoded and checked for the current status and step, within the amount the user accepted: the only kind of invoice the wallet's port takes (design note § 4.4, #100).
///
/// It is not a decoder. Its one source is `walletPaymentFor` (`trade/wallet_payment.dart`), which builds it from a `CheckedInvoice` of the latest status when it offers « Pay with this wallet » (`WalletPaymentOffered`), with the exact string decoded, its amount, the trade's network, its payment hash and when it stops being payable; the tests' helper of `testing.dart` is the only other caller of [of] (`wallet_port_architecture_test.dart`).
/// What this value checks again by itself, independently of the decoder of #86: the string is at most [maxLength] visible ASCII characters in one case; its human-readable part, up to the last `1` (the bech32 separator), is `ln`, the prefix of [network] (`bc` on mainnet, `tb` on testnet; signet's `tbs`, regtest's `bcrt` and any other prefix are another network, #113), and an amount with no leading zero whose multiplier, if any, is `m`, `u`, `n` or `p` (a `p` amount ending in 0); that amount is a whole number of satoshis above zero and at most 21 million bitcoin, equal to [amount]; the data after the separator is not empty and holds only bech32 characters; the payment hash is 64 lowercase hexadecimal characters; [payableUntil] is not after [expiresAt]; and the invoice is still payable at the time given.
/// The human-readable part is read in three places that cannot import each other: here, by the trade's decoder (`lib/features/p2p_bolt11/bolt11_decoder_impl.dart`, with `Bolt11Network.belongsTo` of `trade/bolt11.dart`) and by the payout's shape check of `packages/robosats` (`checkPayoutInvoice`, #111). They agree on the networks (`lnbc` mainnet, `lntb` testnet, anything else another network), on a whole number of satoshis and on no leading zero. They differ in two ways, harmless here: the trade's decoder caps the amount's digits at 18 (so an amount past that is unreadable there, while here and in the payout check it is refused above 21 million bitcoin), and the payout check accepts an invoice without an amount for its own refusal (`PayoutDestinationNoAmount`), where this value and the trade require one. A change to one is a change to the three.
/// What it does not check: the bech32 checksum, the signature and the payee, the description, and [paymentHash] and [expiresAt] against the string, which the decoder of #86 checks before the state machine builds a `CheckedInvoice`; the wallet's own decoder checks them again before it pays (`lib/features/p2p_wallet`).
/// Outside `package:p2p` nothing can build one, since [of] is `@internal`. So a string received from a coordinator cannot reach the wallet's port without the state machine's checks.
/// Its [toString] names no part of the invoice, so that printing or logging it by mistake writes nothing of it.
final class CheckedBolt11Invoice {
  /// The longest invoice accepted, in characters, as the design note bounds an invoice before it is decoded (§ 4.4).
  static const maxLength = 2000;

  /// The most satoshis an invoice may ask for: 21 million bitcoin, as `packages/robosats` bounds every amount it reads (`CoordinatorReadBounds.maxSats`).
  static final maxSats = BigInt.from(2100000000000000);

  /// The exact string that was decoded and shown, never read again from the coordinator.
  final String bolt11;

  /// The amount of the invoice.
  final Sats amount;

  /// The network of the invoice, the trade's own.
  final RobosatsNetwork network;

  /// The invoice's payment hash, 64 lowercase hexadecimal characters: a payment is bound to it.
  final String paymentHash;

  /// When the invoice expires, in UTC, as its timestamp and expiry say.
  final DateTime expiresAt;

  /// When paying it stops making sense, in UTC: the earlier of [expiresAt] and the coordinator's deadline for the step (design note § 1.1).
  final DateTime payableUntil;

  const CheckedBolt11Invoice._(
    this.bolt11,
    this.amount,
    this.network,
    this.paymentHash,
    this.expiresAt,
    this.payableUntil,
  );

  /// The invoice [bolt11], decoded by the trade's checks as [amount] on [network] with [paymentHash], expiring at [expiresAt] and payable until [payableUntil]; `null` when the string is not such an invoice as far as this value can tell (above), or when it is no longer payable at [now].
  @internal
  static CheckedBolt11Invoice? of({
    required String bolt11,
    required Sats amount,
    required RobosatsNetwork network,
    required String paymentHash,
    required DateTime expiresAt,
    required DateTime payableUntil,
    required DateTime now,
  }) {
    if (bolt11.length > maxLength || !_visibleAscii.hasMatch(bolt11)) {
      return null;
    }
    final lower = bolt11.toLowerCase();
    if (bolt11 != lower && bolt11 != bolt11.toUpperCase()) return null;
    // The human-readable part ends at the last `1`, the bech32 separator, which the data part cannot hold.
    final separator = lower.lastIndexOf('1');
    if (separator < 0) return null;
    if (!_bech32Data.hasMatch(lower.substring(separator + 1))) return null;
    final hrp = _humanReadablePart.firstMatch(lower.substring(0, separator));
    if (hrp == null) return null;
    final prefixOfNetwork = switch (hrp.group(1)) {
      'bc' => network == RobosatsNetwork.mainnet,
      'tb' => network == RobosatsNetwork.testnet,
      _ => false,
    };
    if (!prefixOfNetwork) return null;
    final sats = _satsOf(hrp.group(2) ?? '', hrp.group(3) ?? '');
    if (sats == null ||
        sats != amount.value ||
        sats <= BigInt.zero ||
        sats > maxSats) {
      return null;
    }
    if (!_paymentHash.hasMatch(paymentHash)) return null;
    final expiry = expiresAt.toUtc();
    final until = payableUntil.toUtc();
    if (until.isAfter(expiry)) return null;
    if (!now.isBefore(until)) return null;
    return CheckedBolt11Invoice._(
      bolt11,
      amount,
      network,
      paymentHash,
      expiry,
      until,
    );
  }

  /// Whether the invoice is no longer payable at [now]: it expired, or the coordinator's step ended ([payableUntil]).
  bool isExpiredAt(DateTime now) => !now.isBefore(payableUntil);

  /// Whether [other] is the same invoice: the same string, amount, network and payment hash, whenever it was read.
  ///
  /// A later read of the same trade gives the same invoice with the same deadline in practice; a payment compares invoices with this, and takes the latest [payableUntil].
  bool isSameInvoiceAs(CheckedBolt11Invoice other) =>
      other.bolt11 == bolt11 &&
      other.amount == amount &&
      other.network == network &&
      other.paymentHash == paymentHash;

  @override
  bool operator ==(Object other) =>
      other is CheckedBolt11Invoice &&
      isSameInvoiceAs(other) &&
      other.expiresAt == expiresAt &&
      other.payableUntil == payableUntil;

  @override
  int get hashCode => Object.hash(
    bolt11,
    amount,
    network,
    paymentHash,
    expiresAt,
    payableUntil,
  );

  @override
  String toString() => 'CheckedBolt11Invoice';
}

/// One or more visible ASCII characters, from `!` to `~`, and nothing else.
final _visibleAscii = RegExp(r'^[\x21-\x7e]+$');

/// One or more characters of the bech32 alphabet (BIP-173), in lower case.
final _bech32Data = RegExp(r'^[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+$');

/// A payment hash as the trade's reader gives it: 64 lowercase hexadecimal characters.
final _paymentHash = RegExp(r'^[0-9a-f]{64}$');

/// A BOLT11 human-readable part with an amount: `ln`, the prefix of mainnet (`bc`) or testnet (`tb`), the amount's digits without a leading zero, and its multiplier if any. Signet's `tbs` and regtest's `bcrt` do not match: their letter after the prefix is not a digit (#113).
final _humanReadablePart = RegExp(r'^ln(bc|tb)([1-9][0-9]*)([munp]?)$');

/// The amount of a human-readable part in satoshis, from its [digits] in bitcoin times its [multiplier] (BOLT11: `m` 10⁻³, `u` 10⁻⁶, `n` 10⁻⁹, `p` 10⁻¹²), in exact integer arithmetic; `null` for a `p` amount not ending in 0 (BOLT11 refuses it) or an amount that is not a whole number of satoshis.
BigInt? _satsOf(String digits, String multiplier) {
  final value = BigInt.parse(digits);
  // In millisatoshis: 1 bitcoin is 10¹¹ of them.
  final BigInt millisats;
  switch (multiplier) {
    case '':
      millisats = value * BigInt.from(10).pow(11);
    case 'm':
      millisats = value * BigInt.from(10).pow(8);
    case 'u':
      millisats = value * BigInt.from(10).pow(5);
    case 'n':
      millisats = value * BigInt.from(100);
    case 'p':
      if (value % BigInt.from(10) != BigInt.zero) return null;
      millisats = value ~/ BigInt.from(10);
    default:
      return null;
  }
  if (millisats % BigInt.from(1000) != BigInt.zero) return null;
  return millisats ~/ BigInt.from(1000);
}
