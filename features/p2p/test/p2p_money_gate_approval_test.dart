import 'package:p2p/src/domain/p2p_money_gate.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

// The one test meant to be changed on purpose, once: by the pull request that records the repository owner's approval of real money on mainnet.
// Until then it fails the day `P2pMoneyGate.mainnetApproved` is switched on by any other change.
void main() {
  const howToChangeIt =
      'P2pMoneyGate.mainnetApproved was switched on. '
      'It may change only in a pull request whose description quotes the repository owner\'s explicit approval of real money on mainnet and the amounts he accepted, reviewed as money code; '
      'that pull request changes this test in the same commit as the constant.';

  test(
    'nothing about a mainnet trade is allowed: the owner has not approved real money',
    () {
      expect(P2pMoneyGate.mainnetApproved, isFalse, reason: howToChangeIt);
      expect(
        P2pMoneyGate.allowsNewTrade(RobosatsNetwork.mainnet),
        isFalse,
        reason: howToChangeIt,
      );
      expect(
        P2pMoneyGate.allowsActionOnRecordedTrade(RobosatsNetwork.mainnet),
        isFalse,
        reason: howToChangeIt,
      );
    },
  );
}
