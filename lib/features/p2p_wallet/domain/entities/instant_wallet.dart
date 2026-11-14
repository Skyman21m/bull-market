import 'package:p2p/p2p.dart';

/// The wallet's Instant Payments wallet (its default Liquid wallet), as the P2P port reads it: no key, no descriptor, no address.
final class InstantWallet {
  /// The wallet's own id, which the wallet's readers take.
  final String id;

  /// What it can spend now: its balance, as the wallet's send screen compares a Lightning payment against on Liquid, where no coin is frozen.
  final Sats balance;

  /// Whether it is a testnet wallet.
  final bool isTestnet;

  /// Whether it signs on this device, with no device of its own: the only way the port could pay from it without a screen.
  final bool signsHere;

  const InstantWallet({
    required this.id,
    required this.balance,
    required this.isTestnet,
    required this.signsHere,
  });

  /// Why the port cannot use this wallet for a trade on [network], or `null` when it can.
  P2pWalletRefusal? refusalFor(RobosatsNetwork network) {
    if (isTestnet != (network == RobosatsNetwork.testnet)) {
      return const P2pWalletWrongNetwork();
    }
    if (!signsHere) return const P2pWalletUnavailable();
    return null;
  }
}
