import 'package:bb_mobile/core/utils/payment_request.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:p2p/p2p.dart';

/// Reads an invoice with the wallet's `PaymentRequest.parse`, the decoder of its Send screen (Boltz's, through the wallet's SDK).
///
/// This class logs nothing. The wallet's decoder logs, at the `warning` level (the on-disk support log), the text of an error of the libraries it tries when it cannot read the string as an invoice (`payment_request.dart`, its BOLT11 then Liquid address readers): an invoice the trade's decoder read is expected to read here too, and whether those texts repeat the string they were given could not be established without running them.
class WalletInvoiceRepositoryImpl implements WalletInvoiceRepository {
  final Future<PaymentRequest> Function(String) _parse;

  /// [parse] is the wallet's decoder, `PaymentRequest.parse` unless a test gives another.
  const WalletInvoiceRepositoryImpl([this._parse = PaymentRequest.parse]);

  @override
  Future<Result<WalletInvoice, P2pWalletRefusal>> read(String bolt11) async {
    final PaymentRequest request;
    try {
      request = await _parse(bolt11);
    } catch (_) {
      return const Err(P2pWalletInvoiceUnreadable());
    }
    return switch (request) {
      Bolt11PaymentRequest(
        :final amountSat,
        :final paymentHash,
        :final expiresAt,
        :final isTestnet,
      )
          when amountSat > 0 && expiresAt > 0 =>
        Ok(
          WalletInvoice(
            amount: Sats.fromInt(amountSat),
            paymentHash: paymentHash.toLowerCase(),
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              expiresAt * 1000,
              isUtc: true,
            ),
            isTestnet: isTestnet,
          ),
        ),
      _ => const Err(P2pWalletInvoiceUnreadable()),
    };
  }
}
