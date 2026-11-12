import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../book_retry.dart';
import '../p2p_waits.dart';
import 'request_federation_books_usecase.dart';

/// The books of the P2P book screen: every coordinator is asked, and one whose request got no answer is asked again by itself, a few times, before the screen shows it offline.
///
/// One instance serves one book, so the locator gives each book its own: it remembers which coordinators gave their book, and which requests are still in flight.
/// The rule of when to ask again is [BookRetry]; this use case runs it with the timers and draws of [P2pWaits].
final class LoadFederationBooksUsecase {
  final RequestFederationBooksUsecase _requestBooks;
  final P2pWaits _waits;

  /// The request in flight to each coordinator: a coordinator is never sent a second one while it runs, as in the official client, whose `loadBook` of a coordinator joins the request in flight (`frontend/src/models/Coordinator.model.ts` at commit ff1998c).
  final Map<Coordinator, Future<CoordinatorBookOutcome>> _inFlight = {};

  /// The coordinators that gave their book to this instance at least once: they are asked again with [BookRetry.reached], the others with [BookRetry.firstContact].
  final Set<Coordinator> _reached = {};

  LoadFederationBooksUsecase(this._requestBooks, this._waits);

  /// Starts the attempts of each coordinator that has an onion address on [network], or only of those of [only], in the order of the federation, every request started without waiting for the others.
  ///
  /// A coordinator whose request is still in flight is not sent another: its first attempt is that request.
  Map<Coordinator, CoordinatorBookAttempts> execute(
    RobosatsNetwork network, {
    Set<Coordinator>? only,
  }) {
    final coordinators = _requestBooks.coordinatorsOn(network, only: only);
    final idle = {
      for (final coordinator in coordinators)
        if (!_inFlight.containsKey(coordinator)) coordinator,
    };
    if (idle.isNotEmpty) {
      _requestBooks
          .execute(network, only: idle)
          .forEach((coordinator, request) => _track(coordinator, request));
    }
    return {
      for (final coordinator in coordinators)
        coordinator: CoordinatorBookAttempts._(coordinator, network, this),
    };
  }

  /// The request in flight to [coordinator], or a new one when there is none.
  Future<CoordinatorBookOutcome> _request(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) {
    final running = _inFlight[coordinator];
    if (running != null) return running;
    final request =
        _requestBooks.execute(network, only: {coordinator})[coordinator] ??
        // Only a coordinator of the network is asked: none other reaches this.
        Future.value(
          CoordinatorBookOutcome(
            coordinator,
            const Err(CoordinatorNotOnNetwork()),
          ),
        );
    return _track(coordinator, request);
  }

  /// Keeps [request] as the one in flight to [coordinator] until it completes.
  Future<CoordinatorBookOutcome> _track(
    Coordinator coordinator,
    Future<CoordinatorBookOutcome> request,
  ) {
    _inFlight[coordinator] = request;
    void forget() {
      if (identical(_inFlight[coordinator], request)) {
        _inFlight.remove(coordinator);
      }
    }

    request.then<void>(
      (outcome) {
        forget();
        if (outcome.result is Ok) _reached.add(coordinator);
      },
      // A request never fails but on a bug, which reaches whoever awaits it: here it is only forgotten.
      onError: (Object _) => forget(),
    );
    return request;
  }
}

/// The attempts to get the book of one coordinator: the first request, then, while it gets no answer, the extra attempts of [BookRetry].
final class CoordinatorBookAttempts {
  final Coordinator coordinator;
  final RobosatsNetwork _network;
  final LoadFederationBooksUsecase _usecase;
  final BookRetry _retry;
  final _outcome = Completer<Result<OrderBook, CoordinatorFailure>?>();

  /// How many requests these attempts have sent or joined so far.
  int _attempts = 0;

  /// The failure of the last attempt, while the wait before the next one runs.
  CoordinatorFailure? _lastFailure;

  /// The wait before the next attempt, while it runs.
  Timer? _wait;

  /// Whether a failure is final from now on.
  bool _stopped = false;

  CoordinatorBookAttempts._(this.coordinator, this._network, this._usecase)
    : _retry = _usecase._reached.contains(coordinator)
          ? BookRetry.reached
          : BookRetry.firstContact {
    _attempt();
  }

  /// The book, or the failure of the last attempt once no other is made, or `null` once [cancel] came first.
  Future<Result<OrderBook, CoordinatorFailure>?> get outcome => _outcome.future;

  /// How many requests these attempts have sent or joined so far, the one in flight included.
  int get attempts => _attempts;

  /// Whether the wait before another attempt is running.
  bool get isWaiting => _wait != null;

  /// Stops at once: no other request is sent, the wait before one ends, and [outcome] completes with `null`.
  ///
  /// A request in flight is not stopped, since the transport cannot take it back; its answer is dropped here, and a later call of [LoadFederationBooksUsecase.execute] joins it.
  void cancel() {
    _wait?.cancel();
    _wait = null;
    if (!_outcome.isCompleted) _outcome.complete(null);
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
          _finish(Ok(value));
        case Err(:final failure):
          final wait = _stopped
              ? null
              : _retry.waitAfter(
                  failure,
                  attempts: attempts,
                  draw: _usecase._waits.random,
                );
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
    if (!_outcome.isCompleted) _outcome.complete(result);
  }
}
