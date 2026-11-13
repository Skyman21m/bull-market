import 'dart:async';

import 'package:robosats/robosats.dart';

/// The book requests in flight to each coordinator, for every book of the app: a coordinator is never sent a second book request while one runs, a book of a later visit to the tab included.
///
/// It is the rule of the official client, whose coordinators keep their `_bookPromise` for the whole app, so that a new `loadBook` joins the request in flight (`frontend/src/models/Coordinator.model.ts` at commit ff1998c).
/// There is one for the feature, a lazy singleton of the locator: each entry in the tab builds a new book and a new use case, which share it.
/// A request cannot be taken back from the transport: one that no book awaits any more, its book gone, runs to its end all the same, within the transport's limit of 132 seconds, and is forgotten then; its answer goes to the books that joined it meanwhile, and to no other.
final class BookRequestsInFlight {
  final Map<(RobosatsNetwork, String), Future<CoordinatorBookOutcome>>
  _requests = {};

  /// The request in flight to [coordinator] on [network], or the one [send] starts when there is none.
  ///
  /// The future returned completes when the request ends, and the request is forgotten at that very moment, before anyone is told: a call made after it ended starts a new request, so that no book is handed an answer that came before it asked.
  Future<CoordinatorBookOutcome> join(
    RobosatsNetwork network,
    Coordinator coordinator,
    Future<CoordinatorBookOutcome> Function() send,
  ) {
    final key = (network, coordinator.shortAlias);
    final running = _requests[key];
    if (running != null) return running;
    // Sent before it is recorded: a `send` that throws, which only a bug does, leaves no entry that no answer would ever end.
    final request = send();
    // Synchronous, so that whoever joined is told in the same step as the request is forgotten.
    final ended = Completer<CoordinatorBookOutcome>.sync();
    _requests[key] = ended.future;
    request.then(
      (outcome) {
        _requests.remove(key);
        ended.complete(outcome);
      },
      // A request never fails but on a bug, which reaches whoever awaits it.
      onError: (Object error, StackTrace trace) {
        _requests.remove(key);
        ended.completeError(error, trace);
      },
    );
    return ended.future;
  }

  /// Whether a book request to [coordinator] on [network] is in flight.
  bool isInFlight(RobosatsNetwork network, Coordinator coordinator) =>
      _requests.containsKey((network, coordinator.shortAlias));
}
