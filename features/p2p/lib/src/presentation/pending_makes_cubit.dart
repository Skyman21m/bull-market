import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/p2p_failure.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_make.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/make_order_usecase.dart';
import 'make_order_cubit.dart';

/// [MakeOrderUsecase.pendingMakes], which the locator gives the cubit.
typedef PendingMakesLister =
    Stream<Result<List<ActivePendingMake>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// [MakeOrderUsecase.resolve], which the locator gives the cubit.
typedef PendingMakeResolver = Future<MakeOutcome> Function(PendingMake make);

/// [MakeOrderUsecase.dismiss], which the locator gives the cubit.
typedef PendingMakeDismisser =
    Future<Result<bool, P2pFailure>> Function(PendingMake make);

/// Where the resolution of one pending make stands, on this screen.
@immutable
sealed class PendingMakeStep {
  const PendingMakeStep();
}

/// Its resolution runs: « Checking with {coordinator}… ».
final class PendingMakeChecking extends PendingMakeStep {
  const PendingMakeChecking();
}

/// Its last resolution left it pending ([reason]): whether it made an order is not known, and no bond is shown for it.
final class PendingMakeLeftPending extends PendingMakeStep {
  final MakePendingReason reason;

  const PendingMakeLeftPending(this.reason);
}

/// « Set aside » could not be written: it stays pending.
final class PendingMakeNotSetAside extends PendingMakeStep {
  const PendingMakeNotSetAside();
}

/// The pending makes of a network (#182, design note § 3.4, « The screens of a pending make »): their lines in « Active trades » and above the create form, each resolved by its robot's read ([MakeOrderUsecase.resolve]) when the list or the form opens, when the app comes back while it is shown, and on « Retry », never in a loop; set aside on the user's request ([MakeOrderUsecase.dismiss]), never made again.
@immutable
final class PendingMakesState {
  /// The pending makes, oldest first; `null` until the records are read, or when they cannot be ([unreadable]).
  final List<ActivePendingMake>? makes;
  final bool unreadable;

  /// What this screen did with each make, by its robot.
  final Map<RobotSlot, PendingMakeStep> steps;

  /// The trade a resolution confirmed, which the screen opens: set once per confirmation.
  final TradeRecord? started;

  /// Why the last make closed by a resolution made no order, said once its line is gone; `null` when none was closed here, or once the form sent a new make ([PendingMakesCubit.forgetClosed]).
  final MakeProblem? closed;

  /// The coordinator of [closed], its short alias.
  final String? closedAlias;

  /// The robot of the last make that this screen saw end without an order: closed by a resolution as not made, or set aside by the user (#220, security review N1); `null` while none did.
  final RobotSlot? ended;

  const PendingMakesState({
    this.makes,
    this.unreadable = false,
    this.steps = const {},
    this.started,
    this.closed,
    this.closedAlias,
    this.ended,
  });

  /// Whether a pending make is listed, or the records cannot tell: the create form makes nothing then.
  bool get blocksMaking => unreadable || (makes?.isNotEmpty ?? true);

  PendingMakesState _with({
    List<ActivePendingMake>? makes,
    bool? unreadable,
    Map<RobotSlot, PendingMakeStep>? steps,
    TradeRecord? started,
    MakeProblem? closed,
    String? closedAlias,
    RobotSlot? ended,
  }) => PendingMakesState(
    makes: makes ?? this.makes,
    unreadable: unreadable ?? this.unreadable,
    steps: steps ?? this.steps,
    started: started ?? this.started,
    closed: closed ?? this.closed,
    closedAlias: closedAlias ?? this.closedAlias,
    ended: ended ?? this.ended,
  );
}

/// Lists, resolves and sets aside the pending makes of [network]: the only caller of [MakeOrderUsecase.pendingMakes], [MakeOrderUsecase.resolve] and [MakeOrderUsecase.dismiss].
class PendingMakesCubit extends Cubit<PendingMakesState> {
  final RobosatsNetwork network;
  final PendingMakesLister _list;
  final PendingMakeResolver _resolve;
  final PendingMakeDismisser _dismiss;
  StreamSubscription<Result<List<ActivePendingMake>, P2pFailure>>?
  _subscription;

  /// Whether [resolveAll] was asked before the records listed the makes.
  bool _resolveWhenListed = false;

  PendingMakesCubit(this.network, this._list, this._resolve, this._dismiss)
    : super(const PendingMakesState());

  /// Starts listing: a new list after each write of the records.
  void start() {
    if (isClosed || _subscription != null) return;
    _subscription = _list(network).listen((result) {
      if (isClosed) return;
      switch (result) {
        case Ok(:final value):
          final robots = {for (final make in value) make.make.robot};
          emit(
            state._with(
              makes: value,
              unreadable: false,
              steps: {
                for (final MapEntry(:key, :value) in state.steps.entries)
                  if (robots.contains(key)) key: value,
              },
            ),
          );
          if (_resolveWhenListed) {
            _resolveWhenListed = false;
            unawaited(resolveAll());
          }
        case Err():
          emit(state._with(unreadable: true));
      }
    });
  }

  /// Resolves every listed make once, one after the other (the use case holds one per network at a time): when the list or the form opens, and when the app comes back while one of them is shown.
  Future<void> resolveAll() async {
    final makes = state.makes;
    if (makes == null) {
      // The records have not answered yet: resolved once they list the makes.
      _resolveWhenListed = true;
      return;
    }
    for (final make in makes) {
      if (isClosed) return;
      await resolve(make.make);
    }
  }

  /// Resolves [make] once: a second call while it runs does nothing.
  Future<void> resolve(PendingMake make) async {
    if (isClosed || state.steps[make.robot] is PendingMakeChecking) return;
    _step(make, const PendingMakeChecking());
    final outcome = await _resolve(make);
    if (isClosed) return;
    switch (outcome) {
      case MakeStarted(:final record):
        _step(make, null);
        emit(state._with(started: record));
      case MakeNotMade(:final refusal, closeProblem: null):
        _step(make, null);
        emit(
          state._with(
            closed: MakeWasNotMade(refusal),
            closedAlias: make.coordinatorAlias,
            ended: make.robot,
          ),
        );
      case MakeNeverSent(closed: true):
        _step(make, null);
        emit(
          state._with(
            closed: const MakeWasNotMade(null),
            closedAlias: make.coordinatorAlias,
            ended: make.robot,
          ),
        );
      // The close could not be written: it stays listed, and the next resolution closes it.
      case MakeNotMade() || MakeNeverSent():
        _step(make, const PendingMakeLeftPending(MakePendingReason.unread));
      case MakeNoLongerPending():
        _step(make, null);
      case MakePending(:final reason):
        _step(make, PendingMakeLeftPending(reason));
    }
  }

  /// Sets [make] aside, once the user confirmed it: the records close it, nothing is sent, nothing is made again.
  Future<void> dismiss(PendingMake make) async {
    if (isClosed || state.steps[make.robot] is PendingMakeChecking) return;
    final result = await _dismiss(make);
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        _step(make, null);
        if (value) emit(state._with(ended: make.robot));
      case Err():
        _step(make, const PendingMakeNotSetAside());
    }
  }

  /// The form sends a new make: why the last make closed made no order ([PendingMakesState.closed]) is no longer said, so that it is never read as the new make's outcome (seen in a real trial). Nothing else changes: the pending makes, their steps, [PendingMakesState.started] and [PendingMakesState.ended] stay.
  void forgetClosed() {
    if (isClosed || state.closed == null) return;
    emit(
      PendingMakesState(
        makes: state.makes,
        unreadable: state.unreadable,
        steps: state.steps,
        started: state.started,
        ended: state.ended,
      ),
    );
  }

  void _step(PendingMake make, PendingMakeStep? step) => emit(
    state._with(
      steps: {
        for (final MapEntry(:key, :value) in state.steps.entries)
          if (key != make.robot) key: value,
        make.robot: ?step,
      },
    ),
  );

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
