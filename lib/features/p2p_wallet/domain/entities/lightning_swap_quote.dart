import 'package:p2p/p2p.dart';

/// The swap service's quote for paying a Lightning amount from Liquid: what the wallet would send it ([payin]), from which the service pays the amount and keeps the rest as its fee.
final class LightningSwapQuote {
  /// What the wallet would send to the service.
  final Sats payin;

  const LightningSwapQuote({required this.payin});
}
