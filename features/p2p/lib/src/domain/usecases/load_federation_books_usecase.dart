import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../book_requests_in_flight.dart';
import '../book_retry.dart';
import '../p2p_waits.dart';
import 'request_federation_books_usecase.dart';

/// The books of the P2P book screen: every coordinator is asked, and one whose request got no answer is asked again by itself, a few times, before the screen shows it offline.
///
/// One instance serves one book, so the locator gives each book its own: it remembers which coordinators gave their book to it.
/// The requests in flight are those of [BookRequestsInFlight], shared by every book of the app, so that no coordinator is sent a second book request while one runs.
/// The rule of when to ask again is [BookRetry]; this use case runs it with the timers and draws of [P2pWaits].
final class LoadFederationBooksUsecase {
  final RequestFederationBooksUsecase _requestBooks;
  final BookRequestsInFlight _inFlight;
  final P2pWaits _waits;

  /// The coordinators that gave their book to this instance at least once: they are asked again with [BookRetry.reached], the others with [BookRetry.firstContact].
  final Set<Coordinator> _reached = {};

  LoadFederationBooksUsecase(this._requestBooks, this._inFlight, this._waits);

  /// Starts the attempts of each coordinator that has an onion address on [network], or only of those of [only], in the order of the federation, every request started without waiting for the others.
  ///
  /// A coordinator whose request is still in flight, sent by this book or by an earlier one, is not sent another: its first attempt is that request.
  Map<Coordinator, CoordinatorBookAttempts> execute(
    RobosatsNetwork network, {
    Set<Coordinator>? only,
  }) => {
    for (final coordinator in _requestBooks.coordinatorsOn(network, only: only))
      coordinator: CoordinatorBookAttempts._(coordinator, network, this),
  };

  /// Completes once each of [attempts] has given its outcome, is shown offline or was cancelled, and in any case [BookRetry.refreshAtMost] after this call: what the indicator of a refresh waits for, while the row shows the rest.
  Future<void> shown(Iterable<CoordinatorBookAttempts> attempts) {
    final done = Completer<void>();
    final bound = _waits.start(BookRetry.refreshAtMost, () {
      if (!done.isCompleted) done.complete();
    });
    Future.wait([for (final attempt in attempts) attempt.shown]).then((_) {
      bound.cancel();
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// The request in flight to [coordinator], or a new one when there is none.
  Future<CoordinatorBookOutcome> _request(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) => _inFlight.join(
    network,
    coordinator,
    () =>
        _requestBooks.execute(network, only: {coordinator})[coordinator] ??
        // Only a coordinator of the network is asked: none other reaches this.
        Future.value(
          CoordinatorBookOutcome(
            coordinator,
            const Err(CoordinatorNotOnNetwork()),
          ),
        ),
  );
}

/// The attempts to get the book of one coordinator: the first request, then, while it gets no answer, the extra attempts of [BookRetry].
final class CoordinatorBookAttempts {
  final Coordinator coordinator;
  final RobosatsNetwork _network;
  final LoadFederationBooksUsecase _usecase;
  final BookRetry _retry;
  final _outcome = Completer<Result<OrderBook, CoordinatorFailure>?>();
  final _overdue = Completer<CoordinatorFailure?>();
  final _shown = Completer<void>();

  /// How many requests these attempts have sent or joined so far.
  int _attempts = 0;

  /// The failure of the last attempt, while the wait before the next one runs.
  CoordinatorFailure? _lastFailure;

  /// The failure of the latest attempt that failed, kept while the next one runs.
  CoordinatorFailure? _latestFailure;

  /// The time a coordinator is shown awaited at most, from these attempts' start: [BookRetry.awaitedAtMost].
  late final Timer _bound;

  /// The wait before the next attempt, while it runs.
  Timer? _wait;

  /// Whether a failure is final from now on.
  bool _stopped = false;

  CoordinatorBookAttempts._(this.coordinator, this._network, this._usecase)
    : _retry = _usecase._reached.contains(coordinator)
          ? BookRetry.reached
          : BookRetry.firstContact {
    _bound = _usecase._waits.start(BookRetry.awaitedAtMost, _showOffline);
    _attempt();
  }

  /// The book, or the failure of the last attempt once no other is made, or `null` once [cancel] came first.
  Future<Result<OrderBook, CoordinatorFailure>?> get outcome => _outcome.future;

  /// How many requests these attempts have sent or joined so far, the one in flight included.
  int get attempts => _attempts;

  /// Whether the wait before another attempt is running.
  bool get isWaiting => _wait != null;

  /// The failure to show once [BookRetry.awaitedAtMost] has passed without an outcome: the coordinator is shown offline then, while its attempts go on, and an answer they get later still gives its book through [outcome].
  ///
  /// It is the failure of the latest attempt that failed, or [CoordinatorTimedOut] while the first one is still in flight; `null` when the outcome came first or [cancel] was called.
  Future<CoordinatorFailure?> get overdue => _overdue.future;

  /// Completes once the coordinator is no longer shown awaited, its outcome given or it shown offline, or once these attempts were cancelled.
  ///
  /// It completes after [outcome] or [overdue] has its value, so that whoever waits for those has handled it first.
  Future<void> get shown => _shown.future;

  /// Stops at once: no other request is sent, the wait before one ends, and [outcome] and [overdue] complete with `null`.
  ///
  /// A request in flight is not stopped, since the transport cannot take it back: its answer is dropped here, the request stays in flight for any book that joins it, this book's next call or a book of a later visit to the tab, and it ends within the transport's limit of 132 seconds whether or not one does ([BookRequestsInFlight]).
  void cancel() {
    _wait?.cancel();
    _wait = null;
    _bound.cancel();
    if (!_outcome.isCompleted) _outcome.complete(null);
    if (!_overdue.isCompleted) _overdue.complete(null);
    if (!_shown.isCompleted) _shown.complete();
  }

  /// Sends no other request: a wait before one ends at once with the failure that led to it, and a request in flight gives the outcome, whatever it is.
  void stopAskingAgain() {
    _stopped = true;
    final wait = _wait;
    final failure = _lastFailure;
    if (wait == null || failure == null) return;
    wait.cancel();
    _wait = null;
    _finish(Err(failure));
  }

  void _attempt() {
    _wait = null;
    _lastFailure = null;
    final attempts = ++_attempts;
    _usecase._request(coordinator, _network).then((outcome) {
      if (_outcome.isCompleted) return;
      switch (outcome.result) {
        case Ok(:final value):
          _usecase._reached.add(coordinator);
          _finish(Ok(value));
        case Err(:final failure):
          final wait = _stopped
              ? null
              : _retry.waitAfter(
                  failure,
                  attempts: attempts,
                  draw: _usecase._waits.random,
                );
          _latestFailure = failure;
          if (wait == null) {
            _finish(Err(failure));
          } else {
            _lastFailure = failure;
            _wait = _usecase._waits.start(wait, _attempt);
          }
      }
    });
  }

  void _finish(Result<OrderBook, CoordinatorFailure> result) {
    _bound.cancel();
    if (!_outcome.isCompleted) _outcome.complete(result);
    if (!_overdue.isCompleted) _overdue.complete(null);
    if (!_shown.isCompleted) _shown.complete();
  }

  void _showOffline() {
    if (_outcome.isCompleted || _overdue.isCompleted) return;
    _overdue.complete(_latestFailure ?? const CoordinatorTimedOut());
    if (!_shown.isCompleted) _shown.complete();
  }
}
