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

  test('an action on a recorded trade may always go on on testnet', () {
    expect(
      P2pMoneyGate.allowsActionOnRecordedTrade(RobosatsNetwork.testnet),
      isTrue,
    );
  });

  test(
    'an action on a recorded mainnet trade may go on exactly when the owner approved mainnet',
    () {
      // Until a trade record carries its origin (#85, #87), a trade can reach the device otherwise than by a take the gate allowed: an unapproved build acts on none on mainnet.
      expect(
        P2pMoneyGate.allowsActionOnRecordedTrade(RobosatsNetwork.mainnet),
        P2pMoneyGate.mainnetApproved,
      );
    },
  );

  test('every network has an answer', () {
    // The switches of the gate are exhaustive: a third network would not compile until it is placed.
    expect(RobosatsNetwork.values, [
      RobosatsNetwork.mainnet,
      RobosatsNetwork.testnet,
    ]);
  });
}
