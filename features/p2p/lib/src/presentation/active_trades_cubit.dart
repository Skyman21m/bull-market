import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
import '../domain/trade/active_trade.dart';
import '../domain/usecases/trade/list_active_trades_usecase.dart';

/// [ListActiveTradesUsecase.execute], which the locator gives the cubit.
typedef ActiveTradesLister =
    Stream<Result<List<ActiveTrade>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// The active trades of a network, from the device's records only, for the « Order » entry of the P2P tab (#88).
@immutable
sealed class ActiveTradesState {
  const ActiveTradesState();
}

/// The records are being read.
final class ActiveTradesLoading extends ActiveTradesState {
  const ActiveTradesLoading();
}

/// The active trades, newest record last as the repository lists them; empty when there is none.
final class ActiveTradesListed extends ActiveTradesState {
  final List<ActiveTrade> active;

  const ActiveTradesListed(this.active);
}

/// The records cannot be read: never shown as « no trade », since a trade may be running (`ListActiveTradesUsecase`).
final class ActiveTradesUnreadable extends ActiveTradesState {
  const ActiveTradesUnreadable();
}

/// Lists the active trades of [network] while the tab is shown: the only caller of [ListActiveTradesUsecase].
///
/// Nothing is asked of a coordinator: a trade is read only once its screen is opened, which has the only watch of the trade.
class ActiveTradesCubit extends Cubit<ActiveTradesState> {
  final RobosatsNetwork network;
  final ActiveTradesLister _list;
  StreamSubscription<Result<List<ActiveTrade>, P2pFailure>>? _subscription;

  ActiveTradesCubit(this.network, this._list)
    : super(const ActiveTradesLoading());

  /// Starts listing: a new list after each write of the records.
  void start() {
    if (isClosed || _subscription != null) return;
    // An `Error` the list passes on is a bug (rule 11): not caught here.
    _subscription = _list(network).listen((result) {
      if (isClosed) return;
      emit(switch (result) {
        Ok(:final value) => ActiveTradesListed(value),
        Err() => const ActiveTradesUnreadable(),
      });
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
