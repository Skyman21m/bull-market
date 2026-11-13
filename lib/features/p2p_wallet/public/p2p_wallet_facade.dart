import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:p2p/p2p.dart';

/// The wallet's side of the P2P feature's wallet port (#100): the balance of the Instant Payments wallet and the swap service's quote for paying a checked invoice from it.
///
/// It lives in this Troc feature because it depends on both sides, the P2P feature's contract and the wallet's swap and wallet readers (`AGENTS.md`, rule 7): nothing of it is in `lib/core`, and the wallet's send feature is unchanged.
/// It moves no money: it signs nothing, broadcasts nothing and creates no order at the swap service. Paying is added by a later pull request, reviewed as money code.
/// The shell constructs it in `lib/locator.dart` only, and hands it to `P2pFeature.setup` in the foreground composition only.
final class P2pWalletFacade implements P2pWalletPort {
  final WatchInstantBalanceUsecase _watchBalance;
  final QuoteInvoicePaymentUsecase _quote;

  const P2pWalletFacade(this._watchBalance, this._quote);

  @override
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(
    RobosatsNetwork network,
  ) => _watchBalance.execute(network);

  @override
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(
    CheckedBolt11Invoice invoice,
  ) => _quote.execute(invoice);
}
