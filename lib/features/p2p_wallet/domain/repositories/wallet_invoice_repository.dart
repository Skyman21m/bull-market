import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The wallet's own decoder of Lightning invoices, the one its Send screen uses: a second reading of an invoice the trade's checks read already, before the wallet pays it.
abstract interface class WalletInvoiceRepository {
  /// [bolt11] as the wallet's decoder reads it, or [P2pWalletInvoiceUnreadable] when it does not read it as a BOLT11 invoice with an amount of whole satoshis.
  @useResult
  Future<Result<WalletInvoice, P2pWalletRefusal>> read(String bolt11);

  /// The payment hash of [bolt11] as the wallet's decoder reads it, in lower case, whatever its amount (none, or a fraction of a satoshi, as the wallet's Send screen pays), or `null` when the decoder reads no invoice: for finding the orders of a hash, never for paying.
  Future<String?> paymentHashOf(String bolt11);
}
