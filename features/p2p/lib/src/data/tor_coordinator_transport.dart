import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bull_logger/bull_logger.dart';
import 'package:bull_tor/tor.dart';
import 'package:crypto/crypto.dart';
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

/// Retries of the connection to a Nostr relay after a connection failure, on a new Tor session: one, publishing the same events again being harmless (same ids).
const relayConnectRetries = 1;

/// The longest message of a relay that is read: an `OK` takes less than 200 characters; anything longer is ignored.
const maxRelayFrameLength = 4096;

/// The most bytes read from a relay's socket in one publication after the handshake, frame headers included: about 300 times what two `OK`s take. Beyond, the socket is destroyed and the publication fails (review of #158).
///
/// It bounds memory too: `dart:io` assembles a message whole before it delivers it, so the bytes are counted as they come off the socket, before any assembly; what is held at most is this bound plus one read of the socket, after the handshake's head, which `dart:io` bounds at 1 MiB (`_headerTotalSizeLimit` of its HTTP parser).
const maxRelayBytes = 64 * 1024;

/// The most messages read from a relay in one publication: two `OK`s are expected, and a relay may add a few notices. Beyond, the publication fails.
const maxRelayFrames = 64;

/// Time one read of a relay on a session of its own may take in total ([TorCoordinatorTransport.readOnOwnSession], #81): the Tor session, the websocket and the relay's whole answer.
///
/// [torConnectDeadline], the time one connection through Tor is given (66 seconds: `torConnectBudget`, 60 seconds, plus 10 %): on cold installs a first onion contact took up to 34 seconds, as measured in the comment of `torConnectBudget`, and a relay answers a request for a few events within a second or two once connected. A read is not tried again on a new session: the caller reads again at a later opening of the app.
final relayReadDeadline = torConnectDeadline;

/// The most events one read keeps, every event of the read's subscriptions counted: what one call of `GarageRecoveryNote.latestNote` looks at, which is what one coordinator's relay of the reference answers at most for the two requests of a note (500 each). Past it the read stops, incomplete.
const maxRelayReadEvents = GarageRecoveryNote.maxEvents;

/// The longest message of a relay a read looks at: the longest event `GarageRecoveryNote.latestNote` reads, with room for the message around it (`["EVENT","<subscription id>",…]`); a longer message is ignored, but counted.
const maxRelayReadFrameLength = GarageRecoveryNote.maxEventLength + 256;

/// The most messages one read takes from a relay: [maxRelayReadEvents] events, an `EOSE` or a `CLOSED` per subscription, and room for a few notices. Past it the read stops, incomplete.
const maxRelayReadFrames = maxRelayReadEvents + 64;

/// The most bytes one read takes from a relay's socket after the handshake, counted as for a publication ([maxRelayBytes]): a note is 1,701 bytes, so a thousand of them take less than 2 MiB. Past it the socket is destroyed and the read stops, incomplete; it bounds the memory a hostile relay costs.
const maxRelayReadBytes = 8 * 1024 * 1024;

/// Tor sessions of their own that relay calls may hold at once ([TorCoordinatorTransport.readOnOwnSession], [TorCoordinatorTransport.publishOnOwnSession]), apart from [maxRobotSessions]: one per coordinator relay of the network with the most (six on mainnet), so that a note is read from, or written to, every relay at once. A call beyond waits for a place within its own deadline, the first come first served, and gives [NostrRelayBusy] or an empty read when none frees in time.
const maxOwnRelaySessions = 6;

/// Places for robot Tor sessions, all coordinators together: one per coordinator and robot, so a few robots on every coordinator of a network.
///
/// A session holds a place from the moment it starts to open until it is closed, the sessions replaced after a connection failure included while a request still uses them.
/// A session nobody uses is closed to make room for a new one, the least recently used first.
/// It bounds places, not the sessions of the embedded Tor: a session given up after [torSessionCloseTimeout], and one whose opening was given up but that opens after all, exist there without a place until they end.
const maxRobotSessions = 32;

/// Places among [maxRobotSessions] that the robot sessions of one coordinator may hold together, so that the robots of all the other coordinators together always keep the other eight.
///
/// Without it, a coordinator that holds the connections of its robots, two places per robot, takes every place once sixteen robots are sent to it, and has the idle sessions of the other coordinators closed to make room.
/// Beyond it, a new session of that coordinator only takes the place of one of its own sessions, one that is closing or else the least recently used one that no request uses, and fails with [CoordinatorTransportBusy] when there is none: no session of another coordinator is closed for it.
/// Twenty-four is twelve robots with both of their sessions on one coordinator, far more than a person trades with at once; a user who has more robots there gets their idle sessions recycled, the least recently used first, as at [maxRobotSessions].
const maxRobotSessionsPerCoordinator = 24;

/// Places one robot may hold on one coordinator, among [maxRobotSessions]: the session its requests use, and one more that a connection failure replaced while a request still uses it, or that is closing.
///
/// Without it, a coordinator that drops some connections and holds the others makes every request of one robot keep a session of its own, and takes every place from the robots of the other coordinators.
/// It bounds places, not Tor sessions: the place of a session that is closing may be handed over to a new session, of this robot or of another, and then counts for that one, so the robot may have a third session in the embedded Tor until that one has closed; and a session given up after [torSessionCloseTimeout] no longer counts at all.
/// At two, a robot that already has two places never reaches the code that closes the unused session of another robot: write that rule down there before raising this number.
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

/// The most characters the header names and values of one request may have all together.
///
/// Twice [maxHeaderLength], so that the longest header allowed still goes through on its own, while a request with many long headers, which the RoboSats API never sends, fails before any session instead of after three.
const maxTotalHeaderLength = 32 * 1024;

/// The [CoordinatorTransport] of the app: every request goes through the embedded Tor.
///
/// Sessions: one Tor session per coordinator origin for the anonymous requests, and one more per robot for the requests made for it ([CoordinatorRequest.robot]).
/// A session, with its own HTTP client, so its own connections and circuits, is opened at the first request that needs it, shared by the requests of the same origin and robot while it works, and replaced by a new session after a connection failure.
/// So a coordinator, or anyone watching one, sees nothing that ties a robot to another robot, to the same robot on another coordinator, or to the anonymous reads of this device.
/// Robot sessions are bounded by [maxRobotSessions] places, whatever their coordinator, and a session that is opening, open or closing holds its place until it is closed, or given up as said below: beyond the bound the least recently used session that no request is using is closed first, and the new session opens only once that one is closed.
/// One robot has at most [maxSessionsPerRobotAndCoordinator] of them on one coordinator, and the robots of one coordinator at most [maxRobotSessionsPerCoordinator] together, so a coordinator takes no more places than twice the robots this device sent to it, and never the eight places that the robots of all the other coordinators share, whatever it does with their connections.
/// When no place can be had, because every session is in use, because the robot already has its two on that coordinator and neither is closing, because the robots of that coordinator have their [maxRobotSessionsPerCoordinator] and none of those sessions is closing or unused, or because the session whose place was taken did not close within [torSessionCloseTimeout], the request fails with [CoordinatorTransportBusy], a retry after a connection failure included.
/// [CoordinatorTransportBusy] is given for nothing else, and says that the request may be sent again later, not that the coordinator works: the places go to the requests in flight, so a coordinator that holds or drops the connections of its robots uses up their places, up to the limits above (see [CoordinatorTransportBusy] for what a caller does).
/// The opening of a session is given [coordinatorRequestDeadline]: an opening that has not completed by then is given up and gives its place back, the requests waiting for it fail with [CoordinatorUnreachable], and a session that opens after all is closed unused.
/// [closeRobotSessions] closes the sessions of one robot, [closeSessions] closes them all, the sessions a connection failure replaced while a request still used them included: the requests still running fail, and the next request opens new sessions.
/// A session still opening is no longer waited for: it gives its place back shortly after the close has returned, or once the session whose place it took has closed, and it is closed unused as soon as it opens.
/// So a request sent in the very instant a close returns may still find those places taken and fail with [CoordinatorTransportBusy].
/// Both complete even when a Tor session never finishes closing: such a session is given up after [torSessionCloseTimeout].
/// Neither is a lock: a request started after [closeRobotSessions] was called, the second request of a `fetchRobot` that follows error 7004 included, opens a new session of that robot.
/// The transport cannot tell such a request from the next request of the robot, which must go through, so a caller that gives up a robot lets its calls end, or drops them, before it closes its sessions.
/// The session such a request leaves is the most recently used one, so it is the last that the bound closes to make room, not the first.
///
/// Guarantees of the port contract:
/// - [send] always completes, with an [Ok] or an [Err], within [coordinatorRequestDeadline]: a timer answers [CoordinatorTimedOut] when it passes, whatever the request is waiting for (Tor, the session, the connection, a body sent a byte at a time), and cancels the attempt in progress;
/// - the body is read as a stream and the request is cancelled as soon as it exceeds [CoordinatorRequest.maxResponseBytes], or at once when the announced `Content-Length` does;
/// - redirects are never followed: a `3xx` answer is returned as it is;
/// - header names are given in lowercase;
/// - only `http` URLs to a `.onion` host, without user information, are sent: anything else fails with [CoordinatorTransportFailed] before a session is opened;
/// - a header is sent only when its name is an HTTP token, its value printable ASCII, and neither is longer than [maxHeaderLength], and the headers of a request have at most [maxTotalHeaderLength] characters together: anything else fails the same way;
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
/// Nostr relays ([publish], #94): a relay is the coordinator's own origin (`ws://<onion>/relay/`), so its websocket goes through the robot's session to that origin, the one its requests use, with the same `HttpClient`, through its SOCKS connection factory, and a handshake of this transport's own: no redirect followed, no extension offered or accepted (so no compression), the accept key checked; then the bytes read are counted before `dart:io` assembles a message, at most [maxRelayBytes] and [maxRelayFrames] messages, beyond which the socket is destroyed (security review of #158).
/// [publish] always completes within [coordinatorRequestDeadline] too, with a [NostrRelayOutcome]; a connection failure replaces the session and is retried [relayConnectRetries] time; messages longer than [maxRelayFrameLength] and binary ones are ignored; only the outcome's fixed label is logged, never the relay, the robot, an event id or a relay's text.
///
/// Relay calls on a session of their own ([OwnSessionNostrRelayTransport], the recovery note of a Garage Key, #81): each opens a new Tor session, with its own HTTP client, for that call only, outside the places of the robots and the sessions of the anonymous requests, and closes it when the call ends, so that nothing ties the call to a robot, to the books, or to another such call; at most [maxOwnRelaySessions] at once, a call beyond waiting for a place within its deadline. The websocket is made as for [publish], with the same handshake and the same counting of the bytes; a publication is bounded by [coordinatorRequestDeadline], a read by [relayReadDeadline], in events by [maxRelayReadEvents], in messages by [maxRelayReadFrames], in bytes by [maxRelayReadBytes]. Neither is tried again on a new session. [closeSessions] ends them too.
///
/// `User-Agent`: none is sent, whatever the request headers say (decision of 10/11/2026).
/// Its absence is the same for every Troc user, so it singles none of them out, and Troc does not pretend to be the official client.
/// `Accept-Encoding` is `identity` for every request, where `dart:io` would ask for `gzip`, and a body is never decompressed: the size cap counts the bytes that arrive, so a small compressed body cannot inflate in memory.
final class TorCoordinatorTransport
    implements
        CoordinatorTransport,
        CoordinatorSessionsPort,
        NostrRelayTransport,
        OwnSessionNostrRelayTransport {
  final OpenTorSession _openSession;
  final CreateTorHttpClient _createHttpClient;
  final Duration _deadline;
  final Duration _attemptTimeout;
  final Duration _closeTimeout;
  final bool Function(String host) _acceptsHost;
  final int _placesPerCoordinator;
  final Duration _readDeadline;
  final int _ownPlaces;

  /// The relay calls on a session of their own that hold a place, opening, open or closing: at most [_ownPlaces].
  int _ownInUse = 0;

  /// The relay calls waiting for a place on a session of their own, the first come first served.
  final List<Completer<bool>> _ownWaiting = [];

  /// The sessions of their own of the relay calls running, with their clients: [closeSessions] closes them.
  final Set<_OwnSession> _ownSessions = {};

  /// Starts the timer that answers a relay's publication when its deadline passes: [Timer.new], or a late one in a test, which shows that nothing inside the publication waits for it to know the deadline has passed (review of #158).
  final Timer Function(Duration duration, void Function() callback)
  _publicationTimer;

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

  /// The types a `GET` threw that the support log already holds a line for, since this transport (one for the app) was built: a fault that made every read throw would otherwise write a line per read.
  final Set<Type> _getThrowsSaid = {};

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
  /// [placesPerCoordinator] replaces [maxRobotSessionsPerCoordinator], so that the tests of [maxRobotSessions] can put every place on one loopback server.
  /// [readDeadline] replaces [relayReadDeadline], [ownPlaces] replaces [maxOwnRelaySessions].
  @visibleForTesting
  TorCoordinatorTransport.withSeams({
    required this._openSession,
    required this._createHttpClient,
    Duration? deadline,
    Duration? attemptTimeout,
    Duration? closeTimeout,
    bool Function(String host)? acceptsHost,
    int? placesPerCoordinator,
    Timer Function(Duration duration, void Function() callback)?
    publicationTimer,
    Duration? readDeadline,
    int? ownPlaces,
  }) : _publicationTimer = publicationTimer ?? Timer.new,
       _readDeadline = readDeadline ?? relayReadDeadline,
       _ownPlaces = ownPlaces ?? maxOwnRelaySessions,
       _deadline = deadline ?? coordinatorRequestDeadline,
       _attemptTimeout = attemptTimeout ?? torConnectDeadline,
       _closeTimeout = closeTimeout ?? torSessionCloseTimeout,
       _acceptsHost = acceptsHost ?? _isOnion,
       _placesPerCoordinator =
           placesPerCoordinator ?? maxRobotSessionsPerCoordinator;

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
        _logAction(request, 'timed out at the deadline');
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
        _logThrown(request, error);
      },
    );
    return completer.future;
  }

  @override
  Future<void> closeSessions() async {
    _log(() => 'P2P coordinator sessions closed (all)');
    _epoch++;
    // A session still opening is no longer waited for, and is closed as soon as it is open.
    for (final slot in _slots.values) {
      slot.drop();
    }
    _slots.clear();
    // Every open session, the ones a connection failure replaced included: each leaves [_live] once it is closed.
    await Future.wait([
      ...List.of(_live).map((route) => route.close()),
      // The relay calls on a session of their own end with their session.
      ...List.of(_ownSessions).map((own) => own.close()),
    ]);
  }

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async {
    // Never which robot: a log line never ties a robot to anything.
    _log(() => 'P2P coordinator sessions closed (one robot)');
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

  /// Publishes the events of [message] on [relay] through a Tor session of [robot], then closes the websocket: see the class doc.
  @override
  Future<NostrRelayOutcome> publish(
    Uri relay,
    NostrRelayPublication message, {
    required RobotSessionKey robot,
  }) {
    final completer = Completer<NostrRelayOutcome>();
    final deadline = _Deadline(_deadline);
    final timer = _publicationTimer(_deadline, () {
      deadline.expire();
      if (!completer.isCompleted) {
        completer.complete(const NostrRelayTimedOut());
      }
    });
    _publishOnRelay(relay, message, robot, deadline).then(
      (outcome) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(outcome);
      },
      onError: (Object error, StackTrace trace) {
        timer.cancel();
        if (completer.isCompleted) {
          Zone.current.handleUncaughtError(error, trace);
        } else if (error is Exception) {
          completer.complete(const NostrRelayFailed());
        } else {
          completer.completeError(error, trace);
        }
      },
    );
    return completer.future.then((outcome) {
      // The fixed label only: the relay, the robot, the event ids and the message never go to a log (#94, decision D3).
      if (outcome is! NostrRelayAccepted) {
        log.info('P2P Nostr chat publication: ${outcome.label}');
      }
      return outcome;
    });
  }

  /// Publishes the events of [message] on [relay] through a Tor session of its own, opened for this publication and closed after it: see the class doc.
  @override
  Future<NostrRelayOutcome> publishOnOwnSession(
    Uri relay,
    NostrRelayPublication message,
  ) => _ownSessionCall<NostrRelayOutcome>(
    relay,
    _deadline,
    timedOut: const NostrRelayTimedOut(),
    failed: const NostrRelayFailed(),
    busy: const NostrRelayBusy(),
    unreachable: const NostrRelayUnreachable(),
    // The fixed label only: the relay, the event ids and the message never go to a log.
    logLine: (outcome) => outcome is NostrRelayAccepted
        ? null
        : 'P2P Nostr note publication: ${outcome.label}',
    work: (client, deadline) async {
      switch (await _upgradeRelay(client, relay, deadline, maxRelayBytes)) {
        case _RelayUpgraded(:final socket):
          return switch (await _publishOn(socket, message, deadline)) {
            _RelayAnswered(:final outcome) => outcome,
            _RelayConnectFailed() => const NostrRelayUnreachable(),
          };
        case _RelayNotUpgraded(attempt: _RelayAnswered(:final outcome)):
          return outcome;
        case _RelayNotUpgraded(attempt: _RelayConnectFailed()):
          return deadline.passed
              ? const NostrRelayTimedOut()
              : const NostrRelayUnreachable();
      }
    },
  );

  /// Reads from [relay] the events of [filters] through a Tor session of its own, opened for this read and closed after it: see the class doc.
  ///
  /// The events received when the read stops short (its deadline, a bound, the relay closing) are given with the read marked incomplete.
  @override
  Future<NostrRelayRead> readOnOwnSession(
    Uri relay,
    List<NostrRelayFilter> filters,
  ) {
    if (filters.isEmpty) {
      return Future.value(const NostrRelayRead.none('noFilter'));
    }
    return _ownSessionCall<NostrRelayRead>(
      relay,
      _readDeadline,
      // The read answers by itself when its deadline passes, with what it received: this answer is for a read that has not reached the relay by then.
      grace: _readGrace,
      timedOut: const NostrRelayRead.none('timedOut'),
      failed: const NostrRelayRead.none('failed'),
      busy: const NostrRelayRead.none('busy'),
      unreachable: const NostrRelayRead.none('unreachable'),
      // The fixed label only: the relay, the filters and the events never go to a log.
      logLine: (read) =>
          read.complete ? null : 'P2P Nostr relay read: ${read.label}',
      work: (client, deadline) async {
        switch (await _upgradeRelay(
          client,
          relay,
          deadline,
          maxRelayReadBytes,
        )) {
          case _RelayUpgraded(:final socket):
            return _readOn(socket, filters, deadline);
          case _RelayNotUpgraded(attempt: _RelayAnswered(:final outcome)):
            return NostrRelayRead.none(outcome.label);
          case _RelayNotUpgraded(attempt: _RelayConnectFailed()):
            return NostrRelayRead.none(
              deadline.passed ? 'timedOut' : 'unreachable',
            );
        }
      },
    );
  }

  /// How long after its deadline a read's own answer is still awaited before the call answers « timed out » without it: the read answers at its deadline with what it received, and this is the time for that answer to come out.
  static const _readGrace = Duration(seconds: 2);

  /// One relay call on a Tor session of its own, answered [timedOut] once [total] and [grace] have passed whatever it waits for, [failed] for an [Exception], and logged by [logLine], which gives `null` for nothing to log.
  Future<T> _ownSessionCall<T>(
    Uri relay,
    Duration total, {
    Duration grace = Duration.zero,
    required T timedOut,
    required T failed,
    required T busy,
    required T unreachable,
    required String? Function(T outcome) logLine,
    required Future<T> Function(HttpClient client, _Deadline deadline) work,
  }) {
    final completer = Completer<T>();
    final deadline = _Deadline(total);
    final timer = _publicationTimer(total + grace, () {
      deadline.expire();
      if (!completer.isCompleted) completer.complete(timedOut);
    });
    _runOwnSession<T>(
      relay,
      deadline,
      timedOut: timedOut,
      failed: failed,
      busy: busy,
      unreachable: unreachable,
      work: work,
    ).then(
      (outcome) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(outcome);
      },
      onError: (Object error, StackTrace trace) {
        timer.cancel();
        if (completer.isCompleted) {
          Zone.current.handleUncaughtError(error, trace);
        } else if (error is Exception) {
          completer.complete(failed);
        } else {
          completer.completeError(error, trace);
        }
      },
    );
    return completer.future.then((outcome) {
      if (logLine(outcome) case final line?) log.info(line);
      return outcome;
    });
  }

  /// Takes a place among [maxOwnRelaySessions], opens a Tor session and its client for this call alone, runs [work] on that client, and closes them: the place is given back once the session is closed, or given up after [torSessionCloseTimeout].
  ///
  /// The answer does not wait for the session to close.
  Future<T> _runOwnSession<T>(
    Uri relay,
    _Deadline deadline, {
    required T timedOut,
    required T failed,
    required T busy,
    required T unreachable,
    required Future<T> Function(HttpClient client, _Deadline deadline) work,
  }) async {
    // The relay of a coordinator, `getRelayUrl` of the reference: checked here as for [publish].
    if (!_isRelayUrl(relay)) return failed;
    final epoch = _epoch;
    if (!await _takeOwnPlace(deadline)) {
      return deadline.passed ? timedOut : busy;
    }
    TorSession? session;
    _OwnSession? own;
    try {
      if (epoch != _epoch) return failed;
      try {
        session = await _openOwn(deadline);
      } on Exception {
        // Tor did not start, or gave no session: there is no circuit to the relay.
        return unreachable;
      }
      if (session == null) return deadline.passed ? timedOut : unreachable;
      final HttpClient client;
      try {
        client = _createHttpClient(session.endpoint);
      } on Exception {
        return failed;
      }
      client
        ..userAgent = null
        ..autoUncompress = false;
      final opened = own = _OwnSession(session, client, _closeSession);
      _ownSessions.add(opened);
      if (epoch != _epoch) return failed;
      return await work(client, deadline);
    } finally {
      final closing = switch ((own, session)) {
        (final opened?, _) => opened.close(),
        (null, final opened?) => _closeSession(opened),
        (null, null) => Future.value(true),
      };
      unawaited(
        closing.whenComplete(() {
          _ownSessions.remove(own);
          _giveOwnPlaceBack();
        }),
      );
    }
  }

  /// Whether [relay] is the relay of a coordinator, as `getRelayUrl` of the reference writes it, at a host the transport accepts.
  bool _isRelayUrl(Uri relay) =>
      relay.isScheme('ws') &&
      relay.host.isNotEmpty &&
      relay.userInfo.isEmpty &&
      relay.path == '/relay/' &&
      !relay.hasQuery &&
      !relay.hasFragment &&
      _acceptsHost(relay.host);

  /// A place among [_ownPlaces] for a relay call, waited for at most until [deadline] passes: `false` when none freed in time.
  Future<bool> _takeOwnPlace(_Deadline deadline) async {
    if (_ownInUse < _ownPlaces && _ownWaiting.isEmpty) {
      _ownInUse++;
      return true;
    }
    final waiter = Completer<bool>();
    _ownWaiting.add(waiter);
    final timer = Timer(deadline.left, () {
      if (_ownWaiting.remove(waiter)) waiter.complete(false);
    });
    final taken = await waiter.future;
    timer.cancel();
    return taken;
  }

  /// Gives the place of a relay call back, to the first call waiting for one if any.
  void _giveOwnPlaceBack() {
    if (_ownWaiting.isNotEmpty) {
      // Handed over: the count stays.
      _ownWaiting.removeAt(0).complete(true);
      return;
    }
    _ownInUse--;
  }

  /// Asks Tor for a session for one relay call, and waits for it at most until [deadline] passes: `null` when it stopped waiting. A session Tor gives after that is closed at once, unused.
  Future<TorSession?> _openOwn(_Deadline deadline) {
    final pending = _openSession();
    final result = Completer<TorSession?>();
    final timer = Timer(deadline.left, () {
      if (!result.isCompleted) result.complete(null);
    });
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

  /// One read on [socket]: a `REQ` for each of [filters], each under its own subscription id; the events of those subscriptions kept until each has its `EOSE` or `CLOSED`, a bound is reached, the relay closes, or [deadline] passes; then a `CLOSE` for each, and the socket closed.
  Future<NostrRelayRead> _readOn(
    WebSocket socket,
    List<NostrRelayFilter> filters,
    _Deadline deadline,
  ) async {
    final ids = <String>[];
    for (final filter in filters) {
      String id;
      do {
        id = '${filter.subscriptionLabel}_${_subscriptionSuffix()}';
      } while (ids.contains(id));
      ids.add(id);
    }
    final pending = {...ids};
    final events = <String>[];
    var frames = 0;
    var closedByRelay = false;
    final done = Completer<NostrRelayRead>();
    void finish({required bool complete, required String label}) {
      if (!done.isCompleted) {
        done.complete(
          NostrRelayRead(events: events, complete: complete, label: label),
        );
      }
    }

    final subscription = socket.listen(
      (Object? frame) {
        if (done.isCompleted) return;
        if (++frames > maxRelayReadFrames) {
          finish(complete: false, label: 'tooManyMessages');
          return;
        }
        // Binary messages and long ones are ignored: an event the note reader would read is shorter.
        if (frame is! String || frame.length > maxRelayReadFrameLength) return;
        final Object? message;
        try {
          message = jsonDecode(frame);
        } on FormatException {
          return;
        }
        // Only the messages of this read's subscriptions: a relay's notice, or a message for another subscription, is ignored.
        if (message is! List<Object?> ||
            message.length < 2 ||
            !ids.contains(message[1])) {
          return;
        }
        final id = message[1];
        switch (message[0]) {
          case 'EVENT' when message.length >= 3:
            final event = message[2];
            if (event is! Map<String, Object?>) return;
            // A thousand events are kept, and an answer that ends there is whole (500 per request, the reference relay's bound); one more stops the read, incomplete (review of #302).
            if (events.length >= maxRelayReadEvents) {
              finish(complete: false, label: 'tooManyEvents');
              return;
            }
            events.add(jsonEncode(event));
          case 'EOSE':
            pending.remove(id);
            if (pending.isEmpty) {
              finish(
                complete: !closedByRelay,
                label: closedByRelay ? 'closedByRelay' : 'answered',
              );
            }
          case 'CLOSED':
            if (pending.remove(id)) closedByRelay = true;
            if (pending.isEmpty) {
              finish(complete: false, label: 'closedByRelay');
            }
        }
      },
      // Closed by the relay, or broken, before every subscription ended.
      onError: (Object _) => finish(complete: false, label: 'broken'),
      onDone: () => finish(complete: false, label: 'closed'),
      cancelOnError: true,
    );
    deadline.watchSocket(socket);
    try {
      for (final (index, filter) in filters.indexed) {
        socket.add('["REQ",${jsonEncode(ids[index])},${filter.toJson()}]');
      }
      final read = await done.future.timeout(
        deadline.left,
        onTimeout: () =>
            NostrRelayRead(events: events, complete: false, label: 'timedOut'),
      );
      // The subscriptions are closed, as the reference does (`CLOSE`), on a socket still open.
      if (socket.readyState == WebSocket.open) {
        for (final id in ids) {
          socket.add('["CLOSE",${jsonEncode(id)}]');
        }
      }
      return read;
    } finally {
      deadline.forgetSocket(socket);
      await subscription.cancel();
      // Not awaited: the read is answered at once, and the session's client is closed after it anyway.
      unawaited(_closeRelaySocket(socket));
    }
  }

  /// A few random characters for a subscription id, as `Math.random().toString(36).substring(7)` gives the reference's: they tie nothing, but keep two subscriptions apart.
  static String _subscriptionSuffix() => String.fromCharCodes([
    for (var i = 0; i < 6; i++)
      '0123456789abcdefghijklmnopqrstuvwxyz'.codeUnitAt(
        _handshakeRandom.nextInt(36),
      ),
  ]);

  /// The places of the relay calls on a session of their own that are taken, and the calls waiting for one, for tests.
  @visibleForTesting
  ({int inUse, int waiting, int open}) get ownSessionsForTesting => (
    inUse: _ownInUse,
    waiting: _ownWaiting.length,
    open: _ownSessions.length,
  );

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
      _logAction(request, 'refused before sending (url)');
      return const Err(CoordinatorTransportFailed());
    }
    // A credential on an anonymous session would tie that session, and the reads of the book, to a robot.
    // Only `Authorization` is looked at, the one place a robot credential travels in today: the chat websocket will carry the token hash in a query parameter (`token_sha256_hex`), and this guard must be extended to it, and to any other credential, when it arrives.
    if (request.robot == null &&
        request.headers.keys.any(
          (name) => name.toLowerCase() == HttpHeaders.authorizationHeader,
        )) {
      _logAction(request, 'refused before sending (credential on anonymous)');
      return const Err(CoordinatorTransportFailed());
    }
    // Checked before any session opens: `dart:io` would refuse a header it finds invalid with an exception that quotes its value, and a header of megabytes would cost three sessions before it failed.
    if (!_areSendable(request.headers)) {
      _logAction(request, 'refused before sending (headers)');
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

  Future<NostrRelayOutcome> _publishOnRelay(
    Uri relay,
    NostrRelayPublication message,
    RobotSessionKey robot,
    _Deadline deadline,
  ) async {
    // The relay of a coordinator, `getRelayUrl` of the reference: checked here as a request URL is.
    if (!relay.isScheme('ws') ||
        relay.host.isEmpty ||
        relay.userInfo.isNotEmpty ||
        relay.path != '/relay/' ||
        relay.hasQuery ||
        relay.hasFragment ||
        !_acceptsHost(relay.host)) {
      return const NostrRelayFailed();
    }
    final origin = Uri(
      scheme: 'http',
      host: relay.host,
      port: relay.hasPort ? relay.port : null,
    ).origin;
    final requests = _robotRequests.putIfAbsent(robot, _RobotRequests.new);
    requests.running++;
    try {
      return await _runOnRelay(
        (origin: origin, robot: robot),
        relay,
        message,
        deadline,
        requests,
      );
    } finally {
      requests.running--;
      if (requests.running == 0 && identical(_robotRequests[robot], requests)) {
        _robotRequests.remove(robot);
      }
    }
  }

  Future<NostrRelayOutcome> _runOnRelay(
    _RouteKey key,
    Uri relay,
    NostrRelayPublication message,
    _Deadline deadline,
    _RobotRequests requests,
  ) async {
    final epoch = _epoch;
    final generation = requests.generation;
    bool closed() => epoch != _epoch || generation != requests.generation;
    for (var attempt = 0; ; attempt++) {
      if (deadline.passed) return const NostrRelayTimedOut();
      if (closed()) return const NostrRelayFailed();
      final slot = _slotFor(key);
      if (slot == null) return const NostrRelayBusy();
      final _Route route;
      slot.waiting++;
      try {
        route = await slot.opening;
      } on _RouteException catch (exception) {
        return switch (exception.failure) {
          CoordinatorTransportBusy() => const NostrRelayBusy(),
          CoordinatorUnreachable() => const NostrRelayUnreachable(),
          CoordinatorTimedOut() => const NostrRelayTimedOut(),
          _ => const NostrRelayFailed(),
        };
      } finally {
        slot.waiting--;
      }
      if (closed()) return const NostrRelayFailed();
      if (deadline.passed) return const NostrRelayTimedOut();
      // Given up since this publication picked it: the callback of a timer that retires the session can run between the pick above and this line (no microtask runs between two timers of one turn of the event loop), and its client is then closed, which `openUrl` answers with an [Error]. It is never used: another session is asked for, and this turn of the loop is no attempt (independent review of #222, B1).
      if (route.isGivenUp) {
        attempt--;
        continue;
      }

      route.acquire();
      final _RelayAttempt outcome;
      try {
        outcome = await _relayAttempt(route, relay, message, deadline);
      } finally {
        route.release();
      }
      switch (outcome) {
        case _RelayAnswered(:final outcome):
          return outcome;
        case _RelayConnectFailed(:final reason):
          // Given up whatever the deadline: its client is closed with it, which cancels a connection still being made.
          _retire(key, slot, route);
          // Never a new session once the deadline has passed (review of #158).
          if (deadline.passed) return const NostrRelayTimedOut();
          if (attempt >= relayConnectRetries) {
            return const NostrRelayUnreachable();
          }
          // The reason only, as for a request: the relay and the robot never go to a log.
          log.info(
            'P2P Nostr relay connection failed (${reason.name}), retrying on a new Tor session',
          );
      }
    }
  }

  /// One websocket to [relay] on [route]: connect, send the events in order, wait for an `OK` to each, close.
  Future<_RelayAttempt> _relayAttempt(
    _Route route,
    Uri relay,
    NostrRelayPublication message,
    _Deadline deadline,
  ) async {
    switch (await _upgradeRelay(route.client, relay, deadline, maxRelayBytes)) {
      case _RelayUpgraded(:final socket):
        return _publishOn(socket, message, deadline);
      case _RelayNotUpgraded(:final attempt):
        return attempt;
    }
  }

  /// A websocket to [relay] through [client], whose incoming bytes after the handshake are counted up to [maxBytes]; or what the attempt gave when there is none.
  Future<_RelayUpgrade> _upgradeRelay(
    HttpClient client,
    Uri relay,
    _Deadline deadline,
    int maxBytes,
  ) async {
    // The handshake is this transport's own (RFC 6455, § 4.1), on the session's client, so that no redirect is ever followed, no extension or subprotocol is accepted, compression included (a small compressed message could inflate in memory), and the bytes that come after it are counted before `dart:io` assembles a message (reviews of #158).
    // Its head is bounded by `dart:io`, at 1 MiB; each of its steps falls under the shorter of an attempt and what is left of the publication's deadline, so that none outlasts the deadline.
    // Whatever fails between the request and the end of the checks, the connection is destroyed in the `finally`: no socket is left open with the session.
    final key = base64.encode(
      List<int>.generate(16, (_) => _handshakeRandom.nextInt(256)),
    );
    // What is left of the deadline is rounded up past the next whole millisecond: a `Timer` counts in whole milliseconds, so that one set to what is left could fire a fraction of a millisecond before the deadline's own clock says it has passed, and a connection given up at that instant was taken for one to try again on a new Tor session (#196).
    Duration budget() {
      final left = deadline.left;
      if (left >= _attemptTimeout) return _attemptTimeout;
      return Duration(milliseconds: left.inMilliseconds + 1);
    }

    HttpClientRequest? request;
    Socket? detached;
    var upgradedOk = false;
    final Socket upgraded;
    try {
      final opened = await client
          .openUrl(
            'GET',
            Uri(
              scheme: 'http',
              host: relay.host,
              port: relay.hasPort ? relay.port : null,
              path: relay.path,
            ),
          )
          .timeout(budget());
      request = opened;
      opened
        ..followRedirects = false
        ..maxRedirects = 0
        ..persistentConnection = false;
      opened.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Key', key)
        ..set('Sec-WebSocket-Version', '13');
      final response = await opened.close().timeout(budget());
      // Taken off the client in every case, so that an answer that is not an upgrade, a redirect among them, is dropped with its connection and never followed.
      final socket = await response.detachSocket().timeout(budget());
      detached = socket;
      if (_isWebSocketUpgrade(response, key) case final refused?) {
        return _RelayNotUpgraded(_RelayAnswered(refused));
      }
      // The deadline passed while the websocket connected: nothing is written, and the socket is destroyed in the `finally`, inside this future, so that no late write or close can fail outside it.
      if (deadline.passed) {
        return const _RelayNotUpgraded(_RelayAnswered(NostrRelayTimedOut()));
      }
      upgradedOk = true;
      upgraded = socket;
    } on TimeoutException {
      // The session is given up in every case, so that closing its client cancels a connection still being made, which would otherwise stay open with the session (review of #158); no other attempt is made once the deadline has passed.
      return const _RelayNotUpgraded(
        _RelayConnectFailed(TorConnectFailure.timeout),
      );
    } on HttpException {
      // The service answered, not in HTTP: a new circuit would get the same answer, and the message of the exception, which quotes the address, is dropped here.
      return const _RelayNotUpgraded(_RelayAnswered(NostrRelayUnreachable()));
    } on Exception catch (exception) {
      return _RelayNotUpgraded(
        _RelayConnectFailed(TorHttpClientFactory.classify(exception)),
      );
    } finally {
      if (!upgradedOk) {
        if (detached != null) {
          detached.destroy();
        } else {
          request?.abort();
        }
      }
    }
    return _RelayUpgraded(
      WebSocket.fromUpgradedSocket(
        _CappedSocket(upgraded, maxBytes),
        serverSide: false,
        compression: CompressionOptions.compressionOff,
      ),
    );
  }

  /// Sends the events of [message] on [socket] in order, waits for an `OK` to each, and closes it.
  Future<_RelayAttempt> _publishOn(
    WebSocket socket,
    NostrRelayPublication message,
    _Deadline deadline,
  ) async {
    var frames = 0;
    final waiting = {...message.eventIds};
    var refused = false;
    final answered = Completer<NostrRelayOutcome>();
    void finish(NostrRelayOutcome outcome) {
      if (!answered.isCompleted) answered.complete(outcome);
    }

    final subscription = socket.listen(
      (Object? frame) {
        if (++frames > maxRelayFrames) {
          finish(const NostrRelayFailed());
          return;
        }
        // Binary frames and long ones are ignored: an `OK` is short text.
        if (frame is! String || frame.length > maxRelayFrameLength) return;
        final ok = NostrRelayOk.parse(frame);
        if (ok == null || !waiting.remove(ok.eventId)) return;
        if (!ok.accepted) refused = true;
        if (waiting.isEmpty) {
          finish(
            refused ? const NostrRelayRefused() : const NostrRelayAccepted(),
          );
        }
      },
      // Closed by the relay, or broken, before every event was answered.
      onError: (Object _) => finish(
        refused ? const NostrRelayRefused() : const NostrRelayFailed(),
      ),
      onDone: () => finish(
        refused ? const NostrRelayRefused() : const NostrRelayFailed(),
      ),
      cancelOnError: true,
    );
    deadline.watchSocket(socket);
    try {
      for (final frame in message.relayMessages) {
        socket.add(frame);
      }
      return _RelayAnswered(
        await answered.future.timeout(
          _attemptTimeout,
          onTimeout: () => const NostrRelayTimedOut(),
        ),
      );
    } finally {
      deadline.forgetSocket(socket);
      await subscription.cancel();
      await _closeRelaySocket(socket);
    }
  }

  /// Draws the handshake's `Sec-WebSocket-Key`, which RFC 6455 wants random, though it protects nothing secret.
  static final Random _handshakeRandom = Random.secure();

  /// The GUID of RFC 6455 that an accepted handshake hashes with the key.
  static const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  /// `null` when [response] accepts the websocket of [key] as RFC 6455 wants it, with no extension and no subprotocol, which this client asks for neither; otherwise what the publication gives: a redirect, never followed, is a failure, as is an extension or a subprotocol, and anything else that is not an upgrade means no relay there.
  ///
  /// Each header is read whole, a header given twice included, so that nothing here can throw (review of #158): `Upgrade` must be exactly the token `websocket`, `Connection` must hold the token `upgrade`, compared without case, and `Sec-WebSocket-Accept` must be given once, the value of [key].
  static NostrRelayOutcome? _isWebSocketUpgrade(
    HttpClientResponse response,
    String key,
  ) {
    final status = response.statusCode;
    if (status >= 300 && status < 400) return const NostrRelayFailed();
    if (status != HttpStatus.switchingProtocols) {
      return const NostrRelayUnreachable();
    }
    final headers = response.headers;
    List<String> tokensOf(String name) => [
      for (final value in headers[name] ?? const <String>[])
        for (final token in value.split(','))
          if (token.trim().isNotEmpty) token.trim().toLowerCase(),
    ];
    final upgrade = tokensOf(HttpHeaders.upgradeHeader);
    final accept = headers['Sec-WebSocket-Accept'] ?? const <String>[];
    final expected = base64.encode(
      sha1.convert(ascii.encode('$key$_webSocketGuid')).bytes,
    );
    if (upgrade.length != 1 ||
        upgrade.single != 'websocket' ||
        !tokensOf(HttpHeaders.connectionHeader).contains('upgrade') ||
        accept.length != 1 ||
        accept.single.trim() != expected) {
      return const NostrRelayUnreachable();
    }
    if (tokensOf('Sec-WebSocket-Extensions').isNotEmpty ||
        tokensOf('Sec-WebSocket-Protocol').isNotEmpty) {
      return const NostrRelayFailed();
    }
    return null;
  }

  Future<void> _closeRelaySocket(WebSocket socket) async {
    try {
      await socket.close(WebSocketStatus.normalClosure).timeout(_closeTimeout);
    } on Exception {
      // Closing is best effort: the session's client is closed with the session anyway.
    }
  }

  /// A line of the support log on the fate of [request], a request that acts (any method but `GET`, whose reads are too many to log): `P2P coordinator <method> <what>`, [what] being fixed words, Dart type names and names of enum values only, never the request's address, path, headers or body, nor an exception's message.
  static void _logAction(CoordinatorRequest request, String what) {
    if (request.method == CoordinatorHttpMethod.get) return;
    _log(() => 'P2P coordinator ${request.method.name} $what');
  }

  /// `P2P coordinator <method> threw (<type>)`, for what [send] caught of [request]'s exchange, an `Exception` it converts or an `Error` it passes on: the type only, never the message, which could quote a URL or a header.
  ///
  /// Every time for a request that acts; for a `GET`, once per type in the life of this transport ([_getThrowsSaid]).
  void _logThrown(CoordinatorRequest request, Object error) {
    final type = error.runtimeType;
    if (request.method == CoordinatorHttpMethod.get &&
        !_getThrowsSaid.add(type)) {
      return;
    }
    _log(() => 'P2P coordinator ${request.method.name} threw ($type)');
  }

  /// Writes [line] to the support log, and nothing else: whatever the log or the line throws is dropped.
  ///
  /// An `Error` is caught here on purpose: an exception to rule 11 of `AGENTS.md` bounded to the support log's lines, in this helper and in `ActionOutcomeLog`'s only (besides the request hook's, decided in the review of #158), since a line of diagnostics must never stop a request from ending, nor change how it ends.
  static void _log(String Function() line) {
    try {
      log.fine(line());
    } on Object catch (_) {
      // Dropped: see above.
    }
  }

  static final RegExp _headerName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final RegExp _headerValue = RegExp(r'^[\x20-\x7E]*$');

  /// Whether every header can be written on the wire as it is: a name that is an HTTP token, a value made of printable ASCII characters and spaces only, neither longer than [maxHeaderLength], and no more than [maxTotalHeaderLength] characters for all the names and values together.
  ///
  /// A token hash in base91, an armored key and a Nostr key need nothing else, so anything else is a mistake of the caller, and never something to send.
  static bool _areSendable(Map<String, String> headers) {
    var total = 0;
    for (final MapEntry(key: name, :value) in headers.entries) {
      total += name.length + value.length;
      if (name.length > maxHeaderLength ||
          value.length > maxHeaderLength ||
          total > maxTotalHeaderLength) {
        return false;
      }
    }
    return headers.entries.every(
      (header) =>
          _headerName.hasMatch(header.key) &&
          _headerValue.hasMatch(header.value),
    );
  }

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
    var handedOver = false;
    // Told once, when the body of the request starts to be written on a connection to the coordinator (#94, review of #158): never when nothing was written. Whatever the hook does stays out of the request.
    void written() {
      if (handedOver) return;
      handedOver = true;
      try {
        request.onSending?.call();
        // The hook is the caller's: a bug in it must neither stop this request nor reach the zone (decided in the review of #158).
      } on Object catch (error) {
        // The type only, never the message, which could quote a value.
        log.info('P2P coordinator request hook failed (${error.runtimeType})');
      }
    }

    final epoch = _epoch;
    final generation = requests?.generation;
    // Whether [closeSessions], or [closeRobotSessions] for the robot of this request, ran since the request started.
    bool closed() => epoch != _epoch || generation != requests?.generation;
    for (var attempt = 0; ; attempt++) {
      if (deadline.passed) {
        _logAction(request, 'timed out before an attempt');
        return const Err(CoordinatorTimedOut());
      }
      // After [closeSessions] or [closeRobotSessions], a request still running fails instead of opening a new session, whichever session it was on.
      if (closed()) {
        _logAction(request, 'stopped (sessions closed)');
        return const Err(CoordinatorTransportFailed());
      }
      final slot = _slotFor(key);
      // No place for a new session of this robot: nothing was sent on this attempt, and the same request may pass later.
      if (slot == null) {
        _logAction(request, 'busy (no place)');
        return const Err(CoordinatorTransportBusy());
      }
      final _Route route;
      // Counted from here, without a gap, so that the session is never closed as unused before this request takes it.
      slot.waiting++;
      try {
        route = await slot.opening;
      } on _RouteException catch (exception) {
        _logAction(
          request,
          'session not opened (${exception.failure.runtimeType})',
        );
        return Err(exception.failure);
      } finally {
        slot.waiting--;
      }
      if (closed()) {
        _logAction(request, 'stopped (sessions closed)');
        return const Err(CoordinatorTransportFailed());
      }
      if (deadline.passed) {
        _logAction(request, 'timed out before an attempt');
        return const Err(CoordinatorTimedOut());
      }

      route.acquire();
      final _Attempt outcome;
      try {
        outcome = await _attempt(route, request, deadline, written);
      } finally {
        route.release();
      }

      switch (outcome) {
        case _Answered(:final result):
          return result;
        case _Abandoned():
          _retire(key, slot, route);
          _logAction(request, 'abandoned at the deadline');
          return const Err(CoordinatorTimedOut());
        case _ConnectFailed(:final reason):
          _retire(key, slot, route);
          if (attempt >= retries || deadline.passed) {
            _logAction(request, 'connection failed (${reason.name})');
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
  /// A coordinator whose robots already have [maxRobotSessionsPerCoordinator] places gets no other either: its new session can only take the place of one of the robot sessions of that coordinator.
  /// Below that, a place is free while fewer than [maxRobotSessions] are taken, and once all are taken the place of any robot session can be taken.
  /// The place taken is the one of a session that is already closing, or else the one of the least recently used session that no request uses, which [_open] closes.
  /// The new session then opens only once that one is closed, [_Place.vacated], so there are never more than [maxRobotSessions] at a time.
  _Place? _placeForRobot(_RouteKey key) {
    if ((_placesOf[key] ?? 0) >= maxSessionsPerRobotAndCoordinator) {
      final own = _closingRoute((route) => route.key == key);
      return own == null ? null : _handOver(own, key);
    }
    if (_placesAt(key.origin) >= _placesPerCoordinator) {
      // No session of another coordinator is closed for this one: the robots of the others keep their places.
      return _vacate(key, (other) => other.origin == key.origin);
    }
    if (_robotPlaces < maxRobotSessions) {
      _takePlace(key);
      return (vacated: null);
    }
    return _vacate(key, (_) => true);
  }

  /// The place of a robot session whose key [accepts] lets through, for a new session of [key]: the place of a session that is closing, or else of the least recently used one that no request uses.
  _Place? _vacate(_RouteKey key, bool Function(_RouteKey other) accepts) {
    final closing = _closingRoute(
      (route) => route.key.robot != null && accepts(route.key),
    );
    if (closing != null) return _handOver(closing, key);
    for (final MapEntry(key: other, value: slot) in _slots.entries) {
      final route = slot.route;
      if (other.robot == null ||
          !accepts(other) ||
          route == null ||
          !slot.isIdle) {
        continue;
      }
      _slots.remove(other);
      return _handOver(route, key);
    }
    return null;
  }

  /// The places the robot sessions of [origin] hold.
  int _placesAt(String origin) {
    var places = 0;
    for (final MapEntry(:key, :value) in _placesOf.entries) {
      if (key.origin == origin) places += value;
    }
    return places;
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
      if (!vacatedClosed) {
        throw const _RouteException(CoordinatorTransportBusy());
      }
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
    void Function() written,
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
          // Called by Dio as the body is written on the connection it obtained: the moment `CoordinatorRequest.onSending` is for.
          onSendProgress: request.onSending == null
              ? null
              : (_, _) => written(),
        );
      } on DioException catch (exception) {
        // Its type and the type of its cause only: the exception's message quotes the URL.
        _logAction(
          request,
          'failed before headers (${exception.type.name}, ${exception.error.runtimeType})',
        );
        return _failureBeforeHeaders(exception);
      }

      final body = response.data;
      final statusCode = response.statusCode;
      if (body == null || statusCode == null) {
        cancel.cancel();
        _logAction(request, 'answer without status');
        return const _Answered(Err(CoordinatorTransportFailed()));
      }
      _logAction(request, 'answered (${statusCode ~/ 100}xx)');
      final headers = {
        for (final MapEntry(:key, :value) in response.headers.map.entries)
          key.toLowerCase(): value.join(', '),
      };
      final announced = int.tryParse(
        headers[HttpHeaders.contentLengthHeader] ?? '',
      );
      if (announced != null && announced > request.maxResponseBytes) {
        cancel.cancel();
        _logAction(request, 'answer too large');
        return const _Answered(Err(CoordinatorResponseTooLarge()));
      }
      final read = await _readCapped(
        body.stream,
        request.maxResponseBytes,
        cancel,
      );
      if (read case Err(:final failure)) {
        _logAction(request, 'body not read (${failure.runtimeType})');
      }
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

  /// The places of the robot sessions of each coordinator, from [placesOf].
  Map<String, int> get placesAt {
    final places = <String, int>{};
    for (final MapEntry(:key, :value) in placesOf.entries) {
      places[key.origin] = (places[key.origin] ?? 0) + value;
    }
    return places;
  }
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

  /// The client of the session, which a relay's websocket connects through.
  HttpClient get client => _client;
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

  /// Whether this session was retired or is closing: no request takes it any more.
  bool get isGivenUp => _retired || _closing != null;

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

/// What one websocket to a relay gave.
sealed class _RelayAttempt {
  const _RelayAttempt();
}

final class _RelayAnswered extends _RelayAttempt {
  final NostrRelayOutcome outcome;

  const _RelayAnswered(this.outcome);
}

final class _RelayConnectFailed extends _RelayAttempt {
  final TorConnectFailure reason;

  const _RelayConnectFailed(this.reason);
}

/// What the handshake of a websocket to a relay gave: the websocket, or how the attempt ended without one.
sealed class _RelayUpgrade {
  const _RelayUpgrade();
}

final class _RelayUpgraded extends _RelayUpgrade {
  final WebSocket socket;

  const _RelayUpgraded(this.socket);
}

final class _RelayNotUpgraded extends _RelayUpgrade {
  final _RelayAttempt attempt;

  const _RelayNotUpgraded(this.attempt);
}

/// Why no session could serve a request.
final class _RouteException implements Exception {
  final CoordinatorTransportFailure failure;

  const _RouteException(this.failure);
}

/// The overall deadline of one request: once it passes, it cancels the attempt in progress and allows no other.
final class _Deadline {
  /// The whole time of a relay's publication, measured from this deadline's creation: one instant, the single truth of [left] and [passed] (review of #158); `null` for a request, whose deadline only [expire] ends.
  final Duration? _total;
  final Stopwatch _clock = Stopwatch()..start();
  bool _expired = false;
  CancelToken? _current;
  WebSocket? _socket;

  _Deadline([this._total]);

  /// What is left of the publication's time: zero once it has passed.
  Duration get left {
    final total = _total;
    if (_expired || total == null) return Duration.zero;
    final left = total - _clock.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether the deadline has passed: [expire] ran, or, for a publication, nothing is [left].
  bool get passed => _expired || (_total != null && left == Duration.zero);

  void expire() {
    _expired = true;
    _current?.cancel();
    _socket?.close().ignore();
  }

  /// The websocket of a relay publication: closed when the deadline passes.
  void watchSocket(WebSocket socket) {
    _socket = socket;
    if (passed) socket.close().ignore();
  }

  void forgetSocket(WebSocket socket) {
    if (identical(_socket, socket)) _socket = null;
  }

  void watch(CancelToken cancel) {
    _current = cancel;
    if (passed) cancel.cancel();
  }

  void forget(CancelToken cancel) {
    if (identical(_current, cancel)) _current = null;
  }
}

/// The socket of a relay's websocket, whose incoming bytes are counted as they come off the socket, before `dart:io` assembles a message: past the bound, the socket is destroyed and the stream ends, which fails the publication (review of #158).
final class _CappedSocket extends StreamView<Uint8List> implements Socket {
  final Socket _inner;

  _CappedSocket._(this._inner, Stream<Uint8List> counted) : super(counted);

  factory _CappedSocket(Socket inner, int maxBytes) {
    var received = 0;
    var capped = false;
    final counted = inner.transform(
      StreamTransformer<Uint8List, Uint8List>.fromHandlers(
        handleData: (data, sink) {
          // Bytes already on their way when the socket was destroyed are dropped.
          if (capped) return;
          received += data.length;
          if (received > maxBytes) {
            capped = true;
            inner.destroy();
            // Ended here, once: the websocket sees its socket close, and the publication fails.
            sink.close();
            return;
          }
          sink.add(data);
        },
        handleDone: (sink) {
          if (!capped) sink.close();
        },
      ),
    );
    return _CappedSocket._(inner, counted);
  }

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get remotePort => _inner.remotePort;

  @override
  void destroy() => _inner.destroy();

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
}

/// The Tor session and HTTP client of one relay call on a session of its own.
final class _OwnSession {
  final TorSession _session;
  final HttpClient _client;
  final Future<bool> Function(TorSession session) _closeSession;
  Future<bool>? _closing;

  _OwnSession(this._session, this._client, this._closeSession);

  /// Closes the client, which cancels a connection still being made, then the session, once.
  Future<bool> close() => _closing ??= _close();

  Future<bool> _close() async {
    try {
      _client.close(force: true);
    } on Exception {
      // Closing is best effort: the session below is closed either way.
    }
    return _closeSession(_session);
  }
}
