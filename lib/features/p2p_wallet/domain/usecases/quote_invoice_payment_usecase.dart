import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/lightning_swap_quote.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/lightning_swap_quote_repository.dart';
import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The quote for paying a checked invoice from the Instant Payments wallet: the swap service's payin and fee, the wallet's network fee, the total and what stays.
///
/// It moves nothing: it reads the wallet, asks the service (the amount and the route only), and builds an unsigned transaction to the wallet's own address to read its fee.
/// The service is asked only once the invoice, the wallet and its balance allow the payment, so that an invoice that cannot be paid sends the service nothing.
class QuoteInvoicePaymentUsecase {
  final InstantWalletRepository _wallets;
  final LightningSwapQuoteRepository _quotes;
  final DateTime Function() _now;

  const QuoteInvoicePaymentUsecase(this._wallets, this._quotes, this._now);

  @useResult
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> execute(
    CheckedBolt11Invoice invoice,
  ) async {
    if (invoice.isExpiredAt(_now())) {
      return const Err(P2pWalletInvoiceExpired());
    }
    final InstantWallet wallet;
    switch (await _wallets.read()) {
      case Ok(:final value):
        wallet = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (wallet.refusalFor(invoice.network) case final refusal?) {
      return Err(refusal);
    }
    // The wallet's send screen compares the balance with the payin only; the invoice alone is less than any payin.
    if (wallet.balance.value < invoice.amount.value) {
      return Err(
        P2pWalletNotEnoughBalance(
          available: wallet.balance,
          needed: invoice.amount,
        ),
      );
    }
    final LightningSwapQuote service;
    switch (await _quotes.quote(
      network: invoice.network,
      amount: invoice.amount,
    )) {
      case Ok(:final value):
        service = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (wallet.balance.value < service.payin.value) {
      return Err(
        P2pWalletNotEnoughBalance(
          available: wallet.balance,
          needed: service.payin,
        ),
      );
    }
    final Sats networkFee;
    switch (await _wallets.estimateNetworkFee(wallet, service.payin)) {
      case Ok(:final value):
        networkFee = value;
      case Err(:final failure):
        return Err(failure);
    }
    final total = service.payin.value + networkFee.value;
    if (wallet.balance.value < total) {
      return Err(
        P2pWalletNotEnoughBalance(
          available: wallet.balance,
          needed: Sats(total),
        ),
      );
    }
    return Ok(
      P2pWalletQuote(
        invoice: invoice,
        payin: service.payin,
        serviceFeeBasisPoints: service.feeBasisPoints,
        networkFee: networkFee,
        balance: wallet.balance,
        quotedAt: _now(),
      ),
    );
  }
}
