import 'package:bb_mobile/features/p2p_wallet/data/instant_wallet_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/lightning_swap_quote_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/lightning_swap_quote_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/public/p2p_wallet_facade.dart';
import 'package:get_it/get_it.dart';

/// Registers the wallet's side of the P2P feature's wallet port; nothing is read or asked until the port is used.
class P2pWalletLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<InstantWalletRepository>(
      () => InstantWalletRepositoryImpl(
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    locator.registerLazySingleton<LightningSwapQuoteRepository>(
      () => LightningSwapQuoteRepositoryImpl(locator()),
    );
    locator.registerFactory<WatchInstantBalanceUsecase>(
      () => WatchInstantBalanceUsecase(locator()),
    );
    locator.registerFactory<QuoteInvoicePaymentUsecase>(
      () => QuoteInvoicePaymentUsecase(locator(), locator(), DateTime.now),
    );
    locator.registerLazySingleton<P2pWalletFacade>(
      () => P2pWalletFacade(locator(), locator()),
    );
  }
}
