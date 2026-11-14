import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/bolt11.dart';
import 'bolt11_test_invoice.dart';

/// What the next request of a kind meets instead of its answer.
enum ScriptedFault {
  /// The transport had no place for it: nothing reaches the coordinator (`CoordinatorTransportBusy`).
  busy,

  /// The coordinator could not be reached: nothing reaches it (`CoordinatorUnreachable`).
  unreachable,

  /// No answer in time, and nothing done (`CoordinatorTimedOut`).
  timedOut,

  /// The coordinator acts on the request, and its answer is lost on the way back (`CoordinatorTimedOut`).
  answerLost,
}

/// The kinds of request the scripted coordinator answers, to aim a [ScriptedFault] at.
enum ScriptedRequest { info, book, robot, order, take, cancel }

/// One coordinator of the federation list and one order of its book, played for the tests of the trade use cases, as the reference backend at commit ff1998c answers them (`api/views.py`, `api/logics.py`; design note § 1, § 5): never a real coordinator, never money.
///
/// It answers `GET /api/info/`, `GET /api/book/`, `GET /api/robot/` (a first contact keeps the robot with the key pair it sent, a robot it does not know is error 7001), `GET /api/order/` as the order then stands for the robot that asks (3 injected for a live pre-take only, 1043 for a cancelled order, 1044 for a robot that is no participant of an order that is not public), and the `POST /api/order/` actions `take` (a pre-take with its bond invoice on a public order; on any other, the answer of the read, as the reference does, `api/views.py:595-596`) and `cancel` (guarded by `cancel_status` against the stored status, 1020 otherwise; free at the pre-take, the bond lost at 6 and 7, `api/logics.py:1005-1181`).
/// The test moves the order along by itself ([lockBond], [moveTo], [takenByAnother], [backToPublic], [cancelByMaker], [expire], [pause], [satoshisNow] for the market's price), refuses a take as the reference does ([refuseNextTake]: 409, 1011, 1012, 1045; a pre-taker's cancel gives its robot a penalty; a protected order wants its [password]), and says what a robot holds ([robotAnswerHas]); a paused order is shown to its participants only (1044 to anyone else, a take included); a [range] order takes the amount the take sends; time is [clock], and a pre-take ends at its deadline.
/// Every robot and invoice is made by the tests from fixed bytes; the invoices are added to [decoder].
final class ScriptedCoordinator implements CoordinatorTransport {
  /// The order's figures: 100 EUR (currency 2), 106,900 sats at the book's price, a premium of 2 %, a bond of 3 %, an escrow of 3 h.
  static const int bookSats = 106900;
  static const double bookAmount = 100;
  static const int bondPercent = 3;
  static const int escrowSeconds = 10800;

  /// The time to lock a taker bond: the sample's `EXP_TAKER_BOND_INVOICE` less what the first read takes.
  static const Duration preTakeTime = Duration(seconds: 190);

  final RobosatsNetwork network;
  final Coordinator coordinator;
  final int orderId;

  /// The order's type on the wire: 1, a sell order, which its taker buys; 0, a buy order.
  final int orderType;

  /// What `/api/info/` announces as the taker fee.
  final double takerFee;
  final DateTime Function() clock;

  /// Reads back every invoice this coordinator made.
  final Bolt11TestDecoder decoder = Bolt11TestDecoder();

  /// Every request received, in order.
  final List<CoordinatorRequest> requests = [];

  /// When set, every request waits for it before it is answered: a read in flight, as long as the test wants.
  Future<void>? hold;

  /// Runs as each request arrives, before it is answered: the test can move the order there, or stop the app (an `Error` thrown here reaches the caller of a read; the coordinator client turns one thrown on a `POST` into an outcome unknown).
  void Function(CoordinatorRequest request)? onRequest;

  /// Whether a take on a public order is answered with the order as it is, this robot not its taker, as the reference does on a take that did not happen (`api/views.py:595-596`).
  bool takesNotMade = false;

  /// Whether the order has a range, 50 to 200 EUR, its sats at the book's price given for the largest amount.
  final bool range;

  /// The password of a protected order: a take must send its SHA-256, or it is refused with 1045 (`api/views.py:531-596`).
  final String? password;

  /// The sats of the order's largest amount at the coordinator's price now: the market moves them (`Logics.satoshis_now`).
  int satoshisNow = bookSats;

  final Map<RobotSessionKey, Map<String, Object?>> _robotFields = {};
  final List<int> _takeRefusals = [];
  final Map<RobotSessionKey, DateTime> _penalties = {};
  final Map<RobotSessionKey, double> _chosen = {};
  int? _lastSatoshis;

  final Map<RobotSessionKey, RobotIdentity> _robots;
  final Map<RobotSessionKey, Map<String, Object?>> _kept = {};
  final Map<ScriptedRequest, List<ScriptedFault>> _faults = {};
  final RobotHashId _maker;
  final DateTime _createdAt;

  /// The status the coordinator stores: 1 public, 4 cancelled, 5 expired, 6 and later the trade.
  int _status = 1;
  bool _paused = false;
  RobotSessionKey? _taker;
  final Map<RobotSessionKey, ({DateTime deadline, Bolt11TestInvoice bond})>
  _preTakes = {};
  DateTime? _deadline;
  int _invoiceSeed = 1;

  ScriptedCoordinator({
    required this.network,
    required Iterable<RobotIdentity> robots,
    required this.clock,
    String alias = 'temple',
    this.orderId = 42,
    this.orderType = 1,
    this.takerFee = 0.00175,
    this.range = false,
    this.password,
  }) : coordinator = switch (Federation.robosats.byAlias(alias)) {
         final found? => found,
         null => throw ArgumentError('no coordinator $alias'),
       },
       _robots = {for (final robot in robots) robot.sessionKey: robot},
       _maker = switch (RobotHashId.parse(
         '5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5',
       )) {
         Ok(:final value) => value,
         Err(:final failure) => throw StateError('$failure'),
       },
       _createdAt = clock().toUtc().subtract(const Duration(hours: 1));

  /// The next request of [kind] meets [fault] instead of its answer; several queue up in order.
  void failNext(ScriptedRequest kind, ScriptedFault fault) =>
      (_faults[kind] ??= []).add(fault);

  /// The status the coordinator stores now.
  int get status => _status;

  /// The next take is refused with error [code] before anything is done, as the reference refuses it: 1000 to 1003 (the robot has an active order, HTTP 409, `Logics.validate_already_maker_or_taker`), 1011 (an amount out of the range), 1012 (a penalty, HTTP 403, with the seconds in its message), 1045 (a wrong password).
  void refuseNextTake(int code) => _takeRefusals.add(code);

  /// What every answer about [robot] on `/api/robot/` also says: an active or last order id (`active_order_id`, `last_order_id`), as for a robot that already traded.
  void robotAnswerHas(RobotIdentity robot, Map<String, Object?> fields) =>
      _robotFields[robot.sessionKey] = fields;

  /// Whether [robot] has a penalty now, as after the cancel of its pre-take (`PENALTY_TIMEOUT`, 60 s, `api/logics.py:470-483`).
  bool hasPenalty(RobotIdentity robot) =>
      _penalties[robot.sessionKey]?.isAfter(clock().toUtc()) ?? false;

  /// Whether [robot] holds a live pre-take.
  bool holdsPreTake(RobotIdentity robot) {
    _expirePreTakes();
    return _preTakes.containsKey(robot.sessionKey);
  }

  /// The bond invoice of [robot]'s live pre-take.
  Bolt11TestInvoice? bondOf(RobotIdentity robot) =>
      _preTakes[robot.sessionKey]?.bond;

  /// The bond of [robot]'s pre-take locks: the order is taken, at 6, its sats frozen.
  void lockBond(RobotIdentity robot) {
    _expirePreTakes();
    if (!_preTakes.containsKey(robot.sessionKey) || _status != 1) {
      throw StateError('no live pre-take of that robot');
    }
    _preTakes.clear();
    _taker = robot.sessionKey;
    _lastSatoshis = _satsOf(_chosen[robot.sessionKey] ?? bookAmount);
    _status = 6;
    _deadline = clock().toUtc().add(const Duration(seconds: escrowSeconds));
  }

  /// Another robot's bond locks first: the order is taken by it, every other pre-take ends (1044 to them).
  void takenByAnother() {
    _preTakes.clear();
    _taker = null;
    _status = 6;
    _deadline = clock().toUtc().add(const Duration(seconds: escrowSeconds));
  }

  /// The trade moves to [status] (7 to 18), its taker kept.
  void moveTo(int status) {
    _status = status;
    _deadline = clock().toUtc().add(switch (status) {
      7 || 8 => const Duration(hours: 2),
      9 || 10 || 11 => const Duration(hours: 24),
      _ => const Duration(days: 100),
    });
  }

  /// The order is public again, its taker gone (a taker's cancel or timeout after its bond locked, its bond settled).
  void backToPublic() {
    _status = 1;
    _taker = null;
    _lastSatoshis = null;
    _preTakes.clear();
  }

  /// The maker cancels: 1043 to everyone.
  void cancelByMaker() {
    _status = 4;
    _preTakes.clear();
  }

  /// The kinds of the requests received, in order: what a test checks of what was sent.
  List<ScriptedRequest> get received => [
    for (final request in requests) _kindOf(request),
  ];

  /// The order expires (`expiry_reason` 3, « Invoice not submitted »).
  void expire() {
    _status = 5;
    _preTakes.clear();
  }

  /// The maker pauses the order, or resumes it: a paused order leaves the book, and its pre-takers get 1044 (`api/views.py:269-275`), their pre-takes kept.
  void pause({bool paused = true}) => _paused = paused;

  /// A hostile coordinator: the live pre-take of [robot] gets another bond invoice.
  void replaceBondInvoice(RobotIdentity robot) {
    final pre = _preTakes[robot.sessionKey];
    if (pre == null) throw StateError('no live pre-take of that robot');
    _preTakes[robot.sessionKey] = (
      deadline: pre.deadline,
      bond: _bondInvoice(),
    );
  }

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    onRequest?.call(request);
    if (hold case final hold?) await hold;
    _expirePreTakes();
    final kind = _kindOf(request);
    final queue = _faults[kind];
    final fault = queue == null || queue.isEmpty ? null : queue.removeAt(0);
    switch (fault) {
      case ScriptedFault.busy:
        return const Err(CoordinatorTransportBusy());
      case ScriptedFault.unreachable:
        return const Err(CoordinatorUnreachable());
      case ScriptedFault.timedOut:
        return const Err(CoordinatorTimedOut());
      case ScriptedFault.answerLost:
        _answer(kind, request);
        return const Err(CoordinatorTimedOut());
      case null:
        return Ok(_answer(kind, request));
    }
  }

  CoordinatorResponse _answer(
    ScriptedRequest kind,
    CoordinatorRequest request,
  ) {
    switch (kind) {
      case ScriptedRequest.info:
        return _json(200, _info());
      case ScriptedRequest.book:
        if (_status != 1 || _paused) {
          return _json(404, {'not_found': 'No orders found'});
        }
        return _json(200, [_bookOrder()]);
      case ScriptedRequest.robot:
        return _robot(request);
      case ScriptedRequest.order:
        return _orderFor(_robotOf(request));
      case ScriptedRequest.take:
        final robot = _robotOf(request);
        final body = jsonDecode(utf8.decode(request.body ?? const []));
        final fields = body is Map<String, Object?> ? body : const {};
        if (_takeRefusals.isNotEmpty) {
          final code = _takeRefusals.removeAt(0);
          return _json(switch (code) {
            1000 || 1001 || 1002 || 1003 => 409,
            1012 => 403,
            _ => 400,
          }, {
            'error_code': code,
            'bad_request': code == 1012
                ? 'You need to wait 60 seconds to take an order'
                : 'refused',
          });
        }
        if (hasPenalty(robot)) {
          return _json(403, {
            'error_code': 1012,
            'bad_request': 'You need to wait 60 seconds to take an order',
          });
        }
        if (password case final expected?) {
          final hashed = sha256.convert(utf8.encode(expected)).toString();
          if (fields['password'] != hashed) {
            return _json(400, {'error_code': 1045, 'bad_request': 'wrong'});
          }
        }
        final sent = fields['amount'];
        final amount = range && sent is num ? sent.toDouble() : bookAmount;
        if (range && (amount < 50 || amount > 200)) {
          return _json(400, {'error_code': 1011, 'bad_request': 'range'});
        }
        if (_status == 1 && !_paused && _taker == null && !takesNotMade) {
          _chosen.putIfAbsent(robot.sessionKey, () => amount);
          _preTakes.putIfAbsent(
            robot.sessionKey,
            () => (
              deadline: clock().toUtc().add(preTakeTime),
              bond: _bondInvoice(_satsOf(amount) * bondPercent ~/ 100),
            ),
          );
        }
        return _orderFor(robot);
      case ScriptedRequest.cancel:
        return _cancel(_robotOf(request), request);
    }
  }

  CoordinatorResponse _cancel(RobotIdentity robot, CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final guard = body is Map<String, Object?> ? body['cancel_status'] : null;
    final key = robot.sessionKey;
    final preTaker = _preTakes.containsKey(key) && _status == 1;
    final taker = _taker == key;
    if (!preTaker && !taker) return _orderFor(robot);
    // The guard is compared with the status the coordinator stores, 1 at a pre-take (`api/logics.py:1010-1015`).
    if (guard != _status) {
      return _json(400, {'error_code': 1020, 'bad_request': 'status moved'});
    }
    if (preTaker) {
      _preTakes.remove(key);
      // The pre-taker's cancel costs it a penalty (`kick_taker`, `api/logics.py:470-483`).
      _penalties[key] = clock().toUtc().add(const Duration(seconds: 60));
      return _orderFor(robot);
    }
    switch (_status) {
      case 6 || 7:
        // The taker's bond is settled, the order back in the book (`api/logics.py:1108-1130`).
        backToPublic();
        return _orderFor(robot);
      default:
        return _json(400, {'error_code': 1021, 'bad_request': 'not now'});
    }
  }

  RobotIdentity _robotOf(CoordinatorRequest request) {
    final key = request.robot;
    final robot = key == null ? null : _robots[key];
    if (robot == null) throw StateError('a request for no robot of the test');
    return robot;
  }

  CoordinatorResponse _robot(CoordinatorRequest request) {
    final robot = _robotOf(request);
    final parts = (request.headers['Authorization'] ?? '').split(' | ');
    if (parts.length == 4) {
      _kept.putIfAbsent(
        robot.sessionKey,
        () => {
          'public_key': pgpArmorFromWire(parts[1].substring('Public '.length)),
          'encrypted_private_key': pgpArmorFromWire(
            parts[2].substring('Private '.length),
          ),
          'nostr_pubkey': parts[3].substring('Nostr '.length),
        },
      );
    }
    final kept = _kept[robot.sessionKey];
    if (kept == null) {
      return _json(400, {'error_code': 7001, 'bad_request': 'unknown'});
    }
    return _json(200, {
      'nickname': robot.nickname,
      'hash_id': robot.hashId.hex,
      ...kept,
      ...?_robotFields[robot.sessionKey],
    });
  }

  CoordinatorResponse _orderFor(RobotIdentity robot) {
    final key = robot.sessionKey;
    if (_status == 4 || _status == 12) {
      return _json(400, {'error_code': 1043, 'bad_request': 'cancelled'});
    }
    final pre = _preTakes[key];
    if (_status == 1 && pre != null) {
      if (_paused) {
        return _json(403, {'error_code': 1044, 'bad_request': 'not yours'});
      }
      return _json(200, _orderJson(robot, 3, bond: pre.bond, at: pre.deadline));
    }
    // A paused order is shown to its participants only (`api/views.py:269-275`).
    if (_status == 1 && _paused) {
      return _json(403, {'error_code': 1044, 'bad_request': 'not yours'});
    }
    if (_status == 1) return _json(200, _orderJson(robot, 1));
    if (_taker != key) {
      return _json(403, {'error_code': 1044, 'bad_request': 'not yours'});
    }
    return _json(200, _orderJson(robot, _status));
  }

  void _expirePreTakes() {
    final now = clock().toUtc();
    _preTakes.removeWhere((_, pre) => !now.isBefore(pre.deadline));
  }

  static ScriptedRequest _kindOf(CoordinatorRequest request) {
    final action = request.method == CoordinatorHttpMethod.post
        ? _actionOf(request)
        : null;
    return switch (request.url.path) {
      '/api/info/' => ScriptedRequest.info,
      '/api/book/' => ScriptedRequest.book,
      '/api/robot/' => ScriptedRequest.robot,
      _ when action == 'take' => ScriptedRequest.take,
      _ when action == 'cancel' => ScriptedRequest.cancel,
      _ => ScriptedRequest.order,
    };
  }

  static String? _actionOf(CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    return body is Map<String, Object?> ? body['action'] as String? : null;
  }

  /// The sats of [amount] at the price now: those of the largest amount, in proportion for a range.
  int _satsOf(double amount) =>
      range ? (satoshisNow * amount / 200).truncate() : satoshisNow;

  Bolt11TestInvoice _bondInvoice([int? sats]) {
    final invoice = Bolt11TestInvoice(
      network: network == RobosatsNetwork.mainnet
          ? Bolt11Network.mainnet
          : Bolt11Network.testnet,
      sats: sats ?? satoshisNow * bondPercent ~/ 100,
      seed: _invoiceSeed++,
      createdAt: clock().toUtc(),
      expiry: const Duration(seconds: 200),
      description:
          "${coordinator.shortAlias} - Taking 'Order $orderId' Buying BTC for 100.0EUR - Taker bond",
    );
    decoder.add(invoice);
    return invoice;
  }

  int get _last => _lastSatoshis ?? satoshisNow;

  int get _fee => (_last * takerFee).round();

  Map<String, Object?> _info() => {
    'num_public_buy_orders': 0,
    'num_public_sell_orders': 1,
    'book_liquidity': bookSats,
    'active_robots_today': 3,
    'last_day_nonkyc_btc_premium': 2.0,
    'last_day_volume': 0.5,
    'lifetime_volume': 10.0,
    'lnd_version': 'v0.18.0',
    'cln_version': null,
    'robosats_running_commit_hash': 'ff1998c',
    'version': {'major': 0, 'minor': 8, 'patch': 8},
    'alternative_site': null,
    'alternative_name': null,
    'node_alias': coordinator.shortAlias,
    'node_id': coordinator.nodesPubkeys(network).first,
    'network': network.name,
    'maker_fee': 0.00025,
    'taker_fee': takerFee,
    'bond_size': 3.0,
    'min_order_size': 20000,
    'max_order_size': 5000000,
    'swap_enabled': false,
    'max_swap': 0,
  };

  Map<String, Object?> _bookOrder() => {
    'id': orderId,
    'created_at': _createdAt.toIso8601String(),
    'expires_at': _createdAt.add(const Duration(hours: 23)).toIso8601String(),
    'type': orderType,
    'currency': 2,
    'amount': range ? null : '100.00000000',
    'has_range': range,
    'min_amount': range ? '50.00000000' : null,
    'max_amount': range ? '200.00000000' : null,
    'payment_method': 'Revolut Instant SEPA',
    'is_explicit': false,
    'premium': '2.00',
    'satoshis': null,
    'maker': 7,
    'escrow_duration': escrowSeconds,
    'bond_size': '3.00',
    'latitude': null,
    'longitude': null,
    'maker_hash_id': _maker.hex,
    'satoshis_now': satoshisNow,
    'price': 93545.0,
    'maker_status': 'Active',
  };

  /// The order as `OrderView.get` describes it to [robot] at the shown [status] (`api/views.py:226-528`), with the JSON types the reference writes.
  Map<String, Object?> _orderJson(
    RobotIdentity robot,
    int status, {
    Bolt11TestInvoice? bond,
    DateTime? at,
  }) {
    final buyer = orderType == 1;
    final participant = status != 1;
    final taken = status >= 5;
    final deadline =
        at ??
        (status == 1
            ? _createdAt.add(const Duration(hours: 23))
            : _deadline ?? clock().toUtc().add(const Duration(days: 100)));
    final data = <String, Object?>{
      'id': orderId,
      'status': status,
      'created_at': _createdAt.toIso8601String(),
      'expires_at': deadline.toIso8601String(),
      'type': orderType,
      'currency': 2,
      'amount': !range
          ? '100.00000000'
          : switch (_chosen[robot.sessionKey]) {
              final chosen? when participant => chosen.toStringAsFixed(8),
              _ => null,
            },
      'has_range': range,
      'min_amount': range ? '50.00000000' : null,
      'max_amount': range ? '200.00000000' : null,
      'payment_method': 'Revolut Instant SEPA',
      'is_explicit': false,
      'premium': '2.00',
      'satoshis': null,
      'maker': 7,
      'taker': taken ? 8 : null,
      'escrow_duration': escrowSeconds,
      'bond_size': '3.00',
      'latitude': null,
      'longitude': null,
      'is_maker': false,
      'is_taker': participant,
      'is_participant': participant,
      'has_password': password != null,
      'total_secs_exp': deadline
          .difference(clock().toUtc())
          .inSeconds
          .clamp(0, 1 << 31),
      'maker_nick': _maker.nickname,
      'maker_hash_id': _maker.hex,
      'description': null,
      'maker_status': 'Active',
    };
    if (!participant) {
      data
        ..['price_now'] = 93545.0
        ..['premium_now'] = 2.0
        ..['satoshis_now'] = satoshisNow;
      return data;
    }
    final payout = _last - _fee;
    final escrow = _last + _fee;
    data
      ..['is_buyer'] = buyer
      ..['is_seller'] = !buyer
      ..['taker_nick'] = taken ? robot.nickname : 'None'
      ..['status_message'] = 'Some label'
      ..['is_fiat_sent'] = status == 10
      ..['is_disputed'] = status == 11 || status >= 16
      ..['ur_nick'] = robot.nickname
      // At the pre-take the participant's `satoshis_now` is the order's stale `last_satoshis`.
      ..['satoshis_now'] = taken ? _last : bookSats + 4321
      ..['maker_locked'] = true
      ..['taker_locked'] = taken
      ..['escrow_locked'] = status == 8 || status >= 9;
    if (taken) data['taker_hash_id'] = robot.hashId.hex;
    if ([6, 7, 8, 10, 11, 13, 14, 15].contains(status)) {
      data['trade_satoshis'] = buyer ? payout : escrow;
    }
    switch (status) {
      case 3:
        final invoice = bond ?? _bondInvoice();
        data
          ..['bond_invoice'] = invoice.text
          ..['bond_satoshis'] = invoice.facts.amount.value.toInt()
          ..['price_now'] = 93545.0
          ..['premium_now'] = 2.0;
      case 6 || 8 when buyer:
        data
          ..['invoice_amount'] = payout
          ..['swap_allowed'] = false
          ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
      case 9 || 10:
        data
          ..['asked_for_cancel'] = false
          ..['chat_last_index'] = 3;
      case 11:
        data['statement_submitted'] = false;
      case 5:
        data
          ..['public_duration'] = 86399
          ..['expiry_reason'] = 3
          ..['expiry_message'] = 'Invoice not submitted';
    }
    return data;
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );

  @override
  String toString() => 'ScriptedCoordinator(${coordinator.shortAlias})';
}
