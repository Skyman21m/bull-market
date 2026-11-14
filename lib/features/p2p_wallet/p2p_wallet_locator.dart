import 'package:bb_mobile/features/p2p_wallet/data/instant_wallet_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/lightning_swap_quote_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/wallet_invoice_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/wallet_payment_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/lightning_swap_quote_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/find_wallet_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/pay_checked_invoice_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_wallet_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/public/p2p_wallet_facade.dart';
import 'package:get_it/get_it.dart';

/// Registers the wallet's side of the P2P feature's wallet port; nothing is read, asked or paid until the port is used.
///
/// The facade reaches the P2P feature from the foreground composition only (`lib/locator.dart`); the WorkManager isolate registers these too, lazily, and never resolves them.
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
      () => QuoteInvoicePaymentUsecase(
        locator(),
        locator(),
        locator(),
        DateTime.now,
      ),
    );
    locator.registerLazySingleton<P2pWalletFacade>(
      () => P2pWalletFacade(
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    // The payment (#100, W3). One record of the quotes given, and one pay use case: it runs the payments one after the other.
    locator.registerLazySingleton<IssuedQuotes>(() => IssuedQuotes());
    locator.registerLazySingleton<WalletInvoiceRepository>(
      () => const WalletInvoiceRepositoryImpl(),
    );
    locator.registerLazySingleton<WalletPaymentRepository>(
      () => WalletPaymentRepositoryImpl(locator(), locator()),
    );
    locator.registerLazySingleton<PayCheckedInvoiceUsecase>(
      () => PayCheckedInvoiceUsecase(
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        DateTime.now,
      ),
    );
    locator.registerFactory<WatchWalletPaymentUsecase>(
      () => WatchWalletPaymentUsecase(locator()),
    );
    locator.registerFactory<FindWalletPaymentUsecase>(
      () => FindWalletPaymentUsecase(locator()),
    );
  }
}
