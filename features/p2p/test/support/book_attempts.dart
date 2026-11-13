import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/book_retry.dart';
import 'package:p2p/src/domain/p2p_waits.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'fakes.dart';

/// The timers and the draw of the book's waits, which the test fires and sets itself.
///
/// The waits before an attempt are told from the two bounds by their duration, which no spread wait can have: [BookRetry.awaitedAtMost] (75 s) and [BookRetry.refreshAtMost] (10 s).
final class FakeWaits {
  /// Every timer started, in order, fired or cancelled ones included, the bounds included.
  final List<FakeTimer> all = [];

  /// The draw from 0 to 1 that spreads each wait: the middle, which spreads none, unless the test sets another.
  double draw = 0.5;

  /// How many draws were made.
  int draws = 0;

  late final P2pWaits waits = P2pWaits(
    start: (duration, callback) {
      final timer = FakeTimer(duration, callback);
      all.add(timer);
      return timer;
    },
    random: () {
      draws++;
      return draw;
    },
  );

  static bool _isBound(FakeTimer timer) =>
      timer.duration == BookRetry.awaitedAtMost ||
      timer.duration == BookRetry.refreshAtMost;

  /// The waits before an attempt started, in order, fired or cancelled ones included.
  List<FakeTimer> get started => [
    for (final timer in all)
      if (!_isBound(timer)) timer,
  ];

  /// The waits before an attempt still running, in the order they were started.
  List<FakeTimer> get pending => [
    for (final timer in started)
      if (timer.isActive) timer,
  ];

  /// The bounds of [BookRetry.awaitedAtMost] still running, one per coordinator asked.
  List<FakeTimer> get awaitedBounds => [
    for (final timer in all)
      if (timer.isActive && timer.duration == BookRetry.awaitedAtMost) timer,
  ];

  /// The bounds of [BookRetry.refreshAtMost] still running, one per refresh.
  List<FakeTimer> get refreshBounds => [
    for (final timer in all)
      if (timer.isActive && timer.duration == BookRetry.refreshAtMost) timer,
  ];

  /// Every timer still running, waits and bounds.
  List<FakeTimer> get running => [
    for (final timer in all)
      if (timer.isActive) timer,
  ];

  /// Fires every wait before an attempt still running, not the bounds.
  void fireAll() {
    for (final timer in pending) {
      timer.fire();
    }
  }

  /// Lets [BookRetry.awaitedAtMost] pass for every coordinator asked so far.
  void fireAwaitedBounds() {
    for (final timer in awaitedBounds) {
      timer.fire();
    }
  }

  /// Lets [BookRetry.refreshAtMost] pass for every refresh so far.
  void fireRefreshBounds() {
    for (final timer in refreshBounds) {
      timer.fire();
    }
  }
}

/// A timer that runs its callback only when the test fires it.
final class FakeTimer implements Timer {
  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  /// Whether it was cancelled before it fired.
  bool cancelled = false;

  FakeTimer(this.duration, this._callback);

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() {
    if (_active) cancelled = true;
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

/// What one request to a coordinator gets from [ScriptedTransport].
sealed class Scripted {
  const Scripted();
}

/// The book the test gave for the coordinator, or an empty one.
final class ScriptedBook extends Scripted {
  const ScriptedBook();
}

/// A failure of the transport: nothing was answered.
final class ScriptedFailure extends Scripted {
  final CoordinatorTransportFailure failure;

  const ScriptedFailure(this.failure);
}

/// An answer the coordinator sent, but not a book: the status and content type given, with a body that is not one.
final class ScriptedUnusable extends Scripted {
  final int status;
  final String contentType;

  const ScriptedUnusable({
    this.status = 200,
    this.contentType = 'application/json',
  });
}

/// A transport that answers each request to a coordinator, by short alias, with the next entry of its script, then with its book once the script is used up, and that counts the requests to each coordinator at once.
final class ScriptedTransport implements CoordinatorTransport {
  final RobosatsNetwork network;
  final Map<String, List<Scripted>> script;
  final Map<String, List<Map<String, Object?>>> books;

  /// Coordinators whose requests wait until [release].
  final Set<String> held;
  final Map<String, Completer<void>> _releases = {};

  /// Every request, as `alias/path`, in the order sent.
  final List<String> requested = [];
  final Map<String, int> _inFlight = {};

  /// The most requests in flight at once to each coordinator.
  final Map<String, int> mostAtOnce = {};

  ScriptedTransport({
    this.network = RobosatsNetwork.mainnet,
    Map<String, List<Scripted>>? script,
    Map<String, List<Map<String, Object?>>>? books,
    Set<String>? held,
  }) : script = script ?? {},
       books = books ?? {},
       held = held ?? {};

  /// How many book requests went to [alias].
  int requestsTo(String alias) =>
      requested.where((request) => request == '$alias/api/book/').length;

  /// Lets the held requests to [alias] answer.
  void release(String alias) {
    held.remove(alias);
    _releases.remove(alias)?.complete();
  }

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    requested.add('$alias${request.url.path}');
    final now = (_inFlight[alias] ?? 0) + 1;
    _inFlight[alias] = now;
    if (now > (mostAtOnce[alias] ?? 0)) mostAtOnce[alias] = now;
    try {
      if (held.contains(alias)) {
        await (_releases[alias] ??= Completer<void>()).future;
      }
      final steps = [...?script[alias]];
      final step = steps.isEmpty ? const ScriptedBook() : steps.removeAt(0);
      script[alias] = steps;
      return switch (step) {
        ScriptedFailure(:final failure) => Err(failure),
        ScriptedUnusable(:final status, :final contentType) => Ok(
          CoordinatorResponse(
            statusCode: status,
            headers: {'content-type': contentType},
            body: utf8.encode('{"detail": "no book"}'),
          ),
        ),
        ScriptedBook() => Ok(
          CoordinatorResponse(
            statusCode: 200,
            headers: const {'content-type': 'application/json'},
            body: utf8.encode(jsonEncode(books[alias] ?? const [])),
          ),
        ),
      };
    } finally {
      _inFlight[alias] = (_inFlight[alias] ?? 1) - 1;
    }
  }

  String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(network)) {
      if (hostOf(coordinator.shortAlias, network) == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }
}
