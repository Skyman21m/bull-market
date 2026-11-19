import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../p2p_failure.dart';
import '../../repositories/trade_record_repository.dart';
import '../../trade_record.dart';

/// The last finished orders of a network, for « Last order #N » in the Garage (#216): read from the device only, nothing sent.
///
/// The reference keeps « Last order #N » on the robot's profile of its Garage, which opens the order again (`basic/GaragePage/GarageKeyProfile.tsx:214-230`, `basic/RobotPage/RobotProfile.tsx:206-220`, commit ff1998c), so that an order that expired can still be renewed. Its robot is the one shown; here each trade has a robot of its own, so the order is found in the records instead: the last finished order made here, and the last finished trade taken here, each a record closed after its order was confirmed (a take that never happened is none), the newest end first.
final class ListLastOrdersUsecase {
  final TradeRecordRepository _records;

  const ListLastOrdersUsecase(this._records);

  /// A new list after each write of the records; a database that cannot be read gives a [P2pStorageFailure] in place of the list, never an empty one.
  Stream<Result<List<TradeRecord>, P2pFailure>> execute(
    RobosatsNetwork network,
  ) => _records
      .watchTrades(network)
      .map(
        (result) => switch (result) {
          Ok(:final value) => Ok(lastOrdersOf(value)),
          Err(:final failure) => Err(failure),
        },
      );

  /// Of [records], the last finished order made here and the last finished trade taken here, the newest end first; a trade recovered from a pasted key is neither (it was taken over here, not made or taken here).
  static List<TradeRecord> lastOrdersOf(List<TradeRecord> records) {
    TradeRecord? made;
    TradeRecord? taken;
    bool later(TradeRecord record, TradeRecord? than) {
      final end = record.closedAt;
      final thanEnd = than?.closedAt;
      return end != null && (thanEnd == null || !end.isBefore(thanEnd));
    }

    for (final record in records) {
      if (record.closedAt == null || record.confirmedAt == null) continue;
      switch (record.origin) {
        case TradeOrigin.madeHere when later(record, made):
          made = record;
        case TradeOrigin.takenHere when later(record, taken):
          taken = record;
        case TradeOrigin.madeHere ||
            TradeOrigin.takenHere ||
            TradeOrigin.recovered:
          break;
      }
    }
    // The trade taken first only when it ended strictly later.
    if ((made?.closedAt, taken?.closedAt) case (
      final madeEnd?,
      final takenEnd?,
    ) when takenEnd.isAfter(madeEnd)) {
      return List.unmodifiable([?taken, ?made]);
    }
    return List.unmodifiable([?made, ?taken]);
  }
}
