import 'package:primitives/primitives.dart';

/// The sats of each maker seller's escrow this run of the app asked the wallet to pay, by payment hash (#187): what the confirmation of a next contract says of the earlier escrows not back yet.
///
/// In memory only, one for the feature: `trade_payments` keeps no amount (schema 8, design note § 3.5), and the wallet's port gives none; after the app started again, an earlier escrow's sats are unknown, and the confirmation says so.
final class EscrowAmounts {
  final Map<String, Sats> _sats = {};

  /// The sats of the escrow of [paymentHash], `null` when this run did not ask the wallet to pay it.
  Sats? of(String paymentHash) => _sats[paymentHash];

  /// Keeps [sats] for the escrow of [paymentHash], asked of the wallet now.
  void keep(String paymentHash, Sats sats) => _sats[paymentHash] = sats;
}
