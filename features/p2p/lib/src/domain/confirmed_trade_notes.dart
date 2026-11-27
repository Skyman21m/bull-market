import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'garage_key_fingerprint.dart';
import 'order_history.dart' show ClosedTrade;
import 'p2p_failure.dart';
import 'repositories/trade_record_repository.dart';
import 'robot_binding.dart';
import 'trade_record.dart';

/// The trade records, told to [_confirmed] each time a make or a take is confirmed (#81): the one moment the recovery note of the trade's key is written after a trade, once the coordinator confirmed it, never before, so that a take refused or never sent writes nothing (design note `docs/design/garage-key-from-the-words.md` § 3, « This design »).
///
/// Every call goes to the records as it is, and gives what they give; only the two confirmations are watched: `confirmMake` (a make the coordinator answered and that its robot reads as the maker's, `MakeOrderUsecase`) and `confirmTake` (a take whose order reads its robot as the taker, `TradeReader`), when they confirm a record that was not confirmed before.
final class ConfirmedTradeNotes implements TradeRecordRepository {
  final TradeRecordRepository _records;
  final void Function(TradeRecord record) _confirmed;

  const ConfirmedTradeNotes(this._records, this._confirmed);

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmMake(
    PendingMake make, {
    required int orderId,
  }) async {
    final confirmed = await _records.confirmMake(make, orderId: orderId);
    if (confirmed case Ok(:final value) when value.confirmedAt != null) {
      _confirmed(value);
    }
    return confirmed;
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmTake(
    TradeRecord record,
  ) async {
    final confirmed = await _records.confirmTake(record);
    if (confirmed case Ok(:final value)
        when record.confirmedAt == null && value.confirmedAt != null) {
      _confirmed(value);
    }
    return confirmed;
  }

  @override
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _records.newTradeStandingOf(network, key);

  @override
  Future<Result<Set<GarageKeyFingerprint>, P2pFailure>> keysInUse(
    RobosatsNetwork network,
  ) => _records.keysInUse(network);

  @override
  Future<Result<TradeReservation?, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) => _records.reserveForNewTrade(robot, coordinator);

  @override
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    TradeReservation reservation, {
    required int orderId,
    required TradeRole role,
  }) => _records.recordPendingTake(reservation, orderId: orderId, role: role);

  @override
  Future<Result<PendingMake, P2pFailure>> recordPendingMake(
    TradeReservation reservation, {
    required TradeRole role,
  }) => _records.recordPendingMake(reservation, role: role);

  @override
  Future<Result<PendingMake, P2pFailure>> closePendingMake(PendingMake make) =>
      _records.closePendingMake(make);

  @override
  Stream<Result<List<PendingMake>, P2pFailure>> watchPendingMakes(
    RobosatsNetwork network,
  ) => _records.watchPendingMakes(network);

  @override
  Future<Result<TradeRecord, P2pFailure>> recordRecoveredTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required int orderId,
    required TradeRole role,
  }) => _records.recordRecoveredTrade(
    robot,
    coordinator,
    orderId: orderId,
    role: role,
  );

  @override
  Future<Result<TradeRecord, P2pFailure>> closeTrade(TradeRecord record) =>
      _records.closeTrade(record);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchActiveTrades(
    RobosatsNetwork network,
  ) => _records.watchActiveTrades(network);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchTrades(
    RobosatsNetwork network,
  ) => _records.watchTrades(network);

  @override
  Stream<Result<List<ClosedTrade>, P2pFailure>> watchClosedTrades(
    RobosatsNetwork network,
  ) => _records.watchClosedTrades(network);
}
