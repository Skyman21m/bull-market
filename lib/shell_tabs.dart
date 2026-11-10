import 'package:bb_mobile/features/exchange/public/exchange_facade.dart';
import 'package:p2p/p2p.dart' show P2pFeature;

/// The destinations of the bottom bar of the shell.
enum ShellTab { wallet, p2p, exchange }

/// The tabs of the bottom bar, in order: P2P sits between Wallet and Exchange, only when the user may see it.
List<ShellTab> shellTabs({required bool showP2p}) => [
  ShellTab.wallet,
  if (showP2p) ShellTab.p2p,
  ShellTab.exchange,
];

/// The tab that [location] belongs to: a P2P location counts as the wallet while P2P is hidden.
ShellTab shellTabOf(String location, {required bool showP2p}) {
  if (location.startsWith(ExchangeRoute.exchangeHome.path)) {
    return ShellTab.exchange;
  }
  if (showP2p && P2pFeature.isP2pPath(location)) return ShellTab.p2p;
  return ShellTab.wallet;
}

/// Whether the shell must leave [location] for the wallet: the P2P gate closed while the tab was open.
bool mustLeaveP2p(String location, {required bool showP2p}) =>
    !showP2p && P2pFeature.isP2pPath(location);
