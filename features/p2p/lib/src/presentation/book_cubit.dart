import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/book_filter.dart';
import '../domain/order_search.dart';
import '../domain/p2p_tor_state.dart';
import '../domain/tor_wait.dart';
import '../domain/usecases/load_federation_books_usecase.dart';
import '../domain/usecases/retry_p2p_tor_usecase.dart';
import '../domain/usecases/start_p2p_tor_usecase.dart';
import '../domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'book_state.dart';

/// The P2P book: it starts Tor, waits for it, then asks every coordinator for its book and shows each one as it arrives.
///
/// A coordinator whose request got no answer is asked again by the use case, and stays awaited meanwhile: it is shown offline after its last attempt, or once it has been awaited `BookRetry.awaitedAtMost`, its attempts going on and its book still taken if one of them gets it.
class BookCubit extends Cubit<BookState> {
  final WatchP2pTorStateUsecase _watchTor;
  final StartP2pTorUsecase _startTor;
  final RetryP2pTorUsecase _retryTor;
  final LoadFederationBooksUsecase _loadBooks;

  StreamSubscription<P2pTorReport>? _torStates;

  /// The attempts running for each coordinator: asking a coordinator again cancels the attempts before, whose outcome is then dropped.
  final Map<Coordinator, CoordinatorBookAttempts> _attempts = {};

  BookCubit(
    RobosatsNetwork network,
    this._watchTor,
    this._startTor,
    this._retryTor,
    this._loadBooks,
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

  /// Asks every coordinator again, keeping their orders on screen meanwhile, each with all its attempts; completes once each has given its book or is shown offline, and in any case after `BookRetry.refreshAtMost`, so that the indicator of a pull does not wait for the last coordinator.
  Future<void> refresh() => _request(state.coordinators.keys.toSet());

  /// Asks again, with all their attempts, only the coordinators shown offline; completes as [refresh] does.
  Future<void> retryFailed() => _request(state.failedCoordinators.toSet());

  void selectSide(BookSide side) => _filter(state.filter.withSide(side));

  void selectCurrency(RobosatsCurrency? currency) =>
      _filter(state.filter.withCurrency(currency));

  void selectPaymentMethod(String? method) =>
      _filter(state.filter.withPaymentMethod(method));

  void selectHost(Coordinator? host) => _filter(state.filter.withHost(host));

  /// « Search order »: what an order URL finds among every order received, whatever the filter.
  OrderSearchOutcome searchOrder(String url) =>
      OrderSearch.run(url, state.receivedOrders);

  void _onTorState(P2pTorReport report) {
    final previous = state.tor;
    // Tor failed under the book: no coordinator is asked again until the user does, and those waiting to be are shown offline.
    if (previous == TorWait.ready && report.state == P2pTorState.failed) {
      for (final attempts in _attempts.values) {
        attempts.stopAskingAgain();
      }
    }
    final next = previous.after(report.state);
    final percent = next.percentAfter(report, shown: state.torPercent);
    if (next == previous && percent == state.torPercent) return;
    emit(state.copyWith(tor: next, torPercent: percent));
    if (next == TorWait.ready) unawaited(_request(null));
  }

  /// Requests the books of [coordinators], or of every coordinator of the network when `null`.
  Future<void> _request(Set<Coordinator>? coordinators) async {
    if (state.tor != TorWait.ready) return;
    if (coordinators != null && coordinators.isEmpty) return;
    final started = _loadBooks.execute(state.network, only: coordinators);
    for (final MapEntry(key: coordinator, value: attempts) in started.entries) {
      _attempts[coordinator]?.cancel();
      _attempts[coordinator] = attempts;
    }
    final statuses = {
      ...state.coordinators,
      for (final coordinator in started.keys)
        coordinator: CoordinatorBookLoading(
          switch (state.coordinators[coordinator]) {
            CoordinatorBookLoaded(:final book) => book,
            CoordinatorBookLoading(:final previous) => previous,
            _ => null,
          },
        ),
    };
    emit(state.copyWith(coordinators: statuses));
    for (final MapEntry(key: coordinator, value: attempts) in started.entries) {
      unawaited(_await(coordinator, attempts));
      unawaited(_awaitOverdue(coordinator, attempts));
    }
    await _loadBooks.shown(started.values);
  }

  Future<void> _await(
    Coordinator coordinator,
    CoordinatorBookAttempts attempts,
  ) async {
    final result = await attempts.outcome;
    // `null`: these attempts were cancelled, by a new request of the coordinator or by `close`; and an outcome that a new request overtook before it was handled is dropped too.
    if (result == null ||
        isClosed ||
        !identical(_attempts[coordinator], attempts)) {
      return;
    }
    _attempts.remove(coordinator);
    _show(coordinator, switch (result) {
      Ok(:final value) => CoordinatorBookLoaded(value),
      Err(:final failure) => CoordinatorBookFailed(failure),
    });
  }

  /// Shows offline a coordinator awaited too long; its attempts go on, and [_await] shows its book if one of them gets it.
  Future<void> _awaitOverdue(
    Coordinator coordinator,
    CoordinatorBookAttempts attempts,
  ) async {
    final failure = await attempts.overdue;
    if (failure == null ||
        isClosed ||
        !identical(_attempts[coordinator], attempts)) {
      return;
    }
    _show(coordinator, CoordinatorBookFailed(failure));
  }

  void _show(Coordinator coordinator, CoordinatorBookStatus status) {
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

  /// Leaving the tab ends every wait before asking a coordinator again: nothing more is sent for this book.
  @override
  Future<void> close() async {
    for (final attempts in _attempts.values) {
      attempts.cancel();
    }
    _attempts.clear();
    await _torStates?.cancel();
    return super.close();
  }
}
