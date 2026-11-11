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
final coordinatorRequestDeadline = torConnectDeadline * 2;

/// Retries of an idempotent request after a connection failure, each on a new Tor session.
const coordinatorConnectRetries = 2;

/// Tor sessions kept open for robots, one per coordinator and robot: a few robots on every coordinator of a network.
///
/// A session nobody uses is closed to make room for a new one, the least recently used first.
const maxRobotSessions = 32;

/// The [CoordinatorTransport] of the app: every request goes through the embedded Tor.
///
/// Sessions: one Tor session per coordinator origin for the anonymous requests, and one more per robot for the requests made for it ([CoordinatorRequest.robot]).
/// A session, with its own HTTP client, so its own connections and circuits, is opened at the first request that needs it, shared by the requests of the same origin and robot while it works, and replaced by a new session after a connection failure.
/// So a coordinator, or anyone watching one, sees nothing that ties a robot to another robot, to the same robot on another coordinator, or to the anonymous reads of this device.
/// Robot sessions are bounded by [maxRobotSessions]: beyond it the least recently used session that no request is using is closed, and when every one is in use the request fails with [CoordinatorTransportFailed].
/// [closeRobotSessions] closes the sessions of one robot, [closeSessions] closes them all; the next request opens new ones.
///
/// Guarantees of the port contract:
/// - [send] always completes, with an [Ok] or an [Err], within [coordinatorRequestDeadline]: a timer answers [CoordinatorTimedOut] when it passes, whatever the request is waiting for (Tor, the session, the connection, a body sent a byte at a time), and cancels the attempt in progress;
/// - the body is read as a stream and the request is cancelled as soon as it exceeds [CoordinatorRequest.maxResponseBytes], or at once when the announced `Content-Length` does;
/// - redirects are never followed: a `3xx` answer is returned as it is;
/// - header names are given in lowercase;
/// - only `http` URLs to a `.onion` host, without user information, are sent: anything else fails with [CoordinatorTransportFailed] before a session is opened;
/// - a request with an `Authorization` header and no [CoordinatorRequest.robot] fails the same way: a credential never travels on an anonymous session.
///
/// Rule 11 of `AGENTS.md`, precisely: every exception becomes a [CoordinatorTransportFailure].
/// An [Error] thrown by this adapter, or by the session opener or the client factory it is given, propagates to the caller of [send], after the session it concerns is closed.
/// An [Error] raised inside Dio reaches the adapter wrapped in a [DioException], and becomes [CoordinatorTransportFailed].
/// A session or a client that fails to close with an exception is dropped silently.
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
  final bool Function(String host) _acceptsHost;

  /// The session of each origin and robot, opening or open, the least recently used first.
  final Map<_RouteKey, _Slot> _slots = {};

  /// The open sessions, closed by [closeSessions].
  final Set<_Route> _live = {};

  /// Incremented by [closeSessions]: a session that finishes opening after it is closed at once.
  int _epoch = 0;

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
  /// [deadline] bounds a whole request, [attemptTimeout] the connection, the upload and every wait for data of one attempt.
  /// [acceptsHost] decides which hosts may be reached, `.onion` hosts only by default, so that tests can reach a loopback server.
  @visibleForTesting
  TorCoordinatorTransport.withSeams({
    required this._openSession,
    required this._createHttpClient,
    Duration? deadline,
    Duration? attemptTimeout,
    bool Function(String host)? acceptsHost,
  }) : _deadline = deadline ?? coordinatorRequestDeadline,
       _attemptTimeout = attemptTimeout ?? torConnectDeadline,
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
    _slots.clear();
    final live = List.of(_live);
    _live.clear();
    await Future.wait(live.map((route) => route.close()));
  }

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async {
    final closing = <Future<void>>[];
    for (final key in List.of(_slots.keys)) {
      if (key.robot != robot) continue;
      final slot = _slots.remove(key);
      if (slot == null) continue;
      slot.dropped = true;
      final route = slot.route;
      if (route != null) {
        _live.remove(route);
        closing.add(route.close());
      }
    }
    await Future.wait(closing);
  }

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
    if (request.robot == null &&
        request.headers.keys.any(
          (name) => name.toLowerCase() == HttpHeaders.authorizationHeader,
        )) {
      return const Err(CoordinatorTransportFailed());
    }
    final key = (origin: url.origin, robot: request.robot);
    final retries = request.method == CoordinatorHttpMethod.get
        ? coordinatorConnectRetries
        : 0;
    final epoch = _epoch;
    _Slot? previous;
    for (var attempt = 0; ; attempt++) {
      if (deadline.passed) return const Err(CoordinatorTimedOut());
      // After [closeSessions] or [closeRobotSessions], a request still running fails instead of opening a new session.
      if (epoch != _epoch || (previous?.dropped ?? false)) {
        return const Err(CoordinatorTransportFailed());
      }
      final slot = _slotFor(key);
      // Every robot session is in use: nothing can be closed to make room.
      if (slot == null) return const Err(CoordinatorTransportFailed());
      previous = slot;
      final _Route route;
      // Counted from here, without a gap, so that the session is never closed as unused before this request takes it.
      slot.waiting++;
      try {
        route = await slot.opening;
      } on _RouteException catch (exception) {
        return Err(exception.failure);
      } finally {
        slot.waiting--;
      }
      if (slot.dropped) return const Err(CoordinatorTransportFailed());
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
          // The reason only: a line that named the coordinator of a robot request would tie the two.
          log.info(
            'P2P coordinator connection failed (${reason.name}), retrying on a new Tor session (${attempt + 1}/$retries)',
          );
      }
    }
  }

  /// The session of [key], opened if there is none, and marked as the most recently used; `null` when a robot needs a new one and none can be closed to make room.
  _Slot? _slotFor(_RouteKey key) {
    final existing = _slots.remove(key);
    if (existing != null) return _slots[key] = existing;
    if (key.robot != null && !_makeRoomForRobot()) return null;
    final slot = _Slot(_open(_epoch));
    _slots[key] = slot;
    slot.opening.then<void>(
      (route) {
        slot.route = route;
        // [closeRobotSessions] ran while this session was opening.
        if (slot.dropped) {
          _live.remove(route);
          unawaited(route.close());
        }
      },
      // A session that fails to open leaves no trace, so the next request tries again.
      onError: (Object _) {
        if (identical(_slots[key], slot)) _slots.remove(key);
      },
    );
    return slot;
  }

  /// Whether one more robot session may open, after closing the least recently used idle one when [maxRobotSessions] are already kept.
  bool _makeRoomForRobot() {
    var robots = 0;
    _RouteKey? idle;
    for (final MapEntry(:key, value: slot) in _slots.entries) {
      if (key.robot == null) continue;
      robots++;
      if (idle == null && slot.isIdle) idle = key;
    }
    if (robots < maxRobotSessions) return true;
    final slot = idle == null ? null : _slots.remove(idle);
    final route = slot?.route;
    if (route == null) return false;
    _live.remove(route);
    route.retire();
    return true;
  }

  Future<_Route> _open(int epoch) async {
    final TorSession session;
    try {
      session = await _openSession();
    } on Exception {
      // Tor did not start, or gave no session: there is no circuit to the coordinator.
      throw const _RouteException(CoordinatorUnreachable());
    }
    var kept = false;
    try {
      final HttpClient client;
      try {
        client = _createHttpClient(session.endpoint);
      } on Exception {
        throw const _RouteException(CoordinatorTransportFailed());
      }
      client
        ..userAgent = null
        ..autoUncompress = false;
      final route = _Route(session, client, _attemptTimeout);
      if (epoch != _epoch) {
        // [closeSessions] ran while this session was opening.
        await route.close();
        throw const _RouteException(CoordinatorTransportFailed());
      }
      _live.add(route);
      kept = true;
      return route;
    } finally {
      // Whatever went wrong, a bug included, the session does not stay open.
      if (!kept) await _closeSession(session);
    }
  }

  /// Stops reusing [route] for [key]: it closes once its last request ends.
  void _retire(_RouteKey key, _Slot slot, _Route route) {
    if (identical(_slots[key], slot)) _slots.remove(key);
    _live.remove(route);
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

  static Future<void> _closeSession(TorSession session) async {
    try {
      await session.close();
    } on Exception {
      // Closing is best effort: the session is dropped either way.
    }
  }
}

/// What a session is kept for: one origin, and one robot or the anonymous requests.
typedef _RouteKey = ({String origin, RobotSessionKey? robot});

/// The session of one [_RouteKey], while it opens and once it is open.
final class _Slot {
  final Future<_Route> opening;

  /// The session once it is open.
  _Route? route;

  /// The requests that picked this session and wait for it to open.
  int waiting = 0;

  /// Set by [TorCoordinatorTransport.closeRobotSessions]: the requests of this session fail instead of opening another one.
  bool dropped = false;

  _Slot(this.opening);

  /// Whether the session is open and no request uses it or is about to.
  bool get isIdle => waiting == 0 && (route?.isUnused ?? false);
}

/// One Tor session with its HTTP client, shared by the requests of one [_RouteKey].
final class _Route {
  final TorSession _session;
  final HttpClient _client;
  final Dio dio;
  int _users = 0;
  bool _retired = false;
  Future<void>? _closing;

  _Route(this._session, HttpClient client, Duration attemptTimeout)
    : _client = client,
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

  void acquire() => _users++;

  void release() {
    _users--;
    if (_retired && _users == 0) unawaited(close());
  }

  void retire() {
    _retired = true;
    if (_users == 0) unawaited(close());
  }

  Future<void> close() => _closing ??= _close();

  /// Closes the client, which also cancels a connection still being made, then the session.
  Future<void> _close() async {
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
    await TorCoordinatorTransport._closeSession(_session);
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
