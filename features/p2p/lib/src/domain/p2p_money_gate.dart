import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// Whether this build may start a trade that locks, moves or releases funds, by network (design note `docs/design/phase-2-taking-an-order.md`, § 3.7).
///
/// It tells two kinds of calls apart, and each money call of a trade use case asks the one it is.
/// Starting a new trade, that is taking an order, asks [allowsNewTrade]: always on testnet, and on mainnet only when [mainnetApproved] is true.
/// Any action on a trade already recorded on this device (cancelling, paying out, confirming, disputing) asks [allowsActionOnRecordedTrade], which is true whatever the approval: an approval withdrawn by an update must never strand a bond locked before it.
/// `p2p_money_gate_architecture_test.dart` pins that every file of the feature that calls a money member of the coordinator client asks it, and that only the trade use cases call them.
abstract final class P2pMoneyGate {
  /// Whether the repository owner has approved real money on mainnet for this build.
  ///
  /// It is `false` in the pull request that added this gate, and it stays `false` on `main` until the repository owner approves real money explicitly.
  /// It is then changed by a pull request whose description quotes his approval and the amounts he accepted, reviewed as money code.
  /// No runtime switch, build flag, environment variable or developer-mode toggle opens it: this line alone says whether a build can start a mainnet trade.
  static const bool mainnetApproved = false;

  /// Whether a new trade may start on [network]: always on testnet, and on mainnet only when [mainnetApproved] is true.
  static bool allowsNewTrade(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.testnet => true,
    RobosatsNetwork.mainnet => mainnetApproved,
  };

  /// Whether an action may go on with a trade already recorded on [network]: always, on both networks, whatever [mainnetApproved] says.
  ///
  /// Cancelling, giving a payout, confirming and disputing act on a bond or an escrow already locked, and refusing them would leave it to the coordinator's timers.
  /// The network is asked so that each call names the trade's network as [allowsNewTrade] does; the answer does not depend on it.
  static bool allowsActionOnRecordedTrade(RobosatsNetwork network) => true;
}
