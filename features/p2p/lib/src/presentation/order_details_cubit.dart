import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/taker_estimate.dart';
import '../domain/usecases/fetch_coordinator_info_usecase.dart';

/// The details of a public order: the order read from the book, and the fees its coordinator announces.
@immutable
final class OrderDetailsState {
  final PublicOrder order;

  /// What the coordinator says about itself, `null` until it answers or when it does not.
  final CoordinatorInfo? info;

  /// Whether the coordinator could not be asked for its fees: the order is still shown, without them.
  final bool infoFailed;

  const OrderDetailsState(this.order, {this.info, this.infoFailed = false});

  /// The sats a taker would trade, with the taker fee once it is known.
  TakerEstimate? get estimate =>
      TakerEstimate.of(order, takerFee: info?.takerFee ?? 0);
}

/// Shows one order of the book and asks its coordinator for its fees.
class OrderDetailsCubit extends Cubit<OrderDetailsState> {
  final RobosatsNetwork _network;
  final FetchCoordinatorInfoUsecase _fetchInfo;

  OrderDetailsCubit(PublicOrder order, this._network, this._fetchInfo)
    : super(OrderDetailsState(order));

  Future<void> load() async {
    final result = await _fetchInfo.execute(state.order.coordinator, _network);
    if (isClosed) return;
    emit(switch (result) {
      Ok(:final value) => OrderDetailsState(state.order, info: value),
      Err() => OrderDetailsState(state.order, infoFailed: true),
    });
  }
}
