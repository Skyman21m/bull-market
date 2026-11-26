import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../order_history.dart';
import '../../p2p_failure.dart';
import '../../repositories/trade_record_repository.dart';

/// The history of finished orders of every Garage Key of one network (since #81, each line saying its key), for « See history » in the Garage (#253, design note `docs/design/phase-3-order-history.md`): read from the device only, nothing sent, nothing written.
///
/// An addition of Bull Market: the reference keeps one « Last order #N » per robot (`basic/GaragePage/GarageKeyProfile.tsx`, commit babf62e) and no history.
final class ListOrderHistoryUsecase {
  final TradeRecordRepository _records;

  const ListOrderHistoryUsecase(this._records);

  /// The finished orders of every key on [network], the newest end first ([OrderHistory.of]): a new list after each write of the records or of the trails; a database that cannot be read gives a [P2pStorageFailure] in place of the list, never an empty one.
  Stream<Result<List<FinishedOrder>, P2pFailure>> execute(
    RobosatsNetwork network,
  ) => _records
      .watchClosedTrades(network)
      .map(
        (result) => switch (result) {
          Ok(:final value) => Ok(OrderHistory.of(value)),
          Err(:final failure) => Err(failure),
        },
      );
}
