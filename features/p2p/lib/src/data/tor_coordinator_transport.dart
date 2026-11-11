import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_tor/tor.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/coordinator_sessions_port.dart';

/// Opens a new Tor session, isolated from every other one, so on its own circuits.
typedef OpenTorSession = Future<TorSession> Function();

/// Builds the HTTP client that connects through the SOCKS endpoint of a Tor session.
typedef CreateTorHttpClient = HttpClient Function(TorProxyEndpoint endpoint);

/// Time one request to a coordinator may take in total: Tor session, connection, retries and body.
///
/// Twice [torConnectDeadline]: once Tor is ready, a first connection that fails only when the Tor connect budget expires still leaves a full budget for a retry on a new circuit.
/// On a cold start, the start of Tor counts against it too: on 10/11/2026 Tor took 62 s, which left about 10 s to the retry.
/// Screens should therefore wait for Tor to be ready before they ask for the books.
/// The opening of one Tor session is given the same time, a cold start of Tor included: no request could use a session that opens later, so an opening that has not completed by then is given up, with its place.
final coordinatorRequestDeadline = torConnectDeadline * 2;

/// Retries of an idempotent request after a connection failure, each on a new Tor session.
const coordinatorConnectRetries = 2;

/// Tor sessions that may exist for robots at any moment, all coordinators together: one per coordinator and robot, so a few robots on every coordinator of a network.
///
/// A session counts from the moment it starts to open until it is closed, the sessions replaced after a connection failure included while a request still uses them.
/// A session nobody uses is closed to make room for a new one, the least recently used first.
const maxRobotSessions = 32;

/// Tor sessions one robot may have on one coordinator at any moment, among [maxRobotSessions]: the one its requests use, and one more that a connection failure replaced while a request still uses it, or that is closing.
///
/// Without it, a coordinator that drops some connections and holds the others makes every request of one robot keep a session of its own, and takes every place from the robots of the other coordinators.
/// At two, a robot that already has two sessions never reaches the code that closes the unused session of another robot: write that rule down there before raising this number.
const maxSessionsPerRobotAndCoordinator = 2;

/// Time the close of one Tor session may take before the transport stops waiting for it.
///
/// Closing a session is local work in the embedded Tor, the end of a SOCKS listener, with nothing to wait for from the network: ten seconds is far more than it needs, and far less than [coordinatorRequestDeadline].
/// A session that has not closed by then is given up: it no longer counts among [maxRobotSessions], so a close that never completes cannot keep a place for good.
/// Each session given up is counted, and the count is logged as a warning when it reaches 1, 2, 4, 8 and so on, without naming a coordinator, a robot or a session.
const torSessionCloseTimeout = Duration(seconds: 10);

/// The longest header name and the longest header value a request may carry, in characters, which are bytes since only ASCII is sent.
///
/// The longest header of the RoboSats API is the `Authorization` of a first contact, with two armored OpenPGP keys: about 2 000 characters.
const maxHeaderLength = 16 * 1024;

/// The [CoordinatorTransport] of the app: every request goes through the embedded Tor.
///
/// Sessions: one Tor session per coordinator origin for the anonymous requests, and one more per robot for the requests made for it ([CoordinatorRequest.robot]).
/// A session, with its own HTTP client, so its own connections and circuits, is opened at the first request that needs it, shared by the requests of the same origin and robot while it works, and replaced by a new session after a connection failure.
/// So a coordinator, or anyone watching one, sees nothing that ties a robot to another robot, to the same robot on another coordinator, or to the anonymous reads of this device.
/// Robot sessions are bounded by [maxRobotSessions], whatever their coordinator, and the bound counts every session that is opening, open or closing: beyond it the least recently used session that no request is using is closed first, and the new session opens only once that one is closed.
/// One robot has at most [maxSessionsPerRobotAndCoordinator] of them on one coordinator, so a coordinator takes no more places than twice the robots this device sent to it, whatever it does with their connections.
/// When no place can be had, because every session is in use, because the robot already has its two on that coordinator and neither is closing, or because the session whose place was taken did not close within [torSessionCloseTimeout], the request fails with [CoordinatorTransportBusy], a retry after a connection failure included.
/// [CoordinatorTransportBusy] is given for nothing else: a caller that gets it sends the request again later, and does not report a coordinator that does not work.
/// The opening of a session is given [coordinatorRequestDeadline]: an opening that has not completed by then is given up and gives its place back, the requests waiting for it fail with [CoordinatorUnreachable], and a session that opens after all is closed unused.
/// [closeRobotSessions] closes the sessions of one robot, [closeSessions] closes them all, the sessions a connection failure replaced while a request still used them included: the requests still running fail, and the next request opens new sessions.
/// A session still opening is no longer waited for: it gives its place back at once, or once the session whose place it took has closed, and it is closed unused as soon as it opens.
/// Both complete even when a Tor session never finishes closing: such a session is given up after [torSessionCloseTimeout].
/// Neither is a lock: a request started after [closeRobotSessions] was called, the second request of a `fetchRobot` that follows error 7004 included, opens a new session of that robot.
/// The transport cannot tell such a request from the next request of the robot, which must go through, so a caller that gives up a robot lets its calls end, or drops them, before it closes its sessions.
///
/// Guarantees of the port contract:
/// - [send] always completes, with an [Ok] or an [Err], within [coordinatorRequestDeadline]: a timer answers [CoordinatorTimedOut] when it passes, whatever the request is waiting for (Tor, the session, the connection, a body sent a byte at a time), and cancels the attempt in progress;
/// - the body is read as a stream and the request is cancelled as soon as it exceeds [CoordinatorRequest.maxResponseBytes], or at once when the announced `Content-Length` does;
/// - redirects are never followed: a `3xx` answer is returned as it is;
/// - header names are given in lowercase;
/// - only `http` URLs to a `.onion` host, without user information, are sent: anything else fails with [CoordinatorTransportFailed] before a session is opened;
/// - a header is sent only when its name is an HTTP token, its value printable ASCII, and neither is longer than [maxHeaderLength]: anything else fails the same way;
/// - a request with an `Authorization` header and no [CoordinatorRequest.robot] fails the same way: a credential never travels on an anonymous session.
///
/// Rule 11 of `AGENTS.md`, precisely: every exception becomes a [CoordinatorTransportFailure].
/// An [Error] thrown by this adapter, or by the session opener or the client factory it is given, propagates to the caller of [send], after the session it concerns is closed.
/// An [Error] raised inside Dio reaches the adapter wrapped in a [DioException], and becomes [CoordinatorTransportFailed].
/// A session or a client that fails to close with an exception is dropped silently; a session that does not close within [torSessionCloseTimeout] is dropped too, and counted and logged as said there.
/// An [Error] thrown by the close of a Tor session reaches whoever waits for that close, [closeSessions] or [closeRobotSessions] included, once the session has left the count: the next close does not meet it again.
///
/// A connection failure is a SOCKS or socket error before any response header, or a connection closed before the headers, which is also what a dead pooled connection gives: the session is replaced, and a `GET` is retried at most [coordinatorConnectRetries] times within the same deadline.
/// Other methods are never retried, since the coordinator may have processed them.
/// An answer that is not valid HTTP (garbage, an invalid or duplicated `Content-Length`, a forbidden character or an endless header section) means the coordinator answered: it fails with [CoordinatorTransportFailed], without retry.
/// When the deadline passes before the headers, the session is also replaced, so that closing its client cancels a connection still in progress, once the other requests of that session end.
///
/// `User-Agent`: none is sent, whatever the request headers say (decision of 10/11/2026).
/// Its absence is the same for every Troc user, so it singles none of them out, and Troc does not pretend to be the official client.
/// `Accept-Encoding` is `identity` for every request, where `dart:io` would ask for `gzip`, and a body is never decompressed: the size cap counts the bytes that arrive, so a small compressed body cannot inflate in memory.
final class TorCoordinatorTransport
    implements CoordinatorTransport, CoordinatorSessionsPort {
  final OpenTorSession _openSession;
  final CreateTorHttpClient _createHttpClient;
  final Duration _deadline;
  final Duration _attemptTimeout;
  final Duration _closeTimeout;
  final bool Function(String host) _acceptsHost;

  /// The session new requests use for each origin and robot, opening or open, the least recently used first.
  final Map<_RouteKey, _Slot> _slots = {};

  /// Every session that is open: the ones of [_slots], and the ones a connection failure replaced or that are closing, until they are closed.
  final Set<_Route> _live = {};

  /// The places taken among [maxRobotSessions]: one per robot session that is opening, open or closing.
  int _robotPlaces = 0;

  /// The same places, per coordinator and robot: at most [maxSessionsPerRobotAndCoordinator] each.
  ///
  /// A place handed over by a closing session counts for the one that takes it, from that moment.
  final Map<_RouteKey, int> _placesOf = {};

  /// Incremented by [closeSessions]: a request that started before fails, and a session that finishes opening after it is closed at once.
  int _epoch = 0;

  /// The robots that have a request running, each with the generation [closeRobotSessions] increments: a request of that robot that started before fails.
  final Map<RobotSessionKey, _RobotRequests> _robotRequests = {};

  /// The Tor sessions given up after the close timeout since this transport was built.
  int _sessionsGivenUp = 0;

  /// The headers this adapter decides, whatever the request says.
  static const _ownHeaders = {
    HttpHeaders.userAgentHeader,
    HttpHeaders.acceptEncodingHeader,
  };

  /// [tor] is read when the first session opens, so the transport can be built before Tor is registered.
  TorCoordinatorTransport(Tor Function() tor, TorHttpClientFactory httpClients)
    : this.withSeams(
        openSession: () => tor().embedded.sessions.open(),
        createHttpClient: httpClients.create,
      );

  /// The transport with its Tor-specific parts replaced, for tests.
  ///
  /// [deadline] bounds a whole request, [attemptTimeout] the connection, the upload and every wait for data of one attempt, [closeTimeout] the close of one Tor session.
  /// [acceptsHost] decides which hosts may be reached, `.onion` hosts only by default, so that tests can reach a loopback server.
  @visibleForTesting
  TorCoordinatorTransport.withSeams({
    required this._openSession,
    required this._createHttpClient,
    Duration? deadline,
    Duration? attemptTimeout,
    Duration? closeTimeout,
    bool Function(String host)? acceptsHost,
  }) : _deadline = deadline ?? coordinatorRequestDeadline,
       _attemptTimeout = attemptTimeout ?? torConnectDeadline,
       _closeTimeout = closeTimeout ?? torSessionCloseTimeout,
       _acceptsHost = acceptsHost ?? _isOnion;

  /// Whether [host] is an onion service: every coordinator of the federation is reached at one.
  static bool _isOnion(String host) => host.toLowerCase().endsWith('.onion');

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) {
    final completer =
        Completer<Result<CoordinatorResponse, CoordinatorTransportFailure>>();
    final deadline = _Deadline();
    final timer = Timer(_deadline, () {
      deadline.expire();
      if (!completer.isCompleted) {
        completer.complete(const Err(CoordinatorTimedOut()));
      }
    });
    _exchange(request, deadline).then(
      (result) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(result);
      },
      onError: (Object error, StackTrace trace) {
        timer.cancel();
        if (completer.isCompleted) {
          // The caller already has its answer: a late bug still surfaces in the zone.
          Zone.current.handleUncaughtError(error, trace);
        } else if (error is Exception) {
          completer.complete(const Err(CoordinatorTransportFailed()));
        } else {
          completer.completeError(error, trace);
        }
      },
    );
    return completer.future;
  }

  @override
  Future<void> closeSessions() async {
    _epoch++;
    // A session still opening is no longer waited for, and is closed as soon as it is open.
    for (final slot in _slots.values) {
      slot.drop();
    }
    _slots.clear();
    // Every open session, the ones a connection failure replaced included: each leaves [_live] once it is closed.
    await Future.wait(List.of(_live).map((route) => route.close()));
  }

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async {
    // The requests of this robot that are running fail at their next step, whatever session they are on.
    _robotRequests[robot]?.generation++;
    for (final key in List.of(_slots.keys)) {
      // A session still opening is no longer waited for, and is closed as soon as it is open.
      if (key.robot == robot) _slots.remove(key)?.drop();
    }
    await Future.wait([
      for (final route in List.of(_live))
        if (route.key.robot == robot) route.close(),
    ]);
  }

  /// The counts behind the bounds, for tests.
  @visibleForTesting
  TorTransportCounts get countsForTesting => TorTransportCounts(
    places: _robotPlaces,
    placesOf: Map.unmodifiable(_placesOf),
    live: _live.length,
    waiting: _slots.values.fold(0, (sum, slot) => sum + slot.waiting),
    robotsWithRequests: _robotRequests.length,
    sessionsGivenUp: _sessionsGivenUp,
  );

  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> _exchange(
    CoordinatorRequest request,
    _Deadline deadline,
  ) async {
    final url = request.url;
    // A `Coordinator` can be built with any address, so the transport checks the URL itself.
    // User information in the URL would be sent as an `Authorization` header.
    if (!url.isScheme('http') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !_acceptsHost(url.host)) {
      return const Err(CoordinatorTransportFailed());
    }
    // A credential on an anonymous session would tie that session, and the reads of the book, to a robot.
    // Only `Authorization` is looked at, the one place a robot credential travels in today: the chat websocket will carry the token hash in a query parameter (`token_sha256_hex`), and this guard must be extended to it, and to any other credential, when it arrives.
    if (request.robot == null &&
        request.headers.keys.any(
          (name) => name.toLowerCase() == HttpHeaders.authorizationHeader,
        )) {
      return const Err(CoordinatorTransportFailed());
    }
    // Checked before any session opens: `dart:io` would refuse a header it finds invalid with an exception that quotes its value, and a header of megabytes would cost three sessions before it failed.
    if (!_areSendable(request.headers)) {
      return const Err(CoordinatorTransportFailed());
    }
    final robot = request.robot;
    if (robot == null) return _run(request, deadline, null);
    final requests = _robotRequests.putIfAbsent(robot, _RobotRequests.new);
    requests.running++;
    try {
      return await _run(request, deadline, requests);
    } finally {
      requests.running--;
      if (requests.running == 0 && identical(_robotRequests[robot], requests)) {
        _robotRequests.remove(robot);
      }
    }
  }

  static final RegExp _headerName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final RegExp _headerValue = RegExp(r'^[\x20-\x7E]*$');

  /// Whether every header can be written on the wire as it is: a name that is an HTTP token, a value made of printable ASCII characters and spaces only, and neither longer than [maxHeaderLength].
  ///
  /// A token hash in base91, an armored key and a Nostr key need nothing else, so anything else is a mistake of the caller, and never something to send.
  static bool _areSendable(Map<String, String> headers) =>
      headers.entries.every(
        (header) =>
            header.key.length <= maxHeaderLength &&
            header.value.length <= maxHeaderLength &&
            _headerName.hasMatch(header.key) &&
            _headerValue.hasMatch(header.value),
      );

  /// Sends [request] on the session of its origin and robot, opening or replacing that session as needed.
  ///
  /// [requests] is the entry of the robot of the request in [_robotRequests], `null` for an anonymous request.
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> _run(
    CoordinatorRequest request,
    _Deadline deadline,
    _RobotRequests? requests,
  ) async {
    final key = (origin: request.url.origin, robot: request.robot);
    final retries = request.method == CoordinatorHttpMethod.get
        ? coordinatorConnectRetries
        : 0;
    final epoch = _epoch;
    final generation = requests?.generation;
    // Whether [closeSessions], or [closeRobotSessions] for the robot of this request, ran since the request started.
    bool closed() => epoch != _epoch || generation != requests?.generation;
    for (var attempt = 0; ; attempt++) {
      if (deadline.passed) return const Err(CoordinatorTimedOut());
      // After [closeSessions] or [closeRobotSessions], a request still running fails instead of opening a new session, whichever session it was on.
      if (closed()) return const Err(CoordinatorTransportFailed());
      final slot = _slotFor(key);
      // No place for a new session of this robot: nothing was sent on this attempt, and the same request may pass later.
      if (slot == null) return const Err(CoordinatorTransportBusy());
      final _Route route;
      // Counted from here, without a gap, so that the session is never closed as unused before this request takes it.
      slot.waiting++;
      try {
        route = await slot.opening;
      } on _RouteException catch (exception) {
        // A request that a close stopped while it waited fails, whatever became of the session.
        return closed()
            ? const Err(CoordinatorTransportFailed())
            : Err(exception.failure);
      } finally {
        slot.waiting--;
      }
      if (closed()) return const Err(CoordinatorTransportFailed());
      if (deadline.passed) return const Err(CoordinatorTimedOut());

      route.acquire();
      final _Attempt outcome;
      try {
        outcome = await _attempt(route, request, deadline);
      } finally {
        route.release();
      }

      switch (outcome) {
        case _Answered(:final result):
          return result;
        case _Abandoned():
          _retire(key, slot, route);
          return const Err(CoordinatorTimedOut());
        case _ConnectFailed(:final reason):
          _retire(key, slot, route);
          if (attempt >= retries || deadline.passed) {
            return const Err(CoordinatorUnreachable());
          }
          // The reason and two counters only: the coordinator, the robot and the headers of the request never go to a log, where they would tie a robot to a coordinator or leak its credential.
          log.info(
            'P2P coordinator connection failed (${reason.name}), retrying on a new Tor session (${attempt + 1}/$retries)',
          );
      }
    }
  }

  /// The session of [key], opened if there is none, and marked as the most recently used; `null` when a robot needs a new one and no place can be had for it.
  _Slot? _slotFor(_RouteKey key) {
    final existing = _slots.remove(key);
    if (existing != null) return _slots[key] = existing;
    _Route? vacated;
    if (key.robot != null) {
      final place = _placeForRobot(key);
      if (place == null) return null;
      vacated = place.vacated;
    }
    final slot = _Slot();
    final opening = slot.opening = _open(_epoch, key, slot, vacated);
    _slots[key] = slot;
    // A session that fails to open leaves no trace, so the next request tries again.
    opening.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_slots[key], slot)) _slots.remove(key);
      },
    );
    return slot;
  }

  /// A place for one more session of the robot of [key] on its coordinator, or `null` when none can be had.
  ///
  /// A robot that already has [maxSessionsPerRobotAndCoordinator] places on this coordinator gets no other: its new session can only take the place of one of its own that is closing.
  /// Below that, a place is free while fewer than [maxRobotSessions] are taken.
  /// When all are taken, the place of a session that is already closing is handed over, or else the place of the least recently used session that no request uses, which [_open] closes.
  /// The new session then opens only once that one is closed, [_Place.vacated], so there are never more than [maxRobotSessions] at a time.
  _Place? _placeForRobot(_RouteKey key) {
    if ((_placesOf[key] ?? 0) >= maxSessionsPerRobotAndCoordinator) {
      final own = _closingRoute((route) => route.key == key);
      return own == null ? null : _handOver(own, key);
    }
    if (_robotPlaces < maxRobotSessions) {
      _takePlace(key);
      return (vacated: null);
    }
    final closing = _closingRoute((route) => route.key.robot != null);
    if (closing != null) return _handOver(closing, key);
    for (final MapEntry(key: other, value: slot) in _slots.entries) {
      final route = slot.route;
      if (other.robot == null || route == null || !slot.isIdle) continue;
      _slots.remove(other);
      return _handOver(route, key);
    }
    return null;
  }

  /// A session that is closing, whose place no new session waits for yet, and that [accepts] lets through.
  _Route? _closingRoute(bool Function(_Route route) accepts) {
    for (final route in _live) {
      if (route.isClosing && !route.placeHandedOver && accepts(route)) {
        return route;
      }
    }
    return null;
  }

  /// Gives the place of [route], which is closing or about to be closed, to a new session of [key]: the place is handed over once only, and counts for [key] from now on.
  _Place _handOver(_Route route, _RouteKey key) {
    route.placeHandedOver = true;
    _movePlace(route.key, key);
    return (vacated: route);
  }

  void _takePlace(_RouteKey key) {
    _robotPlaces++;
    _placesOf[key] = (_placesOf[key] ?? 0) + 1;
  }

  void _givePlaceBack(_RouteKey key) {
    _robotPlaces--;
    final left = (_placesOf[key] ?? 0) - 1;
    if (left > 0) {
      _placesOf[key] = left;
    } else {
      _placesOf.remove(key);
    }
  }

  void _movePlace(_RouteKey from, _RouteKey to) {
    _givePlaceBack(from);
    _takePlace(to);
  }

  /// Opens the session of [slot], after the session whose place it takes, if any, is closed.
  Future<_Route> _open(
    int epoch,
    _RouteKey key,
    _Slot slot,
    _Route? vacated,
  ) async {
    TorSession? session;
    _Route? route;
    // [closeSessions], or [closeRobotSessions] for this robot, ran while this session was opening.
    bool closed() => epoch != _epoch || slot.dropped;
    try {
      // The session whose place this one takes is closed first, here if it was not closing yet.
      final vacatedClosed = vacated == null || await vacated.close();
      // A close that ran meanwhile wins: the request was stopped, and is not told to come back later.
      if (closed()) throw const _RouteException(CoordinatorTransportFailed());
      // When that session did not close in time, opening now would go over the bound: the request fails, and the place, which that session no longer holds, is given back below.
      if (!vacatedClosed) throw const _RouteException(CoordinatorTransportBusy());
      final TorSession? opened;
      try {
        opened = await _openFor(slot);
      } on Exception {
        // Tor did not start, or gave no session: there is no circuit to the coordinator.
        throw const _RouteException(CoordinatorUnreachable());
      }
      // No longer waited for: a close dropped this session, or Tor did not give it within the deadline of a request.
      if (opened == null) {
        throw _RouteException(
          closed()
              ? const CoordinatorTransportFailed()
              : const CoordinatorUnreachable(),
        );
      }
      session = opened;
      final HttpClient client;
      try {
        client = _createHttpClient(session.endpoint);
      } on Exception {
        throw const _RouteException(CoordinatorTransportFailed());
      }
      client
        ..userAgent = null
        ..autoUncompress = false;
      route = _Route(
        key,
        session,
        client,
        _attemptTimeout,
        _closeSession,
        _forget,
      );
      _live.add(route);
      if (closed()) throw const _RouteException(CoordinatorTransportFailed());
      slot.route = route;
      return route;
    } finally {
      // Whatever went wrong, a bug included, the session does not stay open, and its place is given back once it is closed, or once its close threw.
      if (slot.route == null) {
        if (route != null) {
          await route.close();
        } else {
          try {
            if (session != null) await _closeSession(session);
          } finally {
            if (key.robot != null) _givePlaceBack(key);
          }
        }
      }
    }
  }

  /// Asks Tor for the session of [slot], and waits for it at most [_deadline] and only while [slot] is not dropped: `null` when it stopped waiting.
  ///
  /// A session that Tor gives after that is closed at once, unused: it never holds a place.
  Future<TorSession?> _openFor(_Slot slot) {
    final pending = _openSession();
    final result = Completer<TorSession?>();
    late final Timer timer;
    void stopWaiting() {
      timer.cancel();
      if (!result.isCompleted) result.complete(null);
    }

    timer = Timer(_deadline, stopWaiting);
    unawaited(slot.whenDropped.then((_) => stopWaiting()));
    pending.then(
      (session) {
        timer.cancel();
        if (result.isCompleted) {
          unawaited(_closeSession(session));
        } else {
          result.complete(session);
        }
      },
      onError: (Object error, StackTrace trace) {
        timer.cancel();
        if (!result.isCompleted) {
          result.completeError(error, trace);
        } else if (error is! Exception) {
          // Nobody waits for this session any more: a late bug still surfaces in the zone.
          Zone.current.handleUncaughtError(error, trace);
        }
      },
    );
    return result.future;
  }

  /// Called once [route] is closed, or given up as one that does not close: it no longer counts.
  void _forget(_Route route) {
    _live.remove(route);
    if (route.key.robot != null && !route.placeHandedOver) {
      _givePlaceBack(route.key);
    }
  }

  /// Stops reusing [route] for [key]: it closes once its last request ends, and until then [closeSessions] and [closeRobotSessions] still reach it.
  void _retire(_RouteKey key, _Slot slot, _Route route) {
    if (identical(_slots[key], slot)) _slots.remove(key);
    route.retire();
  }

  Future<_Attempt> _attempt(
    _Route route,
    CoordinatorRequest request,
    _Deadline deadline,
  ) async {
    final cancel = CancelToken();
    deadline.watch(cancel);
    try {
      final Response<ResponseBody> response;
      try {
        response = await route.dio.requestUri<ResponseBody>(
          request.url,
          data: request.body,
          options: Options(
            method: request.method.name.toUpperCase(),
            headers: {
              for (final MapEntry(:key, :value) in request.headers.entries)
                if (!_ownHeaders.contains(key.toLowerCase())) key: value,
              HttpHeaders.acceptEncodingHeader: 'identity',
            },
          ),
          cancelToken: cancel,
        );
      } on DioException catch (exception) {
        return _failureBeforeHeaders(exception);
      }

      final body = response.data;
      final statusCode = response.statusCode;
      if (body == null || statusCode == null) {
        cancel.cancel();
        return const _Answered(Err(CoordinatorTransportFailed()));
      }
      final headers = {
        for (final MapEntry(:key, :value) in response.headers.map.entries)
          key.toLowerCase(): value.join(', '),
      };
      final announced = int.tryParse(
        headers[HttpHeaders.contentLengthHeader] ?? '',
      );
      if (announced != null && announced > request.maxResponseBytes) {
        cancel.cancel();
        return const _Answered(Err(CoordinatorResponseTooLarge()));
      }
      final read = await _readCapped(
        body.stream,
        request.maxResponseBytes,
        cancel,
      );
      return _Answered(switch (read) {
        Ok(value: final bytes) => Ok(
          CoordinatorResponse(
            statusCode: statusCode,
            headers: headers,
            body: bytes,
          ),
        ),
        Err(:final failure) => Err(failure),
      });
    } finally {
      deadline.forget(cancel);
    }
  }

  /// Reads [stream] until it ends, or cancels the request as soon as it exceeds [maxBytes].
  static Future<Result<Uint8List, CoordinatorTransportFailure>> _readCapped(
    Stream<Uint8List> stream,
    int maxBytes,
    CancelToken cancel,
  ) {
    final completer =
        Completer<Result<Uint8List, CoordinatorTransportFailure>>();
    final bytes = BytesBuilder(copy: false);
    late final StreamSubscription<Uint8List> subscription;
    subscription = stream.listen(
      (chunk) {
        if (completer.isCompleted) return;
        if (bytes.length + chunk.length > maxBytes) {
          // The chunk is dropped unread: nothing beyond the cap is kept.
          cancel.cancel();
          subscription.cancel().ignore();
          completer.complete(const Err(CoordinatorResponseTooLarge()));
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace _) {
        if (completer.isCompleted) return;
        completer.complete(Err(_failureWhileReading(error)));
      },
      onDone: () {
        if (completer.isCompleted) return;
        completer.complete(Ok(bytes.takeBytes()));
      },
      cancelOnError: true,
    );
    return completer.future;
  }

  /// What a failure before any response header means.
  ///
  /// Dio reports a connection closed before the headers as [DioExceptionType.connectionError], and rethrows every other [HttpException], which dart:io raises when what arrives is not a valid HTTP response.
  static _Attempt _failureBeforeHeaders(
    DioException exception,
  ) => switch (exception.type) {
    // Only the deadline cancels a request.
    DioExceptionType.cancel => const _Abandoned(),
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => const _Answered(
      Err(CoordinatorTimedOut()),
    ),
    DioExceptionType.badCertificate || DioExceptionType.badResponse =>
      const _Answered(Err(CoordinatorTransportFailed())),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => switch (exception.error) {
      // Dio wraps whatever the stack threw: an Error there is a bug, not a connection problem.
      Error() => const _Answered(Err(CoordinatorTransportFailed())),
      // The coordinator answered, but not in HTTP: a new circuit would get the same answer.
      HttpException() when exception.type == DioExceptionType.unknown =>
        const _Answered(Err(CoordinatorTransportFailed())),
      // `dart:io` refused to write the request, such as a header it finds invalid: no session would send it, and the message of the exception, which may quote a header value, is dropped here.
      FormatException() => const _Answered(Err(CoordinatorTransportFailed())),
      final Object cause => _ConnectFailed(
        TorHttpClientFactory.classify(cause),
      ),
      null => const _ConnectFailed(TorConnectFailure.other),
    },
  };

  /// What a failure while the body arrives means: the connection worked, so it is not retried.
  static CoordinatorTransportFailure _failureWhileReading(Object error) =>
      switch (error) {
        DioException(
          type: DioExceptionType.cancel ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout,
        ) =>
          const CoordinatorTimedOut(),
        DioException(error: IOException()) ||
        IOException() => const CoordinatorUnreachable(),
        _ => const CoordinatorTransportFailed(),
      };

  /// Closes [session] and tells whether it is closed: `false` when it did not answer within the close timeout, and is given up.
  Future<bool> _closeSession(TorSession session) async {
    try {
      await session.close().timeout(_closeTimeout);
    } on TimeoutException {
      _sessionsGivenUp++;
      // The count only, at 1, 2, 4, 8 and so on, so that a Tor that never closes a session cannot fill the support log: the coordinator, the robot and the session are never named.
      if (_sessionsGivenUp & (_sessionsGivenUp - 1) == 0) {
        log.warning(
          'P2P Tor session given up: it did not close in time ($_sessionsGivenUp so far)',
        );
      }
      return false;
    } on Exception {
      // Closing is best effort: the session is dropped either way.
    }
    return true;
  }
}

/// What a session is kept for: one origin, and one robot or the anonymous requests.
typedef _RouteKey = ({String origin, RobotSessionKey? robot});

/// A place for a new robot session, and the session it is taken from, if any, which must be closed before the new one opens.
typedef _Place = ({_Route? vacated});

/// The requests of one robot that are running.
final class _RobotRequests {
  /// How many are running: the entry is dropped when none is.
  int running = 0;

  /// Incremented by [TorCoordinatorTransport.closeRobotSessions].
  int generation = 0;
}

/// The session of one [_RouteKey], while it opens and once it is open.
final class _Slot {
  late final Future<_Route> opening;

  /// The session once it is open.
  _Route? route;

  /// The requests that picked this session and wait for it to open.
  int waiting = 0;

  final _dropped = Completer<void>();

  /// Whether [TorCoordinatorTransport.closeSessions] or [TorCoordinatorTransport.closeRobotSessions] dropped this session: it is no longer waited for, and it is closed as soon as it is open.
  bool get dropped => _dropped.isCompleted;

  /// Completes when this session is dropped.
  Future<void> get whenDropped => _dropped.future;

  void drop() {
    if (!_dropped.isCompleted) _dropped.complete();
  }

  /// Whether the session is open and no request uses it or is about to.
  bool get isIdle => waiting == 0 && (route?.isUnused ?? false);
}

/// What [TorCoordinatorTransport.countsForTesting] reports.
@visibleForTesting
final class TorTransportCounts {
  /// The places taken among [maxRobotSessions].
  final int places;

  /// The places of each robot on each coordinator, for the robots that hold one.
  final Map<({String origin, RobotSessionKey? robot}), int> placesOf;

  /// The sessions the transport keeps track of until they are closed or given up, anonymous ones included.
  final int live;

  /// The requests waiting for a session to open.
  final int waiting;

  /// The robots that have a request running.
  final int robotsWithRequests;

  /// The Tor sessions given up after the close timeout since the transport was built.
  final int sessionsGivenUp;

  const TorTransportCounts({
    required this.places,
    required this.placesOf,
    required this.live,
    required this.waiting,
    required this.robotsWithRequests,
    required this.sessionsGivenUp,
  });
}

/// One Tor session with its HTTP client, shared by the requests of one [_RouteKey].
final class _Route {
  final _RouteKey key;
  final TorSession _session;
  final HttpClient _client;
  final Future<bool> Function(TorSession session) _closeSession;
  final void Function(_Route route) _onClosed;
  final Dio dio;
  int _users = 0;
  bool _retired = false;
  Future<bool>? _closing;

  /// Whether a new session already waits for this one to close to take its place among the robot sessions.
  bool placeHandedOver = false;

  _Route(
    this.key,
    this._session,
    HttpClient client,
    Duration attemptTimeout,
    this._closeSession,
    this._onClosed,
  ) : _client = client,
      dio =
          Dio(
              BaseOptions(
                connectTimeout: attemptTimeout,
                sendTimeout: attemptTimeout,
                receiveTimeout: attemptTimeout,
                followRedirects: false,
                maxRedirects: 0,
                validateStatus: (_) => true,
                responseType: ResponseType.stream,
              ),
            )
            ..httpClientAdapter = IOHttpClientAdapter(
              createHttpClient: () => client,
            );

  bool get isUnused => _users == 0;

  bool get isClosing => _closing != null;

  void acquire() => _users++;

  void release() {
    _users--;
    if (_retired && _users == 0) unawaited(close());
  }

  void retire() {
    _retired = true;
    if (_users == 0) unawaited(close());
  }

  /// Closes this session, once: whether the Tor session is closed, `false` when it was given up after the close timeout.
  Future<bool> close() => _closing ??= _close();

  /// Closes the client, which also cancels a connection still being made, then the session, and only then tells the transport.
  ///
  /// The transport is told even when one of them throws an [Error]: the session leaves the count, and the [Error] goes on to whoever waits for this close.
  Future<bool> _close() async {
    try {
      try {
        dio.close(force: true);
      } on Exception {
        // Closing is best effort: the client and the session below are closed either way.
      }
      try {
        // Dio only closes the client it already used, so the client is closed too.
        _client.close(force: true);
      } on Exception {
        // Closing is best effort: the session below is closed either way.
      }
      return await _closeSession(_session);
    } finally {
      _onClosed(this);
    }
  }
}

/// How one attempt ended.
sealed class _Attempt {
  const _Attempt();
}

/// The coordinator answered, or the exchange failed in a way a new session would not fix.
final class _Answered extends _Attempt {
  final Result<CoordinatorResponse, CoordinatorTransportFailure> result;

  const _Answered(this.result);
}

/// The deadline passed before any header: the request is given up, and its session with it.
final class _Abandoned extends _Attempt {
  const _Abandoned();
}

/// No connection to the coordinator: a new session, with new circuits, may succeed.
final class _ConnectFailed extends _Attempt {
  final TorConnectFailure reason;

  const _ConnectFailed(this.reason);
}

/// Why no session could serve a request.
final class _RouteException implements Exception {
  final CoordinatorTransportFailure failure;

  const _RouteException(this.failure);
}

/// The overall deadline of one request: once it passes, it cancels the attempt in progress and allows no other.
final class _Deadline {
  bool passed = false;
  CancelToken? _current;

  void expire() {
    passed = true;
    _current?.cancel();
  }

  void watch(CancelToken cancel) {
    _current = cancel;
    if (passed) cancel.cancel();
  }

  void forget(CancelToken cancel) {
    if (identical(_current, cancel)) _current = null;
  }
}
