import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/list_last_orders_usecase.dart';

/// [ListLastOrdersUsecase.execute], which the locator gives the cubit.
typedef LastOrdersLister =
    Stream<Result<List<TradeRecord>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// The last finished orders of a network, from the device's records only, for « Last order #N » in the Garage (#216).
@immutable
sealed class LastOrdersState {
  const LastOrdersState();
}

/// The records are being read: nothing is shown yet.
final class LastOrdersLoading extends LastOrdersState {
  const LastOrdersLoading();
}

/// The last finished order made here and the last finished trade taken here, the newest end first; empty when there is none.
final class LastOrdersListed extends LastOrdersState {
  final List<TradeRecord> orders;

  const LastOrdersListed(this.orders);
}

/// The records cannot be read: said, never shown as « no order ».
final class LastOrdersUnreadable extends LastOrdersState {
  const LastOrdersUnreadable();
}

/// Lists the last finished orders of [network] while the Garage is shown, for the « Last order #N » lines; the Garage's `FollowMadeOrdersUsecase` reads the same use case once, for the robot it opens on (#227). Nothing is asked of a coordinator.
class LastOrdersCubit extends Cubit<LastOrdersState> {
  final RobosatsNetwork network;
  final LastOrdersLister _list;
  StreamSubscription<Result<List<TradeRecord>, P2pFailure>>? _subscription;

  LastOrdersCubit(this.network, this._list) : super(const LastOrdersLoading());

  /// Starts listing: a new list after each write of the records.
  void start() {
    if (isClosed || _subscription != null) return;
    // An `Error` the list passes on is a bug (rule 11): not caught here.
    _subscription = _list(network).listen((result) {
      if (isClosed) return;
      emit(switch (result) {
        Ok(:final value) => LastOrdersListed(value),
        Err() => const LastOrdersUnreadable(),
      });
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
