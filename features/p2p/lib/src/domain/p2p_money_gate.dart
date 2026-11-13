import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// Whether this build may lock, move or release funds in a trade, by network (design note `docs/design/phase-2-taking-an-order.md`, § 3.7).
///
/// It answers two questions, and each money call of a trade use case asks the one it is.
/// Starting a new trade, that is taking an order, asks [allowsNewTrade].
/// Any action on a trade already recorded on this device (cancelling, paying out, confirming, disputing) asks [allowsActionOnRecordedTrade].
/// Today both say yes on testnet and, on mainnet, only when [mainnetApproved] is true: nothing about a mainnet trade is allowed on a build the owner has not approved.
/// The two questions stay distinct because they will diverge once a trade record carries its origin (#85, #87); [allowsActionOnRecordedTrade] says how.
/// `p2p_money_gate_architecture_test.dart` pins that only the trade use cases call a money member of the coordinator client, each after the question it is has said yes about the network of the call.
abstract final class P2pMoneyGate {
  /// Whether the repository owner has approved real money on mainnet for this build.
  ///
  /// It is `false` in the pull request that added this gate, and it stays `false` on `main` until the repository owner approves real money explicitly.
  /// It is then changed by a pull request whose description quotes his approval and the amounts he accepted, reviewed as money code.
  /// No runtime switch, build flag, environment variable or developer-mode toggle opens it: this line alone says whether a build can lock, move or release funds on mainnet.
  static const bool mainnetApproved = false;

  /// Whether a new trade may start on [network]: always on testnet, and on mainnet only when [mainnetApproved] is true.
  static bool allowsNewTrade(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.testnet => true,
    RobosatsNetwork.mainnet => mainnetApproved,
  };

  /// Whether an action may go on with a trade already recorded on [network]: always on testnet, and on mainnet only when [mainnetApproved] is true, for now.
  ///
  /// A trade can reach the device otherwise than by a take this gate allowed: a pasted key's robot found holding an order, a restored or edited database, a bare order id.
  /// So until a trade record carries its origin, an unapproved build refuses every action on a mainnet trade, as it refuses taking one.
  /// This rule strands no bond only while no approved build has ever existed: until then no mainnet trade can have been taken.
  /// So the pull request that sets [mainnetApproved] to true must not land before #87 has made this question take the trade record.
  /// Otherwise an approval withdrawn later would refuse cancel, dispute and payout on a trade an approved build took.
  /// #85 gives a trade record its origin: `takenHere`, written only by the take use case after [allowsNewTrade] said yes, or `recovered`, written only by an explicit action of the user.
  /// #87 then makes this question take that record, so that a trade this device took under an approved build can still be cancelled, disputed and paid out after the approval is withdrawn.
  /// A recovered mainnet trade on an unapproved build stays refused, and the user is pointed to the official client with the trade's Garage Key.
  static bool allowsActionOnRecordedTrade(RobosatsNetwork network) =>
      switch (network) {
        RobosatsNetwork.testnet => true,
        RobosatsNetwork.mainnet => mainnetApproved,
      };
}
