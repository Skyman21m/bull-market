import 'package:bb_mobile/features/p2p_wallet/domain/usecases/find_wallet_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/pay_checked_invoice_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_wallet_payment_usecase.dart';
import 'package:p2p/p2p.dart';

/// The wallet's side of the P2P feature's wallet port (#100): the balance of the Instant Payments wallet, the swap service's quote for paying a checked invoice from it, and the payment itself.
///
/// It lives in this Troc feature because it depends on both sides, the P2P feature's contract and the wallet's swap and wallet code (`AGENTS.md`, rule 7): nothing of it is in `lib/core`, and the wallet's send feature is unchanged.
/// [payInvoice] moves money: it creates a swap order, signs and broadcasts the funding transaction, all in `PayCheckedInvoiceUsecase`, the one file of this feature allowed to (`wallet_shell_architecture_test.dart`). [watchPayment] and [findPayment] read the wallet's records only.
/// The shell constructs it in `lib/locator.dart` only, and hands it to `P2pFeature.setup` in the foreground composition only.
final class P2pWalletFacade implements P2pWalletPort {
  final WatchInstantBalanceUsecase _watchBalance;
  final QuoteInvoicePaymentUsecase _quote;
  final PayCheckedInvoiceUsecase _pay;
  final WatchWalletPaymentUsecase _watchPayment;
  final FindWalletPaymentUsecase _findPayment;

  const P2pWalletFacade(
    this._watchBalance,
    this._quote,
    this._pay,
    this._watchPayment,
    this._findPayment,
  );

  @override
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(
    RobosatsNetwork network,
  ) => _watchBalance.execute(network);

  @override
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(
    CheckedBolt11Invoice invoice,
  ) => _quote.execute(invoice);

  @override
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payInvoice(
    CheckedBolt11Invoice invoice, {
    required P2pWalletQuote accepted,
  }) => _pay.execute(invoice, accepted: accepted);

  @override
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watchPayment(
    P2pWalletPayment payment,
  ) => _watchPayment.execute(payment);

  @override
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> findPayment(
    String paymentHash,
  ) => _findPayment.execute(paymentHash);
}
