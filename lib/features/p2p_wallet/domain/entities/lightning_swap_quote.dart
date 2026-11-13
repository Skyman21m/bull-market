import 'package:p2p/p2p.dart';

/// The swap service's quote for paying a Lightning amount from Liquid: what the wallet sends it ([payin]) and its fee rate as it gives it.
final class LightningSwapQuote {
  /// What the wallet would send to the service.
  final Sats payin;

  /// The service's fee rate, in basis points.
  final int feeBasisPoints;

  const LightningSwapQuote({required this.payin, required this.feeBasisPoints});
}
