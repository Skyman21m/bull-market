import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'p2p_money_gate.dart';

/// The money gate's yes to a new trade on one network, as a value: what the record of a trade taken here requires (`TradeRecordRepository.recordPendingTake`).
///
/// [ask] is the only way to get one, and it gives one only when `P2pMoneyGate.allowsNewTrade` says yes for [network]: the class is `final` and its one constructor is private, so no other library can make, extend or implement it.
/// So a record of origin `takenHere` exists only for a network on which this build allowed a new trade.
/// The gate's answer is a constant of the build, so a permit kept for later says nothing the gate would not say again.
/// It is not a guard of a money call: the trade use cases still ask the gate before each call, as `p2p_money_gate_architecture_test.dart` requires.
/// `test/robot_bindings_architecture_test.dart` pins this file as it is.
final class NewTradePermit {
  /// The network the gate said yes for.
  final RobosatsNetwork network;

  const NewTradePermit._(this.network);

  /// A permit for [network] if the money gate allows a new trade there, `null` otherwise.
  static NewTradePermit? ask(RobosatsNetwork network) =>
      P2pMoneyGate.allowsNewTrade(network) ? NewTradePermit._(network) : null;
}
