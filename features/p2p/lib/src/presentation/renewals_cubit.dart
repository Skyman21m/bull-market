import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../domain/p2p_failure.dart';
import '../domain/trade/trade_renewal.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/make_order_usecase.dart';

/// [MakeOrderUsecase.renewalsOf], which the locator gives the cubit.
typedef RenewalsLister =
    Stream<Result<OrderRenewals, P2pFailure>> Function(TradeRecord record);

/// What the records say of the order of a trade made here once it ended (#216, #217): the terms kept of it, and the orders made here since with those very terms.
@immutable
sealed class RenewalsState {
  const RenewalsState();
}

/// The records are being read: whether the order was renewed is not known yet.
final class RenewalsReading extends RenewalsState {
  const RenewalsReading();
}

/// The terms kept of the order, and the orders made here since with them.
final class RenewalsListed extends RenewalsState {
  final OrderRenewals renewals;

  const RenewalsListed(this.renewals);
}

/// The records, or the terms kept of the order, cannot be read: whether it was renewed is not known, which the screen says, never « not renewed ».
final class RenewalsUnknown extends RenewalsState {
  const RenewalsUnknown();
}

/// The renewals of the order of [record] while its trade screen is shown: the only caller of [MakeOrderUsecase.renewalsOf]. Nothing is asked of a coordinator.
class RenewalsCubit extends Cubit<RenewalsState> {
  final TradeRecord record;
  final RenewalsLister _list;
  StreamSubscription<Result<OrderRenewals, P2pFailure>>? _subscription;

  RenewalsCubit(this.record, this._list) : super(const RenewalsReading());

  /// Starts listing: a new list after each write of the records or the terms.
  void start() {
    if (isClosed || _subscription != null) return;
    // An `Error` the list passes on is a bug (rule 11): not caught here.
    _subscription = _list(record).listen((result) {
      if (isClosed) return;
      emit(switch (result) {
        Ok(:final value) => RenewalsListed(value),
        Err() => const RenewalsUnknown(),
      });
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
