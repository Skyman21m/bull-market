import 'dart:io';

import 'package:bb_mobile/core/screens/route_error_screen.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/announcements/presentation/announcements_cubit.dart';
import 'package:bb_mobile/features/autobuy/public/autobuy_facade.dart';
import 'package:bb_mobile/features/app_unlock/ui/app_unlock_router.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/bip85_entropy/router.dart';
import 'package:bb_mobile/features/bitbox/ui/bitbox_router.dart';
import 'package:bb_mobile/features/broadcast_signed_tx/router.dart';
import 'package:bb_mobile/features/buy/ui/buy_router.dart';
import 'package:bb_mobile/features/coins/ui/coins_router.dart';
import 'package:bb_mobile/features/consolidation/ui/consolidation_router.dart';
import 'package:bb_mobile/features/dca/ui/dca_router.dart';
import 'package:bb_mobile/features/limit_orders/public/limit_orders_facade.dart';
import 'package:bb_mobile/features/electrum_settings/frameworks/ui/routing/electrum_settings_router.dart';
import 'package:bb_mobile/features/exchange/public/exchange_facade.dart';
import 'package:bb_mobile/features/mempool_settings/router.dart';
import 'package:bb_mobile/features/fund_exchange/fund_exchange_router.dart';
import 'package:bb_mobile/features/import_coldcard/router.dart';
import 'package:bb_mobile/features/import_mnemonic/router.dart';
import 'package:bb_mobile/features/import_qr_device/router.dart';
import 'package:bb_mobile/features/import_wallet/router.dart';
import 'package:bb_mobile/features/import_watch_only_wallet/import_watch_only_router.dart';
import 'package:bb_mobile/features/ledger/ui/ledger_router.dart';
import 'package:bb_mobile/features/onboarding/ui/onboarding_router.dart';
import 'package:bb_mobile/features/pay/ui/pay_router.dart';
import 'package:bb_mobile/features/psbt_flow/psbt_router.dart';
import 'package:bb_mobile/features/receive/ui/receive_router.dart';
import 'package:bb_mobile/features/recoverbull/router.dart';
import 'package:bb_mobile/features/recoverbull_google_drive/router.dart';
import 'package:bb_mobile/features/replace_by_fee/router.dart';
import 'package:bb_mobile/features/sell/ui/sell_router.dart';
import 'package:bb_mobile/features/send/ui/send_router.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/features/settings/ui/settings_router.dart';
import 'package:bb_mobile/features/sp/ui/sp_router.dart';
import 'package:bb_mobile/features/status_check/router.dart';
import 'package:bb_mobile/features/swap/ui/swap_router.dart';
import 'package:bb_mobile/features/transactions/ui/transactions_router.dart';
import 'package:bb_mobile/features/wallet/ui/wallet_router.dart';
import 'package:bb_mobile/features/wallet/ui/widgets/backup_warning_overlay.dart';
import 'package:bb_mobile/features/wallet/ui/widgets/wallet_home_app_bar.dart';
import 'package:bb_mobile/features/withdraw/ui/withdraw_router.dart';
import 'package:bb_mobile/features/bitcoin_price/presentation/cubit/price_chart_cubit.dart';
import 'package:bb_mobile/features/sp/public/sp_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart'
    show P2pFeature, P2pLocalizations, RobosatsNetwork;
import 'package:sentry_flutter/sentry_flutter.dart';

/// The main router of the app. It is the root of the routing tree and contains
/// all the entry-level routes.
class AppRouter {
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'rootNav');

  static final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: WalletRoute.walletHome.path,
    // Breadcrumbs only — `enableAutoTransactions: false` skips the
    // performance/TTID instrumentation so we stay within the
    // error-reporting scope (consent-gated) rather than perf tracing.
    observers: [SentryNavigatorObserver(enableAutoTransactions: false)],
    redirect: (BuildContext context, GoRouterState state) {
      final path = state.uri.path;
      // P2P shares the superuser + dev-mode gate of SP: closed, its pages do
      // not exist, so nothing of P2P (Tor included) starts.
      if (P2pFeature.isP2pPath(path)) {
        return _isP2pVisible(context.read<SettingsCubit>().state)
            ? null
            : WalletRoute.walletHome.path;
      }
      // Only read the gate providers for SP routes; the decision itself lives
      // in the SP feature's pure `spRedirect` (unit-testable, no widget tree).
      if (!isSpPath(path)) return null;
      final settingsState = context.read<SettingsCubit>().state;
      return spRedirect(
        path,
        isSuperuser: settingsState.isSuperuser ?? false,
        isDevModeEnabled: settingsState.isDevModeEnabled ?? false,
        // The SP feature's own synchronous flag, not the wallet feature's copy:
        // that copy only lands a few turns after setup finishes, which bounced
        // any navigation to an SP route right after create back to setup.
        isSpWalletSetup: locator<SpFacade>().isSetUpNow,
        gateClosedRedirectPath: WalletRoute.walletHome.path,
      );
    },
    routes: [
      ShellRoute(
        notifyRootObserver: true,
        builder: (context, state, child) {
          final location = state.uri.toString();
          final showP2p = context.select(
            (SettingsCubit cubit) => _isP2pVisible(cubit.state),
          );
          final isP2p = P2pFeature.isP2pPath(state.uri.path);
          if (isP2p && !showP2p) {
            // The gate closed while the tab was open: leave it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.goNamed(WalletRoute.walletHome.name);
            });
          }
          final tabs = [
            _ShellTab.wallet,
            if (showP2p) _ShellTab.p2p,
            _ShellTab.exchange,
          ];
          final currentTab =
              location.startsWith(ExchangeRoute.exchangeHome.path)
              ? _ShellTab.exchange
              : isP2p && showP2p
              ? _ShellTab.p2p
              : _ShellTab.wallet;
          final tabIndex = tabs.indexOf(currentTab);
          final isSupportChat =
              location.contains('/support-chat') ||
              location.contains('/login-support');

          return MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => locator<PriceChartCubit>()),
              BlocProvider(
                create: (_) => locator<AnnouncementsCubit>()..refresh(),
              ),
            ],
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                context.goNamed(WalletRoute.walletHome.name);
              },
              child: BackupWarningOverlay(
                child: Scaffold(
                  // The app bar of the exchange tab is rendered by the
                  // ExchangeHomeScreen itself, as an overlay.
                  appBar: currentTab == _ShellTab.wallet
                      ? const WalletHomeAppBar()
                      : null,
                  extendBodyBehindAppBar: true,
                  body: child,
                  bottomNavigationBar: isSupportChat
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BottomNavigationBar(
                              currentIndex: tabIndex,
                              onTap: (index) {
                                if (tabs[index] == _ShellTab.wallet) {
                                  context.goNamed(WalletRoute.walletHome.name);
                                } else if (tabs[index] == _ShellTab.p2p) {
                                  context.go(P2pFeature.path);
                                } else {
                                  // Exchange tab
                                  if (Platform.isIOS) {
                                    final isSuperuser =
                                        context
                                            .read<SettingsCubit>()
                                            .state
                                            .isSuperuser ??
                                        false;
                                    if (isSuperuser) {
                                      context.goNamed(
                                        ExchangeRoute.exchangeHome.name,
                                      );
                                    } else {
                                      context.goNamed(
                                        ExchangeRoute.exchangeLanding.name,
                                      );
                                    }
                                  } else {
                                    context.goNamed(
                                      ExchangeRoute.exchangeHome.name,
                                    );
                                  }
                                }
                              },
                              items: [
                                BottomNavigationBarItem(
                                  icon: const Icon(Icons.currency_bitcoin),
                                  label: context.loc.navigationTabWallet,
                                  backgroundColor: context.appColors.background,
                                ),
                                if (showP2p)
                                  BottomNavigationBarItem(
                                    icon: const Icon(Icons.swap_horiz),
                                    label: P2pLocalizations.of(
                                      context,
                                    ).p2pTabLabel,
                                    backgroundColor:
                                        context.appColors.background,
                                  ),
                                BottomNavigationBarItem(
                                  icon: const Icon(Icons.attach_money),
                                  label: context.loc.navigationTabExchange,
                                  backgroundColor: context.appColors.background,
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
        routes: [
          WalletRouter.walletHomeRoute,
          const P2pFeature().route(
            locator,
            // The book follows the network of the wallet: testnet reads the
            // testnet instances of the coordinators.
            network: (context) =>
                context.select(
                  (SettingsCubit cubit) =>
                      cubit.state.environment?.isTestnet ?? false,
                )
                ? RobosatsNetwork.testnet
                : RobosatsNetwork.mainnet,
          ),
          ...ExchangeRouter.routes(
            ExchangeRouterConfig(
              isSuperuser: (context) =>
                  context.read<SettingsCubit>().state.isSuperuser ?? false,
              homePath: WalletRoute.walletHome.path,
              buildHomeCards: () => [
                locator<LimitOrdersFacade>().buildDashboardCard(),
              ],
              onHomeRefresh: () =>
                  locator<LimitOrdersFacade>().refreshDashboard(),
              onExit: (context) => context.goNamed(WalletRoute.walletHome.name),
              onOpenSettings: (context) =>
                  context.pushNamed(SettingsRoute.settings.name),
            ),
          ),
        ],
      ),
      OnboardingRouter.route,
      AppUnlockRouter.route,
      WalletRouter.walletDetailRoute,
      ConsolidationRouter.route,
      SettingsRouter.route,
      TransactionsRouter.transactionsRoute,
      TransactionsRouter.exportTransactionsRoute,
      ...TransactionsRouter.transactionDetailsRoutes,
      ReceiveRouter.route,
      SendRouter.route,
      CoinsRouter.route,
      SwapRouter.route,
      ...BuyRouter.routes,
      ...FundExchangeRouter.routes,
      SellRouter.route,
      WithdrawRouter.route,
      PayRouter.route,
      ImportMnemonicRouter.route,
      ImportWatchOnlyRouter.route,
      BroadcastSignedTxRouter.route,
      PsbtRouterConfig.route,
      ImportWalletRouter.route,
      ...ImportColdcardRouter.routes,
      ...LedgerRouter.routes,
      ...BitBoxRouter.routes,
      DcaRouter.route,
      AutoBuyRouter.route,
      ...LimitOrdersRouter.routes,
      ReplaceByFeeRouter.route,
      Bip85EntropyRouter.route,
      ElectrumSettingsRouter.route,
      MempoolSettingsRoute.route,
      SpSetupRouter.route(successRedirectPath: WalletRoute.walletHome.path),
      SpRouter.route(
        sendRouteName: SendRoute.send.name,
        sendRouteExtra: const SendRouteArgs.sp(),
        exitRedirectPath: WalletRoute.walletHome.path,
      ),
      ...ImportQrDeviceRouter.routes,
      RecoverBullRouter.route,
      RecoverBullGoogleDriveRouter.route,
      LabelsRouter.route,
      StatusCheckRouter.route,
    ],
    errorBuilder: (context, state) => const RouteErrorScreen(),
  );
}

/// The destinations of the bottom bar.
enum _ShellTab { wallet, p2p, exchange }

/// P2P is shown to superusers in dev mode only, like Silent Payments.
bool _isP2pVisible(SettingsState settings) =>
    (settings.isSuperuser ?? false) && (settings.isDevModeEnabled ?? false);
