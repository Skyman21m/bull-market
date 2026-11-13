import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart' show Sats;
import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// A Lightning invoice (BOLT11) that the trade screen decoded, checked and showed, the only kind of invoice the wallet's port takes (design note § 4.4, #100).
///
/// It is not a decoder: the feature's BOLT11 check (#86) decodes the string, checks it against the order, and builds this value from the exact string it decoded and the facts it read in it. The two will become one type once both are on `main`.
/// What this value guarantees by itself: the string is at most [maxLength] visible ASCII characters in one case; its human-readable part, up to the last `1` (the bech32 separator), is `ln`, the prefix of [network] (`bc` on mainnet, `tb` or `tbs` on testnet), and an amount with no leading zero whose multiplier, if any, is `m`, `u`, `n` or `p` (a `p` amount ending in 0); that amount is a whole number of satoshis above zero, equal to [amount]; the data after the separator is not empty and holds only bech32 characters; and the invoice has not expired at the time given.
/// What it does not check: the bech32 checksum, the signature and the payee, the payment hash, the description, and [expiresAt] against the string's own timestamp and expiry fields. The decoder of #86 checks those before it builds the value.
/// Outside `package:p2p` nothing can build one, since [of] is `@internal`; inside it, only the files that `wallet_port_architecture_test.dart` lists may call [of]. So a string received from a coordinator cannot reach the wallet's port without that check.
/// Its [toString] names no part of the invoice, so that printing or logging it by mistake writes nothing of it.
final class CheckedBolt11Invoice {
  /// The longest invoice accepted, in characters, as the design note bounds an invoice before it is decoded (§ 4.4).
  static const maxLength = 2000;

  /// The exact string that was decoded and shown, never read again from the coordinator.
  final String bolt11;

  /// The amount of the invoice.
  final Sats amount;

  /// The network of the invoice, the trade's own.
  final RobosatsNetwork network;

  /// When the invoice expires, in UTC, as its timestamp and expiry say; the coordinator's own deadline for the step may come earlier (design note § 1.1).
  final DateTime expiresAt;

  const CheckedBolt11Invoice._(
    this.bolt11,
    this.amount,
    this.network,
    this.expiresAt,
  );

  /// The invoice [bolt11], decoded by the feature's check as [amount] on [network], expiring at [expiresAt]; `null` when the string is not such an invoice as far as this value can tell (above), or when it has expired at [now].
  @internal
  static CheckedBolt11Invoice? of({
    required String bolt11,
    required Sats amount,
    required RobosatsNetwork network,
    required DateTime expiresAt,
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
      'tb' || 'tbs' => network == RobosatsNetwork.testnet,
      _ => false,
    };
    if (!prefixOfNetwork) return null;
    final sats = _satsOf(hrp.group(2) ?? '', hrp.group(3) ?? '');
    if (sats == null || sats != amount.value || sats <= BigInt.zero) {
      return null;
    }
    final expiry = expiresAt.toUtc();
    if (!now.isBefore(expiry)) return null;
    return CheckedBolt11Invoice._(bolt11, amount, network, expiry);
  }

  /// Whether the invoice has expired at [now].
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  @override
  bool operator ==(Object other) =>
      other is CheckedBolt11Invoice &&
      other.bolt11 == bolt11 &&
      other.amount == amount &&
      other.network == network &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(bolt11, amount, network, expiresAt);

  @override
  String toString() => 'CheckedBolt11Invoice';
}

/// One or more visible ASCII characters, from `!` to `~`, and nothing else.
final _visibleAscii = RegExp(r'^[\x21-\x7e]+$');

/// One or more characters of the bech32 alphabet (BIP-173), in lower case.
final _bech32Data = RegExp(r'^[qpzry9x8gf2tvdw0s3jn54khce6mua7l]+$');

/// A BOLT11 human-readable part with an amount: `ln`, the network's prefix, the amount's digits without a leading zero, and its multiplier if any. `tbs` is tried before `tb`, so that signet's prefix is not read as testnet's followed by an `s`.
final _humanReadablePart = RegExp(r'^ln(bc|tbs|tb)([1-9][0-9]*)([munp]?)$');

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
