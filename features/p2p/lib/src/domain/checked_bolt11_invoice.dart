import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart' show Sats;
import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// A Lightning invoice (BOLT11) that the trade screen decoded, checked and showed, the only kind of invoice the wallet's port takes (design note § 4.4, #100).
///
/// It is not a decoder: the feature's BOLT11 check (#86) decodes the string, checks it against the order, and builds this value from the exact string it decoded and what it read in it; the value itself refuses only what no such invoice can be.
/// Outside `package:p2p` nothing can build one, since [of] is `@internal`: a string received from a coordinator cannot reach the wallet's port without that check.
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

  /// The invoice [bolt11], decoded by the feature's check as [amount] on [network], expiring at [expiresAt]; `null` when no BOLT11 invoice of that network and amount can be that string.
  ///
  /// Refused: more than [maxLength] characters, any character that is not visible ASCII (`!` to `~`), upper and lower case mixed (bech32 allows one case only), a prefix that is not the network's with an amount (`lnbc` and a digit on mainnet, `lntb` or `lntbs` and a digit on testnet, so neither regtest's `lnbcrt` nor an invoice without an amount), and an amount of zero.
  @internal
  static CheckedBolt11Invoice? of({
    required String bolt11,
    required Sats amount,
    required RobosatsNetwork network,
    required DateTime expiresAt,
  }) {
    if (bolt11.length > maxLength || !_visibleAscii.hasMatch(bolt11)) {
      return null;
    }
    final lower = bolt11.toLowerCase();
    if (bolt11 != lower && bolt11 != bolt11.toUpperCase()) return null;
    final prefix = switch (network) {
      RobosatsNetwork.mainnet => _mainnetPrefix,
      RobosatsNetwork.testnet => _testnetPrefix,
    };
    if (!prefix.hasMatch(lower)) return null;
    if (amount.value <= BigInt.zero) return null;
    return CheckedBolt11Invoice._(bolt11, amount, network, expiresAt.toUtc());
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

final _mainnetPrefix = RegExp('^lnbc[0-9]');

final _testnetPrefix = RegExp('^lntbs?[0-9]');
