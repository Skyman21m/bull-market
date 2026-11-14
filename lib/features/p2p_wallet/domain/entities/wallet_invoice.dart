import 'package:p2p/p2p.dart';

/// A Lightning invoice as the wallet's own decoder reads it (the decoder its Send screen uses): what a payment checks again before it pays. No description, no payee.
final class WalletInvoice {
  /// The amount, in whole satoshis.
  final Sats amount;

  /// The payment hash, as the decoder gives it.
  final String paymentHash;

  /// When the invoice expires, in UTC.
  final DateTime expiresAt;

  /// Whether the decoder reads it as an invoice of a test network.
  final bool isTestnet;

  const WalletInvoice({
    required this.amount,
    required this.paymentHash,
    required this.expiresAt,
    required this.isTestnet,
  });

  @override
  String toString() => 'WalletInvoice';
}
