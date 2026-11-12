import 'dart:async';
import 'dart:collection';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show Coordinator, RobosatsNetwork, RobotSessionKey;

import 'p2p_failure.dart';

/// The robot requests of the whole feature to the coordinators: how many are in flight at once, in which order the others wait, when a request the transport found busy is sent again, and what each coordinator did lately.
///
/// There is one for the feature, so that every screen and every robot share its places; the polling of orders of phase 2 is to go through it too, with [RobotRequests.send].
/// A coordinator is one instance of the federation list on one network: the same alias on testnet and on mainnet is two coordinators here, with places and memories of their own.
/// What it remembers, the busy answers and the nicknames refused of each coordinator, is in memory only and ends with the run of the app.
/// It holds no token and no key: a robot is named by its [RobotSessionKey], made from its public hash id, and a request is a function it runs.
/// Its waits use the clock, the delay and the randomness it is given, so that tests control them.
final class RobotRequestLimiter {
  /// Robot requests in flight at once to one coordinator, whatever their robot: the others wait in the order they were asked.
  ///
  /// The transport keeps two places per robot on a coordinator and 24 for all the robots of one coordinator (`maxRobotSessionsPerCoordinator`): with two requests at a time, a coordinator that holds its answers keeps two places at most.
  static const maxInFlight = 2;

  /// Attempts of one request that the transport answers busy (`CoordinatorTransportBusy`): the first and three more.
  static const maxAttempts = 4;

  /// The waits before the second, third and fourth attempts of a request answered busy, each spread by [jitter].
  static const busyWaits = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// How far each wait of [busyWaits] is spread, up or down, at random: a wait of 2 s lasts from 1.6 s to 2.4 s, so that requests answered busy together are not sent again together.
  static const jitter = 0.2;

  /// Busy answers one coordinator may give within [busyWindow]: at one more, its requests fail at once, until enough of them are older than the window.
  static const maxBusyAnswers = 12;

  /// See [maxBusyAnswers].
  static const busyWindow = Duration(minutes: 10);

  /// The wait before the read that follows a first contact answered with a nickname already taken (error 7004) after the client's own read: the coordinator may still be creating the robot for another copy of the same request.
  static const nicknameRecheckWait = Duration(seconds: 10);

  /// First contacts one coordinator may refuse with a nickname taken, still taken at the read that follows, in one run of the app: from then on, first contacts to it fail at once.
  static const maxNicknameRefusals = 3;

  /// How long a release waits for the requests of its robot in flight before the sessions of the robot are closed all the same.
  static const releaseWait = Duration(seconds: 10);

  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final double Function() _random;

  /// The places of each coordinator that has requests in flight or waiting.
  final Map<_Lane, _Places> _places = {};

  /// The calls opened for each robot and not closed or released yet.
  final Map<RobotSessionKey, Set<RobotRequests>> _open = {};

  /// The times of the busy answers of each coordinator, within [busyWindow].
  final Map<_Lane, List<DateTime>> _busyAnswers = {};

  /// The first contacts each coordinator refused with a nickname taken, in this run.
  final Map<_Lane, int> _nicknameRefusals = {};

  /// `clock` gives the time of the busy answers, `delay` waits, and `random` draws a number from 0 (included) to 1 (excluded) for each spread wait.
  RobotRequestLimiter({
    required this._clock,
    required this._delay,
    required this._random,
  });

  /// Opens the requests of one call made for [robot], such as one use of a use case: each request goes through [RobotRequests.send], and all of them stop at a [release] of the robot.
  ///
  /// Close it with [RobotRequests.close] once the call has ended, whatever its outcome.
  RobotRequests open(RobotSessionKey robot) {
    final requests = RobotRequests._(this, robot);
    (_open[robot] ??= {}).add(requests);
    return requests;
  }

  /// Whether a call opened for [robot] is still running: one opened after its last release counts.
  bool isInUse(RobotSessionKey robot) => _open[robot]?.isNotEmpty ?? false;

  /// Releases [robot], whose screen is gone: its requests waiting for a place are dropped, the calls opened for it so far send nothing more, and what it returns tells when its requests in flight have ended.
  ///
  /// A request in flight is not stopped: it runs to its end, and the call that sent it sends nothing after it.
  /// A call opened for the robot after this release is not affected.
  RobotRelease release(RobotSessionKey robot) {
    final released = _open.remove(robot) ?? const <RobotRequests>{};
    for (final requests in released) {
      requests._released = true;
    }
    for (final lane in [..._places.keys]) {
      final places = _places[lane];
      if (places == null) continue;
      final dropped = [
        for (final waiter in places.waiting)
          if (waiter.requests._released) waiter,
      ];
      places.waiting.removeWhere((waiter) => waiter.requests._released);
      for (final waiter in dropped) {
        waiter.turn.complete(false);
      }
      _forgetIfIdle(lane);
    }
    final running = [
      for (final requests in released)
        if (requests._inFlight > 0) requests._ended(),
    ];
    if (running.isEmpty) {
      return RobotRelease._(Future.value(), Future.value(true));
    }
    final ended = Future.wait(running).then((_) {});
    return RobotRelease._(
      ended,
      Future.any([
        ended.then((_) => true),
        _delay(releaseWait).then((_) => false),
      ]),
    );
  }

  /// Whether first contacts to [coordinator] on [network] fail at once: it refused [maxNicknameRefusals] robots with a nickname taken in this run.
  bool refusesFirstContacts(RobosatsNetwork network, Coordinator coordinator) =>
      (_nicknameRefusals[(network, coordinator.shortAlias)] ?? 0) >=
      maxNicknameRefusals;

  /// Notes that [coordinator] on [network] refused a first contact with a nickname taken, still taken at the read that follows.
  void noteNicknameRefused(RobosatsNetwork network, Coordinator coordinator) {
    final lane = (network, coordinator.shortAlias);
    _nicknameRefusals[lane] = (_nicknameRefusals[lane] ?? 0) + 1;
  }

  /// Whether the requests to [lane] fail at once: it gave more than [maxBusyAnswers] busy answers within [busyWindow].
  ///
  /// An answer dated after the clock, which went back since, no longer counts: a clock set back never keeps a coordinator refused longer than the window.
  bool _refuses(_Lane lane) {
    final answers = _busyAnswers[lane];
    if (answers == null) return false;
    final now = _clock();
    final since = now.subtract(busyWindow);
    answers.removeWhere((at) => !at.isAfter(since) || at.isAfter(now));
    if (answers.isEmpty) _busyAnswers.remove(lane);
    return answers.length > maxBusyAnswers;
  }

  void _noteBusy(_Lane lane) => (_busyAnswers[lane] ??= []).add(_clock());

  /// [wait] spread by up to [jitter] either way, from a number [_random] draws.
  Duration _spread(Duration wait) {
    final draw = _random().clamp(0.0, 1.0);
    final factor = 1 + jitter * (2 * draw - 1);
    return Duration(microseconds: (wait.inMicroseconds * factor).round());
  }

  /// Completes with `true` once [requests] holds a place of [lane], in the order asked, or with `false` when its robot was released while it waited.
  Future<bool> _turn(_Lane lane, RobotRequests requests) {
    final places = _places[lane] ??= _Places();
    if (places.inFlight < maxInFlight && places.waiting.isEmpty) {
      places.inFlight++;
      return Future.value(true);
    }
    final waiter = _Waiter(requests);
    places.waiting.add(waiter);
    return waiter.turn.future;
  }

  /// Gives back a place of [lane], to the request that has waited longest if any.
  void _leave(_Lane lane) {
    final places = _places[lane];
    if (places == null || places.inFlight == 0) {
      throw StateError('a place was given back that was not taken');
    }
    places.inFlight--;
    if (places.waiting.isNotEmpty) {
      places.inFlight++;
      places.waiting.removeFirst().turn.complete(true);
    }
    _forgetIfIdle(lane);
  }

  void _forgetIfIdle(_Lane lane) {
    final places = _places[lane];
    if (places != null && places.inFlight == 0 && places.waiting.isEmpty) {
      _places.remove(lane);
    }
  }
}

/// The requests of one call made for one robot, such as one use of a use case, opened by [RobotRequestLimiter.open].
final class RobotRequests {
  final RobotRequestLimiter _limiter;
  final RobotSessionKey _robot;

  /// Whether the robot was released since this call was opened: nothing more is sent.
  bool _released = false;

  bool _closed = false;

  /// The requests of this call in flight.
  int _inFlight = 0;

  /// Completes when the last request of this call in flight has ended.
  Completer<void>? _idle;

  RobotRequests._(this._limiter, this._robot);

  /// Sends [request] to [coordinator] on [network] once one of its [RobotRequestLimiter.maxInFlight] places is free, and again while the transport answers it busy, which [isBusy] reads from its answer.
  ///
  /// [after] is waited first, holding no place.
  /// The answer is that of the last attempt, in an [Ok], whatever it says, unless every attempt was answered busy.
  /// A busy answer is waited out, holding no place, for the wait of [RobotRequestLimiter.busyWaits] that follows that attempt, spread by [RobotRequestLimiter.jitter]; the request then waits for a place again, behind the requests asked meanwhile.
  /// It fails with [RobotCoordinatorBusyFailure], the request not sent again, after [RobotRequestLimiter.maxAttempts] busy answers, or at once when the coordinator gave more than [RobotRequestLimiter.maxBusyAnswers] busy answers within [RobotRequestLimiter.busyWindow], that request's included.
  /// It fails with [RobotReleasedFailure] once the robot is released: a request still waiting for its place, for [after] or after a busy answer is not sent.
  /// An exception or an error that [request] throws reaches the caller, and its place is given back.
  Future<Result<T, P2pFailure>> send<T>(
    RobosatsNetwork network,
    Coordinator coordinator,
    Future<T> Function() request, {
    required bool Function(T answer) isBusy,
    Duration after = Duration.zero,
  }) async {
    if (_closed) throw StateError('these robot requests are closed');
    final lane = (network, coordinator.shortAlias);
    if (after > Duration.zero) await _limiter._delay(after);
    for (var attempt = 1; ; attempt++) {
      if (_released) return const Err(RobotReleasedFailure());
      if (_limiter._refuses(lane)) {
        return const Err(RobotCoordinatorBusyFailure());
      }
      final T answer;
      switch (await _inPlace(lane, request, isBusy)) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          answer = value;
      }
      if (!isBusy(answer)) return Ok(answer);
      if (attempt >= RobotRequestLimiter.maxAttempts ||
          _limiter._refuses(lane)) {
        return const Err(RobotCoordinatorBusyFailure());
      }
      await _limiter._delay(
        _limiter._spread(RobotRequestLimiter.busyWaits[attempt - 1]),
      );
    }
  }

  /// Ends this call: its robot is no longer in use for it, and it sends nothing more.
  void close() {
    _closed = true;
    final open = _limiter._open[_robot];
    if (open == null) return;
    open.remove(this);
    if (open.isEmpty) _limiter._open.remove(_robot);
  }

  /// [request] run in a place of [lane], or why it was not run.
  ///
  /// A busy answer, as [isBusy] reads it, is counted before the place goes to the next request, so that a request that waited sees its coordinator refused by that very answer.
  Future<Result<T, P2pFailure>> _inPlace<T>(
    _Lane lane,
    Future<T> Function() request,
    bool Function(T answer) isBusy,
  ) async {
    if (!await _limiter._turn(lane, this)) {
      return const Err(RobotReleasedFailure());
    }
    _inFlight++;
    try {
      // The robot may have been released, or the coordinator refused, while this request waited for its place.
      if (_released) return const Err(RobotReleasedFailure());
      if (_limiter._refuses(lane)) {
        return const Err(RobotCoordinatorBusyFailure());
      }
      final answer = await request();
      if (isBusy(answer)) _limiter._noteBusy(lane);
      return Ok(answer);
    } finally {
      _inFlight--;
      _limiter._leave(lane);
      if (_inFlight == 0) {
        final idle = _idle;
        _idle = null;
        idle?.complete();
      }
    }
  }

  Future<void> _ended() => (_idle ??= Completer<void>()).future;
}

/// What a release of a robot waits for: the requests it had in flight.
final class RobotRelease {
  /// Completes once every request the robot had in flight when it was released has ended, at once when it had none.
  final Future<void> ended;

  /// Completes with `true` once [ended] has, or with `false` after [RobotRequestLimiter.releaseWait] when it has not by then.
  final Future<bool> endedInTime;

  const RobotRelease._(this.ended, this.endedInTime);
}

/// A coordinator, on one network, by its short alias.
typedef _Lane = (RobosatsNetwork, String);

/// The places of one coordinator: the requests in flight, and those waiting, in the order asked.
final class _Places {
  int inFlight = 0;
  final Queue<_Waiter> waiting = Queue();
}

/// A request waiting for a place, for the call [requests].
final class _Waiter {
  final RobotRequests requests;
  final Completer<bool> turn = Completer();

  _Waiter(this.requests);
}
