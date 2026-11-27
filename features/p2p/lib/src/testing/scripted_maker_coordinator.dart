import 'dart:convert';
import 'dart:typed_data';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/bolt11.dart';
import 'bolt11_test_invoice.dart';
import 'scripted_coordinator.dart' show ScriptedFault;
import 'scripted_signatures.dart';

/// The kinds of request [ScriptedMakerCoordinator] answers, to aim a [ScriptedFault] at.
enum ScriptedMakerRequest {
  /// `GET /api/info/`.
  info,

  /// `GET /api/limits/`.
  limits,

  /// `GET /api/robot/`.
  robot,

  /// `POST /api/make/`.
  make,

  /// `GET /api/order/`.
  order,

  /// `POST /api/order/` with the action `cancel`.
  cancel,

  /// `POST /api/order/` with the action `update_invoice`: a maker buyer's payout (#182).
  payout,

  /// `POST /api/order/` with the action `confirm`: a maker buyer's « fiat sent » (#182).
  confirm,

  /// `POST /api/order/` with the action `pause`: the maker's pause or « Unpause Order » (#184).
  pause,
}

/// One order made by a robot of the test on [ScriptedMakerCoordinator], as the coordinator stores it.
final class ScriptedMadeOrder {
  final int id;

  /// The robot that made it.
  final RobotIdentity maker;

  /// The body of the make, as sent.
  final Map<String, Object?> body;

  final DateTime createdAt;
  DateTime expiresAt;

  /// The status the coordinator stores: 0 to 18, as `Order.Status` (`api/models/order.py:35-54`).
  int status = 0;

  /// The maker bond, made at the maker's first read at 0 (`api/views.py:373-379`), and given again after.
  Bolt11TestInvoice? bond;

  /// The order's sats at the coordinator's price, as `last_satoshis` (`api/logics.py:262-275`).
  int lastSatoshis;

  /// Why the order expired (`api/models/order.py:56-61`): 0 not taken, 1 maker bond not locked, 3 invoice not submitted.
  int? expiryReason;

  /// The current contract: its taker, its deadline (the lock's time and the escrow duration, `api/logics.py:1338-1340`), and for a range the amount taken.
  RobotIdentity? taker;
  DateTime? deadline;
  double? takenAmount;

  /// The maker seller's escrow invoice of the current contract.
  Bolt11TestInvoice? escrow;

  /// Whether a cancel returned the maker bond, or settled it.
  bool bondReturned = false;

  /// Whether the buyer confirmed the fiat sent (`order.is_fiat_sent`, `api/logics.py:1696`).
  bool fiatSent = false;

  /// The payment hash of the last payout invoice taken (#182): the same invoice is refused again (3002), as the reference compares a new invoice with `order.payout` only (`api/logics.py:877-879`), never with earlier ones.
  String? payoutHash;
  bool bondSettled = false;

  /// At 15, whether the failed payout invoice expired, so that a new one is asked (`invoice_expired`, `api/views.py:472-488`), #237.
  bool payoutExpired = false;

  ScriptedMadeOrder._({
    required this.id,
    required this.maker,
    required this.body,
    required this.createdAt,
    required this.expiresAt,
    required this.lastSatoshis,
  });

  /// The order's type on the wire: 0 a buy order, whose maker buys; 1 a sell order.
  int get type => body['type'] as int? ?? 0;

  bool get hasRange => body['has_range'] == true;

  int get publicSeconds => (body['public_duration'] as num?)?.toInt() ?? 86400;

  int get escrowSeconds => (body['escrow_duration'] as num?)?.toInt() ?? 10800;

  double get bondSize => (body['bond_size'] as num?)?.toDouble() ?? 3;

  double get premium => (body['premium'] as num?)?.toDouble() ?? 0;

  /// The order's largest amount: its amount, or its range's maximum.
  double get largestAmount =>
      ((hasRange ? body['max_amount'] : body['amount']) as num?)?.toDouble() ??
      0;
}

/// A coordinator of the federation list that the maker tests make orders on (#179), as the reference backend at commit ff1998c answers a maker (`api/views.py`, `api/logics.py`; design note `docs/design/phase-3-making-an-order.md` § 1.2 to § 1.7, § 5): never a real coordinator, never money.
///
/// It answers `GET /api/info/` (the maker fee [makerFee], the DevFund [devfund]), `GET /api/limits/` (the price of each currency in [prices], the bounds from 20,000 to 5,000,000 sats at it, `LimitView`, `api/views.py:1177-1197`), `GET /api/robot/` (a first contact keeps the robot with its key pair; its `active_order_id` while it is the maker of an order at 0 to 3, 6 to 11 or 16, else its `last_order_id`, `api/views.py:725-737`, `Logics.validate_already_maker_or_taker`, `api/logics.py:75-135`), `POST /api/make/` (`MakerView.post`, `api/views.py:90-216`: one active order per robot, 409 with 1000; the size at the price now, 1004 and 1005; the order saved at 0 with 300 s to lock its bond; answered `201` with `ListOrderSerializer`'s fields, `api/serializers.py:83-107`), `GET /api/order/` as the maker reads its order (the bond made at its first read at 0 and given again, error 1022 once past the 300 s then the order at 5 with reason 1, `api/logics.py:1252-1318`; 1043 once cancelled; 1044 to a robot that is no participant of an order that is not public), and the maker's `cancel` (`Logics.cancel_order`, `api/logics.py:1006-1181`: guarded by `cancel_status` against the stored status, 1020 otherwise; at 0 cancelled, at 1 or 2 cancelled with the bond returned, at 6 or 7 cancelled with the bond settled, answered with the short body of `api/views.py:604-615`; 1021 elsewhere).
/// It also answers the maker's `pause` (#184, `api/views.py:617-619`, `:686-695`, `Logics.pause_unpause_public_order`, `api/logics.py:1758-1783`): 1047 to a robot that is no participant, 1032 to one that is not the maker, 1033 at a status other than 1 or 2, else 1 → 2 or 2 → 1 and the maker's read of the order.
/// The test moves an order along by itself ([lockMakerBond], [take], [pause], [backToBook], [expire]), lets the cleaner run ([clean]), makes requests fail ([failNext], [landLate]) or be refused ([refuseNextMake], [pauseRefusals]), and plays a coordinator that lies ([makeAnswerChanges], [orderChanges], [robotAnswerHas], [cancelAnswersWholeOrder], [hideOrders], [pauseAnswerChanges], [pauseNotToggled]).
/// Every robot and invoice is made by the tests from fixed bytes; the invoices are added to [decoder].
final class ScriptedMakerCoordinator implements CoordinatorTransport {
  /// The coordinator's bounds of an order, in sats (`MIN_ORDER_SIZE`, `MAX_ORDER_SIZE`).
  static const int minOrderSats = 20000;
  static const int maxOrderSats = 5000000;

  /// The time to lock the maker bond (`EXP_MAKER_BOND_INVOICE`, `.env-sample:166`).
  static const Duration makerBondTime = Duration(seconds: 300);

  /// How long the cleaner takes to expire an order whose time ran out (`clean_orders.py:114-120`).
  static const Duration cleanerLoop = Duration(seconds: 5);

  final RobosatsNetwork network;
  final Coordinator coordinator;
  final DateTime Function() clock;

  /// Reads back every invoice this coordinator made.
  final Bolt11TestDecoder decoder = Bolt11TestDecoder();

  /// Every request received, in order.
  final List<CoordinatorRequest> requests = [];

  /// The coordinator's price of a bitcoin, by currency id: what `/api/limits/` gives, and what the orders' sats are computed at.
  final Map<int, double> prices = {2: 91711.15};

  /// What `/api/info/` announces as the maker fee, and its DevFund donation.
  double makerFee = 0.00025;
  double? devfund = 30;

  /// The version `/api/info/` announces (`version`, `api/views.py:1033`, `settings.VERSION`): 0.8.8 by default; an older one for the alert of a protected order (#189).
  ({int major, int minor, int patch}) version = (major: 0, minor: 8, patch: 8);

  /// The orders made, by number.
  final Map<int, ScriptedMadeOrder> orders = {};

  /// The number of the next order made.
  int nextOrderId;

  /// A hostile coordinator: what the `201` of the next makes says otherwise, a `null` value removing its key, in order.
  final List<Map<String, Object?>> makeAnswerChanges = [];

  /// A hostile coordinator: what every maker's read of an order says otherwise, by order number, a `null` value removing its key.
  final Map<int, Map<String, Object?>> orderChanges = {};

  /// A hostile coordinator: what every answer about a robot on `/api/robot/` says otherwise, a `null` value removing its key.
  final Map<RobotSessionKey, Map<String, Object?>> _robotChanges = {};

  /// A hostile coordinator: a cancel that ends the order is answered with the whole order at 4, rather than the reference's short body.
  bool cancelAnswersWholeOrder = false;

  /// A hostile coordinator, or a page of an intermediary: the maker's cancel is answered with the whole order unchanged, as if no cancel had come, and nothing is cancelled (security review of #179).
  bool cancelAnswersUnchanged = false;

  /// A hostile coordinator: it says the robot named no order, whatever it made.
  bool hideOrders = false;

  /// A hostile coordinator: what the answer of the next pauses says otherwise, a `null` value removing its key, in order (#184); the order itself is toggled as the reference does, unless [pauseNotToggled].
  final List<Map<String, Object?>> pauseAnswerChanges = [];

  /// A hostile coordinator: the maker's pause is answered as the reference answers it, the order read after the toggle, but nothing is toggled (#184).
  bool pauseNotToggled = false;

  /// A coordinator's refusals of the next pauses, in order, each answered `400` with its code before anything is toggled, as `api/views.py:686-689` answers 1032 and 1033 (#184): 1032 comes from the reference only to a taker, so for a maker it plays a coordinator that answers falsely.
  final List<int> pauseRefusals = [];

  /// A hostile coordinator: the next make saves its order, then answers with this refusal code, as if it had refused before making anything.
  int? refuseAfterMaking;

  /// Runs as each request arrives, before it is answered.
  void Function(CoordinatorRequest request)? onRequest;

  /// How many « confirm » requests a maker seller sent (#188): its « Confirm … received », sent once per press.
  int sellerConfirmations = 0;

  /// When set, every make waits for it once it arrived, before it is answered: a make in flight, as long as the test wants.
  Future<void>? holdMake;

  final Map<RobotSessionKey, RobotIdentity> _robots;
  final Map<RobotSessionKey, Map<String, Object?>> _kept = {};
  final Map<ScriptedMakerRequest, List<ScriptedFault>> _faults = {};
  final List<int?> _makeRefusals = [];
  final List<(ScriptedMakerRequest, CoordinatorRequest)> _late = [];
  int _invoiceSeed = 100;

  ScriptedMakerCoordinator({
    required this.network,
    required Iterable<RobotIdentity> robots,
    required this.clock,
    String alias = 'temple',
    this.nextOrderId = 42,
  }) : coordinator = switch (Federation.robosats.byAlias(alias)) {
         final found? => found,
         null => throw ArgumentError('no coordinator $alias'),
       },
       _robots = {for (final robot in robots) robot.sessionKey: robot};

  /// The next request of [kind] meets [fault] instead of its answer; several queue up in order.
  void failNext(ScriptedMakerRequest kind, ScriptedFault fault) =>
      (_faults[kind] ??= []).add(fault);

  /// The next make is refused before anything is made: an empty `400` (the serializer's) when [code] is `null`, otherwise that error code with the reference's HTTP status.
  void refuseNextMake(int? code) => _makeRefusals.add(code);

  /// The robot [robot] already exists on this coordinator with the key pair [publicKey] and [encryptedPrivateKey] (another device, or the official app with the same Garage Key, made it first): a read back before its first contact is error 7001 as for any robot this device never sent, and its first contact is answered with that pair, not the one it sent (`robosats/middleware.py:62-178`).
  void existsWithPair(
    RobotIdentity robot, {
    required String publicKey,
    required String encryptedPrivateKey,
    required String nostrPublicKey,
  }) => _presetPairs[robot.sessionKey] = {
    'public_key': publicKey,
    'encrypted_private_key': encryptedPrivateKey,
    'nostr_pubkey': nostrPublicKey,
  };

  final Map<RobotSessionKey, Map<String, Object?>> _presetPairs = {};

  /// A hostile coordinator: what every answer about [robot] also says, or says otherwise.
  void robotAnswerHas(RobotIdentity robot, Map<String, Object?> fields) =>
      _robotChanges[robot.sessionKey] = fields;

  /// The kinds of the requests received, in order.
  List<ScriptedMakerRequest> get received => [
    for (final request in requests) _kindOf(request),
  ];

  /// The order [id], which must exist.
  ScriptedMadeOrder order(int id) =>
      orders[id] ?? (throw StateError('no order $id'));

  /// The orders [robot] made, oldest first.
  List<ScriptedMadeOrder> ordersOf(RobotIdentity robot) => [
    for (final order in orders.values)
      if (order.maker.sessionKey == robot.sessionKey) order,
  ];

  /// A hostile coordinator invents an order made by [maker], at [status], with the body of [like] (an order of the test) or a make of 100 EUR, created at [createdAt] (now by default): no make was sent for it.
  ScriptedMadeOrder inventOrder(
    RobotIdentity maker, {
    int status = 0,
    ScriptedMadeOrder? like,
    DateTime? createdAt,
  }) {
    final now = clock().toUtc();
    final made = ScriptedMadeOrder._(
      id: nextOrderId++,
      maker: maker,
      body:
          like?.body ??
          const {
            'type': 0,
            'currency': 2,
            'amount': 100,
            'has_range': false,
            'min_amount': null,
            'max_amount': null,
            'payment_method': 'Revolut Instant SEPA',
            'is_explicit': false,
            'premium': 2,
            'satoshis': null,
            'public_duration': 86340,
            'escrow_duration': 10800,
            'bond_size': 3,
            'latitude': null,
            'longitude': null,
            'password': null,
            'description': null,
          },
      createdAt: createdAt ?? now,
      expiresAt: (createdAt ?? now).add(
        status == 0 ? makerBondTime : const Duration(seconds: 86340),
      ),
      lastSatoshis: 0,
    )..status = status;
    made.lastSatoshis = _satsOf(made, made.largestAmount);
    orders[made.id] = made;
    return made;
  }

  /// The requests held by [ScriptedFault.landsLate] reach the coordinator now, in order, and it acts on them; their answers are gone.
  void landLate() {
    final held = List.of(_late);
    _late.clear();
    for (final (kind, request) in held) {
      _answer(kind, request);
    }
  }

  /// The maker bond of order [id] locks: the invoice follower publishes the order (`follow_invoices.py:233-240`, `Logics.publish_order`, `api/logics.py:1205-1227`), its deadline the creation and the public duration.
  void lockMakerBond(int id) {
    final made = order(id);
    if (made.status != 0 || made.bond == null) {
      throw StateError('no maker bond to lock');
    }
    made
      ..status = 1
      ..expiresAt = made.createdAt.add(Duration(seconds: made.publicSeconds));
  }

  /// [taker]'s bond locks on public order [id]: a contract (`Logics.finalize_contract`, `api/logics.py:1321-1380`), its sats at the price now, its deadline the lock's time and the escrow duration, for a range the amount taken.
  void take(int id, RobotIdentity taker, {double? amount}) {
    final made = order(id);
    if (made.status != 1) throw StateError('not public');
    final now = clock().toUtc();
    made
      ..taker = taker
      ..takenAmount = made.hasRange ? amount ?? made.largestAmount : null
      ..lastSatoshis = _satsOf(made, made.takenAmount ?? made.largestAmount)
      ..status = 6
      ..deadline = now.add(Duration(seconds: made.escrowSeconds))
      ..expiresAt = now.add(Duration(seconds: made.escrowSeconds))
      ..escrow = null;
  }

  /// The maker pauses order [id], or resumes it (`Logics.pause_unpause_public_order`, `api/logics.py:1758-1783`): its deadline does not move.
  void pause(int id) {
    final made = order(id);
    made.status = switch (made.status) {
      1 => 2,
      2 => 1,
      _ => throw StateError('neither public nor paused'),
    };
  }

  /// The taker of order [id] cancelled or did not act: the order is public again with its first deadline (`Logics.publish_order`, `api/logics.py:1205-1227`).
  void backToBook(int id) {
    final made = order(id);
    made
      ..status = 1
      ..taker = null
      ..takenAmount = null
      ..escrow = null
      ..expiresAt = made.createdAt.add(Duration(seconds: made.publicSeconds));
  }

  /// Order [id] expires with [reason].
  void expire(int id, {int reason = 0}) {
    order(id)
      ..status = 5
      ..expiryReason = reason;
  }

  /// The cleaner's loop (`clean_orders.py:48-70`): every order at 0 whose 300 s ran out a loop ago expires, its bond invoice cancelled (`api/logics.py:329-338`).
  void clean() {
    final now = clock().toUtc();
    for (final made in orders.values) {
      if (made.status == 0 && !now.isBefore(made.expiresAt.add(cleanerLoop))) {
        made
          ..status = 5
          ..expiryReason = 1;
      }
    }
  }

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    onRequest?.call(request);
    final kind = _kindOf(request);
    if (kind == ScriptedMakerRequest.make) {
      if (holdMake case final hold?) await hold;
    }
    clean();
    final queue = _faults[kind];
    final fault = queue == null || queue.isEmpty ? null : queue.removeAt(0);
    if (fault != ScriptedFault.busy && fault != ScriptedFault.unreachable) {
      request.onSending?.call();
    }
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
      case ScriptedFault.landsLate:
        _late.add((kind, request));
        return const Err(CoordinatorTimedOut());
      case ScriptedFault.refused:
        return Ok(_json(403, {'error_code': 1047, 'bad_request': 'refused'}));
      case ScriptedFault.answerDelayed || ScriptedFault.servedLate:
        throw UnsupportedError('not played by the maker coordinator');
      case null:
        return Ok(_answer(kind, request));
    }
  }

  /// Whether the coordinator checks the signature of every request of a robot that changes a state, as one running the fix of GHSA-22q8-9ghc-jg3h does (RoboSats pull request 2955, head `0943c97`): before anything else, a body with no signature is refused with 1059, one whose signature does not verify with the key the robot gave at its first contact or signs another text with 1048, a make signed for another coordinator with 1061 and one whose time is more than 300 seconds from [clock] with 1060 ([scriptedSignatureRefusal]).
  ///
  /// `false` plays a coordinator not updated yet, at commit babf62e, which reads only the fields its serializers declare and ignores the signature.
  bool checksSignatures = true;

  CoordinatorResponse _answer(
    ScriptedMakerRequest kind,
    CoordinatorRequest request,
  ) => switch (_signatureRefused(request)) {
    final refused? => refused,
    null => _answerSigned(kind, request),
  };

  /// The refusal of the signature of [request] when [checksSignatures] and it is a `POST` of a robot, `null` otherwise: see [checksSignatures].
  CoordinatorResponse? _signatureRefused(CoordinatorRequest request) {
    if (!checksSignatures || request.method != CoordinatorHttpMethod.post) {
      return null;
    }
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final fields = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};
    final action = fields['action'];
    final orderId = int.tryParse(request.url.queryParameters['order_id'] ?? '');
    final ScriptedSignedText expected;
    switch (request.url.path) {
      case '/api/make/':
        expected = ScriptedTimedText('make', coordinator.shortAlias);
      case '/api/order/' when action is String && orderId != null:
        expected = ScriptedExactText(
          orderActionContent(action, orderId, coordinator.shortAlias),
        );
      default:
        return null;
    }
    final publicKey = _kept[_robotOf(request).sessionKey]?['public_key'];
    // A robot the coordinator does not know is refused by its authentication first (7001).
    if (publicKey is! String) return null;
    final code = scriptedSignatureRefusal(
      fields,
      publicKey: publicKey,
      expected: expected,
      now: clock(),
    );
    if (code == null) return null;
    return _json(400, {
      'error_code': code,
      'bad_request': scriptedSignatureMessage(code),
    });
  }

  CoordinatorResponse _answerSigned(
    ScriptedMakerRequest kind,
    CoordinatorRequest request,
  ) => switch (kind) {
    ScriptedMakerRequest.info => _json(200, _info()),
    ScriptedMakerRequest.limits => _json(200, _limits()),
    ScriptedMakerRequest.robot => _robot(request),
    ScriptedMakerRequest.make => _make(_robotOf(request), request),
    ScriptedMakerRequest.order => _read(_robotOf(request), request),
    ScriptedMakerRequest.cancel => _cancel(_robotOf(request), request),
    ScriptedMakerRequest.payout => _payout(_robotOf(request), request),
    ScriptedMakerRequest.confirm => _confirm(_robotOf(request), request),
    ScriptedMakerRequest.pause => _pause(_robotOf(request), request),
  };

  /// The maker's made order [request] names, if [robot] is its maker.
  ScriptedMadeOrder? _ownOrder(
    RobotIdentity robot,
    CoordinatorRequest request,
  ) {
    final id = int.tryParse(request.url.queryParameters['order_id'] ?? '');
    final made = id == null ? null : orders[id];
    if (made == null || made.maker.sessionKey != robot.sessionKey) return null;
    return made;
  }

  /// A maker buyer's payout (#182): `update_invoice` as the reference answers it (`api/views.py:617-649`, `Logics.update_invoice`, `api/logics.py:752-890`): the clear signature checked against the robot's kept public key and split as `verify_signed_message` splits it (`api/utils.py:628-648`), the invoice of exactly `invoice_amount` less the routing budget, at 6 (→ 7) or 8 (→ 9); a payment hash given before refused (3002).
  CoordinatorResponse _payout(RobotIdentity robot, CoordinatorRequest request) {
    final made = _ownOrder(robot, request);
    if (made == null) {
      return _json(403, {'error_code': 1047, 'bad_request': 'not yours'});
    }
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final fields = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};
    final signed = fields['invoice'];
    final publicKey = _kept[robot.sessionKey]?['public_key'];
    final verified = signed is String && publicKey is String
        ? switch (PgpPublicKey.parse(publicKey)) {
            Ok(:final value) => value.verifyCleartext(signed),
            Err(:final failure) => Err<String, PgpFailure>(failure),
          }
        : const Err<String, PgpFailure>(PgpArmorMalformed());
    if (signed is! String || verified is Err) {
      return _json(400, {
        'error_code': 1048,
        'bad_request': 'The PGP signed cleartext message is not valid.',
      });
    }
    const header = '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n';
    const footer = '-----BEGIN PGP SIGNATURE-----';
    final parts = signed.split(header);
    if (parts.length < 2) return _json(500, {'detail': 'IndexError'});
    final text = parts[1].split(footer).first.trim();
    if (made.type != 0) {
      return _json(400, {
        'error_code': 1017,
        'bad_request': 'Only the buyer of this order can provide it.',
      });
    }
    if (made.status != 6 &&
        made.status != 8 &&
        !(made.status == 15 && made.payoutExpired)) {
      return _json(400, {
        'error_code': 3001,
        'bad_invoice':
            'You can only submit an invoice after expiration or 3 failed attempts',
      });
    }
    final payout = _payoutOf(made);
    final ppm = fields['routing_budget_ppm'];
    final budget = ppm is int ? ppm : 0;
    final asked = (payout.toDouble() - payout.toDouble() * (budget / 1000000))
        .truncate();
    final facts = switch (decoder.decode(text)) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (facts == null) {
      return _json(400, {
        'bad_invoice': 'Does not look like a valid lightning invoice',
      });
    }
    if (facts.amount.value.toInt() != asked) {
      return _json(400, {
        'bad_invoice': 'The invoice provided is not for $asked Sats',
      });
    }
    if (made.payoutHash == facts.paymentHash) {
      return _json(400, {
        'error_code': 3002,
        'bad_invoice': 'You must submit a NEW invoice',
      });
    }
    made.payoutHash = facts.paymentHash;
    if (made.status == 6) {
      made.status = 7;
    } else if (made.status == 15) {
      // A new invoice after a failed payout: paid again from 13 (`Logics.move_state_updated_payout_method`, `api/logics.py:909-947`).
      made
        ..status = 13
        ..payoutExpired = false;
    } else {
      // Into the chat: its deadline set from now (`Logics.update_invoice`, `api/logics.py:909-947`, `FIAT_EXCHANGE_DURATION`, 24 h in `robosats/settings.py:310`).
      _toChat(made);
    }
    return _json(200, _orderJson(made, robot, isMaker: true));
  }

  /// A maker buyer's « fiat sent » (#182): `confirm` at 9 (→ 10), the step's deadline kept (`Logics.confirm_fiat`, `api/logics.py:1686-1735`); refused elsewhere (1029). A maker seller's « received » (#188): `confirm` at 10 settles the escrow, returns both bonds and pays the buyer, 13 (`:1701-1730`); at 9, before the buyer's « fiat sent », refused with 1027 (`:1702-1703`). Each `confirm` of a maker seller is counted ([sellerConfirmations]).
  CoordinatorResponse _confirm(
    RobotIdentity robot,
    CoordinatorRequest request,
  ) {
    final made = _ownOrder(robot, request);
    if (made == null) {
      return _json(403, {'error_code': 1047, 'bad_request': 'not yours'});
    }
    if (made.status != 9 && made.status != 10) {
      return _json(400, {
        'error_code': 1029,
        'bad_request': 'You cannot confirm the fiat payment at this stage',
      });
    }
    if (made.type != 0) {
      sellerConfirmations += 1;
      if (!made.fiatSent) {
        return _json(400, {
          'error_code': 1027,
          'bad_request':
              'You cannot confirm to have received the fiat before it is confirmed to be sent by the buyer.',
        });
      }
      made
        ..status = 13
        ..bondReturned = true;
      return _json(200, _orderJson(made, robot, isMaker: true));
    }
    made
      ..status = 10
      ..fiatSent = true;
    return _json(200, _orderJson(made, robot, isMaker: true));
  }

  /// The seller locks the escrow of order [id] (`Logics.update_status` on the escrow's lock, `api/logics.py:1469-1481`): 6 → 8, 7 → 9; the taker for a maker buyer (#182), the maker for a maker seller (#188: its escrow paid, from this wallet or another, which the test says here).
  void lockEscrow(int id) {
    final made = order(id);
    switch (made.status) {
      case 6:
        made.status = 8;
      case 7:
        _toChat(made);
      default:
        throw StateError('no escrow to lock at ${made.status}');
    }
  }

  /// [made] into the chat (9), its deadline the chat's from now (`api/logics.py:913-916`, `:927-930`, `:1475-1480`).
  void _toChat(ScriptedMadeOrder made) {
    made
      ..status = 9
      ..expiresAt = clock().toUtc().add(const Duration(hours: 24));
  }

  /// What a maker buyer receives, `invoice_amount`: `round(last_satoshis − last_satoshis × fee)`, a half to the even one as Python's `round` (`Logics.payout_amount`, `api/logics.py:650-669`).
  int _payoutOf(ScriptedMadeOrder made) =>
      _halfEven(made.lastSatoshis - made.lastSatoshis * makerFee);

  /// [value] rounded to the nearest whole number, a half to the even one, as Python's `round`.
  static int _halfEven(double value) {
    final floor = value.floorToDouble();
    final rest = value - floor;
    final whole = floor.toInt();
    if (rest > 0.5) return whole + 1;
    if (rest < 0.5) return whole;
    return whole.isEven ? whole : whole + 1;
  }

  /// The taker, the seller, confirms the fiat received at 10: the escrow settled, both bonds returned, the buyer's invoice being paid, 13 (`Logics.confirm_fiat`, `api/logics.py:1712-1730`, `pay_buyer`) (#182).
  void sellerConfirms(int id) {
    final made = order(id);
    if (made.status != 10) throw StateError('not at 10');
    made
      ..status = 13
      ..bondReturned = true;
  }

  /// The taker, the buyer of a maker seller's order, gives its payout invoice (#188, `Logics.update_invoice`, `api/logics.py:752-890`, then `move_state_updated_payout_method`, `:907-947`): 6 → 7 while the escrow is not locked, 8 → 9 (the chat, its deadline from now).
  void buyerGivesInvoice(int id) {
    final made = order(id);
    switch (made.status) {
      case 6:
        made.status = 7;
      case 8:
        _toChat(made);
      default:
        throw StateError('no payout to give at ${made.status}');
    }
  }

  /// The taker, the buyer of a maker seller's order, confirms the fiat sent at 9 (#188, `Logics.confirm_fiat`, `api/logics.py:1692-1699`): 10, `is_fiat_sent`.
  void buyerSentFiat(int id) {
    final made = order(id);
    if (made.status != 9) throw StateError('not at 9');
    made
      ..status = 10
      ..fiatSent = true;
  }

  /// The buyer's invoice could not be paid (#237): 13 → 15, the attempts made (`follow_invoices.py`, `api/logics.py`, the routing's failures); with [expired] the failed invoice expired, so that the coordinator asks a new invoice of the same `invoice_amount` (`api/views.py:472-488`), which takes the order back to 13 (`Logics.move_state_updated_payout_method`, `api/logics.py:909-947`).
  void failPayout(int id, {bool expired = true}) {
    final made = order(id);
    if (made.status != 13) throw StateError('not at 13');
    made
      ..status = 15
      ..payoutExpired = expired;
  }

  /// The buyer's invoice paid: the trade succeeded, 14 (`follow_invoices.py`, the payment's success) (#182).
  void buyerPaid(int id) {
    final made = order(id);
    if (made.status != 13) throw StateError('not at 13');
    made.status = 14;
  }

  CoordinatorResponse _make(RobotIdentity robot, CoordinatorRequest request) {
    if (_kept[robot.sessionKey] == null) {
      return _json(400, {'error_code': 7001, 'bad_request': 'unknown'});
    }
    if (_makeRefusals.isNotEmpty) {
      final code = _makeRefusals.removeAt(0);
      if (code == null) {
        return CoordinatorResponse(
          statusCode: 400,
          headers: const {},
          body: Uint8List(0),
        );
      }
      return _json(code >= 1000 && code <= 1003 ? 409 : 400, {
        'error_code': code,
        'bad_request': 'refused',
      });
    }
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    if (body is! Map<String, Object?>) {
      return CoordinatorResponse(
        statusCode: 400,
        headers: const {},
        body: Uint8List(0),
      );
    }
    // One active order per robot (`api/views.py:170-176`).
    if (_activeOf(robot) != null) {
      return _json(409, {'error_code': 1000, 'bad_request': 'active'});
    }
    final now = clock().toUtc();
    final made = ScriptedMadeOrder._(
      id: nextOrderId++,
      maker: robot,
      body: Map.unmodifiable(body),
      createdAt: now,
      expiresAt: now.add(makerBondTime),
      lastSatoshis: 0,
    );
    made.lastSatoshis = _satsOf(made, made.largestAmount);
    // The size at the price now (`Logics.validate_order_size`, `api/logics.py:138-177`), the range's minimum against the smallest size.
    final smallest = made.hasRange
        ? _satsOf(made, (body['min_amount'] as num?)?.toDouble() ?? 0)
        : made.lastSatoshis;
    if (made.lastSatoshis > maxOrderSats) {
      return _json(400, {'error_code': made.hasRange ? 1007 : 1004});
    }
    if (smallest < minOrderSats) {
      return _json(400, {'error_code': made.hasRange ? 1008 : 1005});
    }
    orders[made.id] = made;
    if (refuseAfterMaking case final code?) {
      refuseAfterMaking = null;
      return _json(400, {'error_code': code, 'bad_request': 'refused'});
    }
    final answer = <String, Object?>{
      'id': made.id,
      'status': 0,
      'created_at': made.createdAt.toIso8601String(),
      'expires_at': made.expiresAt.toIso8601String(),
      'type': made.type,
      'currency': body['currency'],
      'amount': _decimal(body['amount'], 8),
      'has_range': made.hasRange,
      'min_amount': _decimal(body['min_amount'], 8),
      'max_amount': _decimal(body['max_amount'], 8),
      'payment_method': body['payment_method'],
      'is_explicit': false,
      'premium': _decimal(body['premium'], 2),
      'satoshis': null,
      'maker': 7,
      'taker': null,
      'escrow_duration': made.escrowSeconds,
      'bond_size': _decimal(body['bond_size'], 2),
      // `ListOrderSerializer`'s texts of 6 decimals (`api/serializers.py:105-106`, `api/models/order.py:148-167`), #189.
      'latitude': _decimal(body['latitude'], 6),
      'longitude': _decimal(body['longitude'], 6),
    };
    if (makeAnswerChanges.isNotEmpty) {
      _apply(answer, makeAnswerChanges.removeAt(0));
    }
    return _json(201, answer);
  }

  /// `OrderView.get` for [robot] (`api/views.py:226-528`).
  CoordinatorResponse _read(RobotIdentity robot, CoordinatorRequest request) {
    final id = int.tryParse(request.url.queryParameters['order_id'] ?? '');
    final made = id == null ? null : orders[id];
    if (made == null) {
      return _json(404, {'bad_request': 'Invalid Order Id'});
    }
    if (made.status == 4 || made.status == 12) {
      return _json(400, {'error_code': 1043, 'bad_request': 'cancelled'});
    }
    final isMaker = made.maker.sessionKey == robot.sessionKey;
    if (!isMaker && made.status != 1) {
      return _json(403, {'error_code': 1044, 'bad_request': 'not yours'});
    }
    if (isMaker && made.status == 0) {
      // `Logics.gen_maker_hold_invoice` (`api/logics.py:1252-1318`): past its time the order expires and the read answers 1022; otherwise the bond, made once at the price now.
      if (made.expiresAt.isBefore(clock().toUtc())) {
        made
          ..status = 5
          ..expiryReason = 1;
        return _json(400, {
          'error_code': 1022,
          'bad_request':
              'Invoice expired. You did not confirm publishing the order in time. Make a new order.',
        });
      }
      if (made.bond == null) {
        made.lastSatoshis = _satsOf(made, made.largestAmount);
        made.bond = _invoice(
          made.lastSatoshis * made.bondSize ~/ 100,
          "${coordinator.shortAlias} - Publishing 'Order ${made.id}' - Maker bond",
          makerBondTime,
        );
      }
    }
    final data = _orderJson(made, robot, isMaker: isMaker);
    if (isMaker) {
      if (orderChanges[made.id] case final changes?) _apply(data, changes);
    }
    return _json(200, data);
  }

  /// The maker's cancel (`Logics.cancel_order`, `api/logics.py:1006-1181`, answered by `api/views.py:599-616`).
  CoordinatorResponse _cancel(RobotIdentity robot, CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final guard = body is Map<String, Object?> ? body['cancel_status'] : null;
    final id = int.tryParse(request.url.queryParameters['order_id'] ?? '');
    final made = id == null ? null : orders[id];
    if (made == null) return _json(404, {'bad_request': 'Invalid Order Id'});
    if (made.maker.sessionKey != robot.sessionKey) {
      return _json(403, {'error_code': 1047, 'bad_request': 'not yours'});
    }
    if (guard != null && guard != made.status) {
      return _json(400, {'error_code': 1020, 'bad_request': 'status moved'});
    }
    if (cancelAnswersUnchanged) {
      return _json(200, _orderJson(made, robot, isMaker: true));
    }
    switch (made.status) {
      case 0:
        made.status = 4;
      case 1 || 2:
        made
          ..bondReturned = true
          ..status = 4;
      case 6 || 7:
        made
          ..bondSettled = true
          ..status = 4;
      default:
        return _json(400, {'error_code': 1021, 'bad_request': 'not now'});
    }
    if (cancelAnswersWholeOrder) {
      return _json(200, _orderJson(made, robot, isMaker: true));
    }
    return _json(200, {
      'id': made.id,
      'status': made.status,
      'type': made.type,
      'expires_at': made.expiresAt.toIso8601String(),
      'bad_request': 'This order has been cancelled',
    });
  }

  /// The maker's pause, or « Unpause Order » (#184), as the reference answers it: `OrderView.take_update_confirm_dispute_cancel` with the action `pause` (`api/views.py:686-695`): a robot that is neither the maker nor the taker is refused with 1047 and `403` before the action (`:617-619`); then `Logics.pause_unpause_public_order` (`api/logics.py:1758-1783`): another robot than the maker 1032, 1 → 2, 2 → 1, any other status 1033, each refusal answered `400` (`api/views.py:688-689`); once toggled, the answer is the maker's read of the order (`return self.get(request)`, `:695`). The toggle moves no deadline (`Order.update_status`, `api/models/order.py:363-371`, writes the status only).
  CoordinatorResponse _pause(RobotIdentity robot, CoordinatorRequest request) {
    final id = int.tryParse(request.url.queryParameters['order_id'] ?? '');
    final made = id == null ? null : orders[id];
    if (made == null) return _json(404, {'bad_request': 'Invalid Order Id'});
    final isMaker = made.maker.sessionKey == robot.sessionKey;
    final isTaker = made.taker?.sessionKey == robot.sessionKey;
    if (!isMaker && !isTaker) {
      return _json(403, {
        'error_code': 1047,
        'bad_request': 'You are not a participant in this order',
      });
    }
    if (pauseRefusals.isNotEmpty) {
      final code = pauseRefusals.removeAt(0);
      return _json(400, {'error_code': code, 'bad_request': 'refused'});
    }
    if (!isMaker) {
      return _json(400, {
        'error_code': 1032,
        'bad_request': 'You cannot pause or unpause an order you did not make',
      });
    }
    if (made.status != 1 && made.status != 2) {
      return _json(400, {
        'error_code': 1033,
        'bad_request':
            'You can only pause/unpause an order that is either public or paused',
      });
    }
    if (!pauseNotToggled) made.status = made.status == 1 ? 2 : 1;
    final answer = _read(robot, request);
    if (pauseAnswerChanges.isEmpty || answer.statusCode != 200) return answer;
    final data = jsonDecode(utf8.decode(answer.body)) as Map<String, Object?>;
    _apply(data, pauseAnswerChanges.removeAt(0));
    return _json(200, data);
  }

  /// The order [made] as `OrderView.get` describes it to [robot], its maker when [isMaker], with the JSON types the reference writes.
  Map<String, Object?> _orderJson(
    ScriptedMadeOrder made,
    RobotIdentity robot, {
    required bool isMaker,
  }) {
    final now = clock().toUtc();
    final status = made.status;
    final buyer = made.type == 0;
    final taker = made.taker;
    final body = made.body;
    final protected = body['password'] != null;
    final data = <String, Object?>{
      'id': made.id,
      'status': status,
      'created_at': made.createdAt.toIso8601String(),
      'expires_at': made.expiresAt.toIso8601String(),
      'type': made.type,
      'currency': body['currency'],
      'amount': made.hasRange
          ? (taker == null ? null : made.takenAmount?.toStringAsFixed(8))
          : _decimal(body['amount'], 8),
      'has_range': made.hasRange,
      'min_amount': _decimal(body['min_amount'], 8),
      'max_amount': _decimal(body['max_amount'], 8),
      'payment_method': body['payment_method'],
      'is_explicit': false,
      'premium': _decimal(body['premium'], 2),
      'satoshis': null,
      'maker': 7,
      'taker': taker == null ? null : 8,
      'escrow_duration': made.escrowSeconds,
      'bond_size': _decimal(body['bond_size'], 2),
      // To a participant the stored `Decimal` as a JSON number (`api/views.py:320-321`); to another robot the serializer's text, removed with the description for a protected order (`:291-298`), #189.
      'latitude': isMaker
          ? _stored(body['latitude'])
          : protected
          ? null
          : _decimal(body['latitude'], 6),
      'longitude': isMaker
          ? _stored(body['longitude'])
          : protected
          ? null
          : _decimal(body['longitude'], 6),
      'is_maker': isMaker,
      'is_taker': false,
      'is_participant': isMaker,
      'has_password': body['password'] != null,
      'total_secs_exp': made.expiresAt
          .difference(now)
          .inSeconds
          .clamp(0, 1 << 31),
      'maker_nick': made.maker.nickname,
      'maker_hash_id': made.maker.hashId.hex,
      'description': !isMaker && protected ? null : body['description'],
      'maker_status': 'Active',
      if (taker != null) 'taker_status': 'Active',
    };
    if (!isMaker) {
      data
        ..['price_now'] = _priceOf(made)
        ..['premium_now'] = made.premium
        ..['satoshis_now'] = made.lastSatoshis;
      return data;
    }
    if (status >= 1 && status < 6) {
      data
        ..['price_now'] = _priceOf(made)
        ..['premium_now'] = made.premium;
    }
    final payout = _payoutOf(made);
    // `Logics.escrow_amount`: `round(last_satoshis + last_satoshis × fee)`, a half to the even one as Python's `round` (`api/logics.py:742-746`).
    final escrow = _halfEven(made.lastSatoshis + made.lastSatoshis * makerFee);
    data
      ..['is_buyer'] = buyer
      ..['is_seller'] = !buyer
      ..['taker_nick'] = taker?.nickname ?? 'None'
      ..['status_message'] = 'Some label'
      // `order.is_fiat_sent`: set by the buyer's « confirm » (`api/logics.py:1696`), cleared by « undo » only (`:1748`), so still set after 10 (#182).
      ..['is_fiat_sent'] = status == 10 || (made.fiatSent && status >= 11)
      ..['is_disputed'] = status == 11 || status >= 16
      ..['ur_nick'] = robot.nickname
      ..['satoshis_now'] = made.lastSatoshis
      // Whether each hold invoice is LOCKED now (`api/views.py:327-343`): the maker bond from the publication to the trade's end, returned or settled at 4, 5 and 11 to 18 (`Logics.return_bond`, `settle_bond`, `api/logics.py:1561-1600`; a dispute settles the escrow and both bonds, `:503-506`; the seller's « confirm » returns both bonds before paying the buyer, `:1724-1727`); the taker bond from the contract (6) to 10; the escrow from its lock (8, or 9 after 7) to 10 (#182).
      ..['maker_locked'] = const [1, 2, 3, 6, 7, 8, 9, 10].contains(status)
      ..['taker_locked'] = status >= 6 && status <= 10
      ..['escrow_locked'] = status >= 8 && status <= 10;
    if (taker != null) {
      data
        ..['taker_hash_id'] = taker.hashId.hex
        ..['taker_nostr_pubkey'] = 'None';
    }
    // Only while both bonds are LOCKED, at the statuses `api/views.py:346-361` lists (6, 7, 8, 10, 11, 12, 13, 14, 15, not 9): with the bonds locked only at 6, 7, 8 and 10 (above), never at 9, 11 to 15 (#182).
    if (const [6, 7, 8, 10].contains(status)) {
      data['trade_satoshis'] = buyer ? payout : escrow;
    }
    switch (status) {
      case 0:
        final bond = made.bond;
        if (bond != null) {
          data
            ..['bond_invoice'] = bond.text
            ..['bond_satoshis'] = bond.facts.amount.value.toInt();
        }
      case 6 || 7 when !buyer:
        final invoice = made.escrow ??= _invoice(
          escrow,
          "${coordinator.shortAlias} - Escrow amount for 'Order ${made.id}'",
          Duration(seconds: made.escrowSeconds),
        );
        data
          ..['escrow_invoice'] = invoice.text
          ..['escrow_satoshis'] = invoice.facts.amount.value.toInt();
      case 6 || 8 when buyer:
        data
          ..['invoice_amount'] = payout
          ..['swap_allowed'] = false
          ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
      // The chat's fields at 8 for the seller (the buyer's 8 is the payout's branch), 9 and 10 (`api/views.py:430-457`).
      case 8 || 9 || 10:
        data
          ..['asked_for_cancel'] = false
          ..['chat_last_index'] = 0;
      // A failed payout, to its receiver (`api/views.py:471-488`): the attempts, the next one, the reason, and once the invoice expired the amount of a new one, `Logics.payout_amount` as at 6 and 8 (#237).
      case 15 when buyer:
        data
          ..['retries'] = 3
          ..['next_retry_time'] = now.toIso8601String()
          // `LNPayment.FailureReason.NONRECO`'s label (`api/models/ln_payment.py`).
          ..['failure_reason'] = 'A non-recoverable error has occurred.';
        if (made.payoutExpired) {
          data
            ..['invoice_expired'] = true
            ..['trade_satoshis'] = payout;
        }
      case 5:
        final reason = made.expiryReason ?? 0;
        data
          ..['expiry_reason'] = reason
          ..['expiry_message'] = switch (reason) {
            1 => 'Maker bond not locked',
            3 => 'Invoice not submitted',
            _ => 'Expired not taken',
          };
    }
    // The renewal's fields (`api/views.py:490-498`); the trade summary of 13 to 15 (`Logics.summarize_trade`) is not played.
    if (const [5, 13, 14].contains(status) || (status == 15 && !buyer)) {
      data
        ..['public_duration'] = made.publicSeconds
        ..['bond_size'] = _decimal(body['bond_size'], 2);
    }
    return data;
  }

  CoordinatorResponse _robot(CoordinatorRequest request) {
    final robot = _robotOf(request);
    final parts = (request.headers['Authorization'] ?? '').split(' | ');
    if (parts.length == 4) {
      _kept.putIfAbsent(
        robot.sessionKey,
        () =>
            _presetPairs[robot.sessionKey] ??
            {
              'public_key': pgpArmorFromWire(
                parts[1].substring('Public '.length),
              ),
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
    final active = hideOrders ? null : _activeOf(robot);
    final made = ordersOf(robot);
    final data = <String, Object?>{
      'nickname': robot.nickname,
      'hash_id': robot.hashId.hex,
      ...kept,
      if (active != null) 'active_order_id': active.id,
      if (active == null && made.isNotEmpty && !hideOrders)
        'last_order_id': made.last.id,
    };
    if (_robotChanges[robot.sessionKey] case final changes?) {
      _apply(data, changes);
    }
    return _json(200, data);
  }

  /// The order [robot] is the maker of and still engaged in (`Logics.validate_already_maker_or_taker`, `api/logics.py:75-135`), if any.
  ScriptedMadeOrder? _activeOf(RobotIdentity robot) {
    for (final made in ordersOf(robot)) {
      if (const [0, 1, 2, 3, 6, 7, 8, 9, 10, 11, 16].contains(made.status)) {
        return made;
      }
    }
    return null;
  }

  RobotIdentity _robotOf(CoordinatorRequest request) {
    final key = request.robot;
    final robot = key == null ? null : _robots[key];
    if (robot == null) throw StateError('a request for no robot of the test');
    return robot;
  }

  static ScriptedMakerRequest _kindOf(CoordinatorRequest request) =>
      switch (request.url.path) {
        '/api/info/' => ScriptedMakerRequest.info,
        '/api/limits/' => ScriptedMakerRequest.limits,
        '/api/robot/' => ScriptedMakerRequest.robot,
        '/api/make/' => ScriptedMakerRequest.make,
        '/api/order/' when request.method == CoordinatorHttpMethod.post =>
          switch (_actionOf(request)) {
            'update_invoice' => ScriptedMakerRequest.payout,
            'confirm' => ScriptedMakerRequest.confirm,
            'pause' => ScriptedMakerRequest.pause,
            _ => ScriptedMakerRequest.cancel,
          },
        _ => ScriptedMakerRequest.order,
      };

  static String? _actionOf(CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    return body is Map<String, Object?> ? body['action'] as String? : null;
  }

  /// `Logics.calc_sats` of [amount] for [made] at the price now, truncated as `satoshis_now` (`api/logics.py:256-275`).
  int _satsOf(ScriptedMadeOrder made, double amount) =>
      (amount / (_priceOf(made) * (1 + made.premium / 100)) * 100000000)
          .truncate();

  double _priceOf(ScriptedMadeOrder made) =>
      prices[made.body['currency']] ?? (throw StateError('no price'));

  Bolt11TestInvoice _invoice(int sats, String description, Duration expiry) {
    final invoice = Bolt11TestInvoice(
      network: network == RobosatsNetwork.mainnet
          ? Bolt11Network.mainnet
          : Bolt11Network.testnet,
      sats: sats,
      seed: _invoiceSeed++,
      createdAt: clock().toUtc(),
      expiry: expiry,
      description: description,
    );
    decoder.add(invoice);
    return invoice;
  }

  Map<String, Object?> _info() => {
    'num_public_buy_orders': 0,
    'num_public_sell_orders': 0,
    'book_liquidity': 0,
    'active_robots_today': 3,
    'last_day_nonkyc_btc_premium': 2.0,
    'last_day_volume': 0.5,
    'lifetime_volume': 10.0,
    'lnd_version': 'v0.18.0',
    'cln_version': null,
    'robosats_running_commit_hash': 'ff1998c',
    'version': {
      'major': version.major,
      'minor': version.minor,
      'patch': version.patch,
    },
    'alternative_site': null,
    'alternative_name': null,
    'node_alias': coordinator.shortAlias,
    'node_id': coordinator.nodesPubkeys(network).first,
    'network': network.name,
    'maker_fee': makerFee,
    'taker_fee': 0.00175,
    'bond_size': 3.0,
    'min_order_size': minOrderSats,
    'max_order_size': maxOrderSats,
    'swap_enabled': false,
    'max_swap': 0,
    if (devfund != null) 'devfund': devfund,
  };

  /// `LimitView.get` (`api/views.py:1177-1197`).
  Map<String, Object?> _limits() => {
    for (final MapEntry(key: id, value: price) in prices.entries)
      '$id': {
        'code': switch (RobosatsCurrency.fromId(id)) {
          final currency? => currency.code,
          null => '?',
        },
        'price': price,
        'min_amount': minOrderSats / 100000000 * price,
        'max_amount': maxOrderSats / 100000000 * price,
      },
  };

  /// [value], a number of the make's body, as the serializer writes a decimal of [places] places, or `null`.
  static String? _decimal(Object? value, int places) =>
      value is num ? value.toDouble().toStringAsFixed(places) : null;

  /// [value] as the coordinator stores it, 6 decimals, then written as a JSON number (`float` of the `Decimal`, Django REST framework's encoder), or `null`.
  static double? _stored(Object? value) => switch (_decimal(value, 6)) {
    final text? => double.parse(text),
    null => null,
  };

  static void _apply(Map<String, Object?> data, Map<String, Object?> changes) {
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null) {
        data.remove(key);
      } else {
        data[key] = value;
      }
    }
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );

  @override
  String toString() => 'ScriptedMakerCoordinator(${coordinator.shortAlias})';
}
