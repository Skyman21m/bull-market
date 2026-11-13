import 'package:p2p/src/domain/p2p_money_gate.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

// The behaviour of the gate on both networks; whether the owner approved mainnet is pinned in `p2p_money_gate_approval_test.dart`.
void main() {
  test('a new trade may always start on testnet', () {
    expect(P2pMoneyGate.allowsNewTrade(RobosatsNetwork.testnet), isTrue);
  });

  test(
    'a new trade may start on mainnet exactly when the owner approved it',
    () {
      expect(
        P2pMoneyGate.allowsNewTrade(RobosatsNetwork.mainnet),
        P2pMoneyGate.mainnetApproved,
      );
    },
  );

  test(
    'an action on a recorded trade goes on, on both networks, whatever the approval',
    () {
      // A bond locked before an update that withdrew the approval must not be left to the coordinator's timers.
      for (final network in RobosatsNetwork.values) {
        expect(
          P2pMoneyGate.allowsActionOnRecordedTrade(network),
          isTrue,
          reason: network.name,
        );
      }
    },
  );

  test('every network has an answer', () {
    // The switch of `allowsNewTrade` is exhaustive: a third network would not compile until it is placed.
    expect(RobosatsNetwork.values, [
      RobosatsNetwork.mainnet,
      RobosatsNetwork.testnet,
    ]);
  });
}
