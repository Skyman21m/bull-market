import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/book_filter.dart';
import '../domain/p2p_tor_state.dart';
import '../domain/tor_wait.dart';
import '../domain/usecases/request_federation_books_usecase.dart';
import '../domain/usecases/retry_p2p_tor_usecase.dart';
import '../domain/usecases/start_p2p_tor_usecase.dart';
import '../domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'book_state.dart';

/// The P2P book: it starts Tor, waits for it, then asks every coordinator for its book and shows each one as it arrives.
class BookCubit extends Cubit<BookState> {
  final WatchP2pTorStateUsecase _watchTor;
  final StartP2pTorUsecase _startTor;
  final RetryP2pTorUsecase _retryTor;
  final RequestFederationBooksUsecase _requestBooks;

  StreamSubscription<P2pTorState>? _torStates;

  /// The number of the latest request to each coordinator: an answer to an older one is dropped.
  final Map<Coordinator, int> _requests = {};
  int _nextRequest = 0;

  BookCubit(
    RobosatsNetwork network,
    this._watchTor,
    this._startTor,
    this._retryTor,
    this._requestBooks,
  ) : super(BookState(network: network));

  /// Follows Tor and starts it: the book is requested once Tor is ready.
  void start() {
    _torStates ??= _watchTor.execute().listen(_onTorState);
    unawaited(_startTor.execute());
  }

  /// Starts Tor again after it failed.
  void retryTor() {
    if (state.tor != TorWait.failed) return;
    emit(state.copyWith(tor: TorWait.initializing));
    unawaited(_retryTor.execute());
  }

  /// Asks every coordinator again, keeping their orders on screen meanwhile; completes when every answer is in.
  Future<void> refresh() => _request(state.coordinators.keys.toSet());

  /// Asks again only the coordinators whose book failed.
  Future<void> retryFailed() => _request(state.failedCoordinators.toSet());

  void selectSide(BookSide side) => _filter(state.filter.withSide(side));

  void selectCurrency(RobosatsCurrency? currency) =>
      _filter(state.filter.withCurrency(currency));

  void selectPaymentMethod(String? method) =>
      _filter(state.filter.withPaymentMethod(method));

  void selectHost(Coordinator? host) => _filter(state.filter.withHost(host));

  void _onTorState(P2pTorState torState) {
    final previous = state.tor;
    final next = previous.after(torState);
    if (next == previous) return;
    emit(state.copyWith(tor: next));
    if (next == TorWait.ready) unawaited(_request(null));
  }

  /// Requests the books of [coordinators], or of every coordinator of the network when `null`.
  Future<void> _request(Set<Coordinator>? coordinators) async {
    if (state.tor != TorWait.ready) return;
    if (coordinators != null && coordinators.isEmpty) return;
    final pending = _requestBooks.execute(state.network, only: coordinators);
    final statuses = {
      ...state.coordinators,
      for (final coordinator in pending.keys)
        coordinator: CoordinatorBookLoading(switch (state
            .coordinators[coordinator]) {
          CoordinatorBookLoaded(:final book) => book,
          CoordinatorBookLoading(:final previous) => previous,
          _ => null,
        }),
    };
    emit(state.copyWith(coordinators: statuses));
    await Future.wait([
      for (final MapEntry(key: coordinator, value: outcome) in pending.entries)
        _await(coordinator, outcome, _requests[coordinator] = _nextRequest++),
    ]);
  }

  Future<void> _await(
    Coordinator coordinator,
    Future<CoordinatorBookOutcome> outcome,
    int id,
  ) async {
    final result = (await outcome).result;
    if (isClosed || _requests[coordinator] != id) return;
    final status = switch (result) {
      Ok(:final value) => CoordinatorBookLoaded(value),
      Err(:final failure) => CoordinatorBookFailed(failure),
    };
    final coordinators = {...state.coordinators, coordinator: status};
    emit(
      state.copyWith(
        coordinators: coordinators,
        orders: state.filter.apply(
          coordinators.values.expand((status) => status.orders),
        ),
      ),
    );
  }

  void _filter(BookFilter filter) {
    if (filter == state.filter) return;
    emit(
      state.copyWith(
        filter: filter,
        orders: filter.apply(state.receivedOrders),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _torStates?.cancel();
    return super.close();
  }
}
