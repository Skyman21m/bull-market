import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256, sha512;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../domain/trade/bolt11.dart';
import 'bolt11_test_invoice.dart';
import 'scripted_signatures.dart';

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

  /// The request is still on its way when its answer times out (`CoordinatorTimedOut`): the coordinator acts on it only when the test calls `ScriptedCoordinator.landLate`, after the reads that follow, as a request held up over Tor.
  landsLate,

  /// The coordinator answers the request as the order stands when it arrives, and the answer reaches the app only when the test calls `ScriptedCoordinator.deliverDelayed`, after later requests were answered: a read overtaken on its way back over Tor (#141).
  answerDelayed,

  /// The coordinator refuses the request before it changes anything, as it refuses a robot that is no participant (1047, `api/views.py:617-619`).
  refused,

  /// The request reaches the coordinator but is served only when the test calls `ScriptedCoordinator.serveLate`, after requests that left later were served and answered: a request that leaves earlier but is served later (#141).
  servedLate,
}

/// The kinds of request the scripted coordinator answers, to aim a [ScriptedFault] at.
enum ScriptedRequest {
  info,
  book,
  robot,
  order,
  take,
  cancel,
  payout,

  /// `GET /api/chat/`.
  chat,

  /// `POST /api/chat/`.
  chatPost,

  /// `confirm`: the buyer's « fiat sent », or the seller's « received ».
  confirm,

  /// `undo_confirm`: the buyer takes back « fiat sent ».
  undoConfirm,

  /// `dispute`.
  dispute,

  /// `rate_platform`.
  rate,

  /// `POST /api/review/`: the token to rate the coordinator on Nostr.
  review,
}

/// One coordinator of the federation list and one order of its book, played for the tests of the trade use cases, as the reference backend at commit ff1998c answers them (`api/views.py`, `api/logics.py`; design note § 1, § 5): never a real coordinator, never money.
///
/// It answers `GET /api/info/`, `GET /api/book/`, `GET /api/robot/` (a first contact keeps the robot with the key pair it sent, a robot it does not know is error 7001), `GET /api/order/` as the order then stands for the robot that asks (3 injected for a live pre-take only, 1043 for a cancelled order, 1044 for a robot that is no participant of an order that is not public), and the `POST /api/order/` actions `take` (a pre-take with its bond invoice on a public order; on any other, the answer of the read, as the reference does, `api/views.py:595-596`), `cancel` (guarded by `cancel_status` against the stored status, 1020 otherwise; free at the pre-take, the bond lost at 6 and 7, `api/logics.py:1005-1181`), and the buyer's payout, `update_invoice` and `update_address` (#90: the clear signature checked against the robot's kept public key and split as the coordinator splits it, then the rules of `Logics.update_invoice` and `update_address`, `api/views.py:617-649`, `api/logics.py:752-947`, with the node's and bitcoind's refusals as their bare texts).
/// From the chat (#95) it also answers `cancel` as the collaborative cancel of 8 and 9 (the first ask raises the asker's flag, `asked_for_cancel` to the asker and `pending_cancel` to the other; the second side's ask returns everything, 12, with the short body of a cancel that ended the order, `api/logics.py:1130-1202`, `api/views.py:604-615`), `confirm` (the buyer's « fiat sent », 9 or 10 → 10, the step's deadline kept; the seller's confirmation only after it, `api/logics.py:1686-1735`), `undo_confirm` (the buyer only, 10 → 9, `:1737-1756`), `dispute` (9 or 10, not earlier than 18 hours before the step's deadline, `:485-533`) and `rate_platform` (the serializer's choices « 1 » to « 5 », kept in [platformRating]), each refused with the reference's code, and 1047 to a robot that is no participant (`api/views.py:617-619`).
/// It answers `POST /api/review/` as `ReviewView` (`api/views.py:1236-1269`, #95): a body without a key an empty 400, a robot whose order is not at 14, 17 or 18 or whose Nostr key is not the one kept at its first contact 1052, otherwise the token, of the reference's form ([reviewToken]).
/// The seller's side (#96, an order of [orderType] 0): the escrow invoice is made once, at the first read of 6 or 7 by the taker who sells, and given with `escrow_satoshis` at 6 and 7 as `Logics.gen_escrow_hold_invoice` gives it (`api/views.py:398-411`, `api/logics.py:1484-1551`: the trade's frozen sats and the taker fee, `:733-749`, valid for the escrow's time); [lockEscrow] locks it (6 → 8, 7 → 9, `:1469-1481`); the seller's `confirm` is refused before « fiat sent » (1027) and with [escrowBelowPayout] (1028), answered `200` at 10 with nothing done when [confirmFallsThrough] (the reference's function falls through when it cannot settle the escrow, `:1716-1735`), and otherwise settles and pays the buyer: 13 (Lightning), or 14 when [onchainPayout].
/// Known gaps: at 8 the reference shows the collaborative cancel's flags to the seller only (`api/views.py:415`, `:431`), not played.
/// The test moves the order along by itself ([lockBond], [moveTo], [takenByAnother], [backToPublic], [cancelByMaker], [expire], [pause], [satoshisNow] for the market's price, [peerAsksToCancel] and [peerAcceptsCancel] for the maker's side of a collaborative cancel, [landLate] for requests held by [ScriptedFault.landsLate]), refuses a take as the reference does ([refuseNextTake]: 409, 1011, 1012, 1045; a pre-taker's cancel gives its robot a penalty; a protected order wants its [password]), and says what a robot holds ([robotAnswerHas]); a paused order is shown to its participants only (1044 to anyone else, a take included); a [range] order takes the amount the take sends; time is [clock], and a pre-take ends at its deadline.
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

  /// A hostile coordinator (#179): a pre-taker's cancel is answered with the whole order at status 4, which the reference never sends (it answers an order the cancel ended with a short body, `api/views.py:604-615`, and a pre-taker's cancel with the order as it then is); the order itself goes on as the cancel left it.
  bool cancelAnswersWholeOrderAt4 = false;

  /// Whether a take on a public order is answered with the order as it is, this robot not its taker, as the reference does on a take that did not happen (`api/views.py:595-596`).
  bool takesNotMade = false;

  /// Whether the order has a range, 50 to 200 EUR, its sats at the book's price given for the largest amount.
  final bool range;

  /// The password of a protected order: a take must send its SHA-256, or it is refused with 1045 (`api/views.py:531-596`).
  final String? password;

  /// The sats of the order's largest amount at the coordinator's price now: the market moves them (`Logics.satoshis_now`).
  int satoshisNow = bookSats;

  /// The order's currency, the reference's id (`currency`, 2 for EUR by default, 1 for USD), in the book and in every read (#249: a currency the Bull wallet prices or not).
  int currency = 2;

  /// The order's premium in percent (#249): the maker's, as the book and every read give it (`premium`, two decimals), and the one the coordinator gives a robot that reads the order without taking part or holds its pre-take (`premium_now`, `api/views.py:288`, and at statuses 1 to 5 `:300-302`, the maker's for an order not priced in sats, `Logics.price_and_premium_now`, `api/logics.py:277-295`); for an order priced in sats, what the test makes the coordinator compute at its own price.
  double premium = 2;

  /// The coordinator's price of a bitcoin with the premium, as the book (`price`) and those reads (`price_now`) give it, rounded to 5 significant digits (`Logics.price_and_premium_now`, `api/logics.py:290-293`): the test keeps it with [satoshisNow] and [premium] (#249); the app computes nothing from it.
  double price = 93545.0;

  /// Whether the buyer is offered an on-chain payout at 6 and 8 (`swap_allowed`), with [swapFeeRate] and [suggestedMiningFeeRate]; otherwise the reference's `swap_failure_reason` when swaps are disabled.
  bool swapAllowed = false;
  double swapFeeRate = 0.75;
  double suggestedMiningFeeRate = 3.5;

  /// The seller's escrow invoice, made at the first read of 6 or 7 by its taker; `null` before.
  Bolt11TestInvoice? escrowInvoice;

  /// A hostile or mistaken coordinator (#96): the escrow invoice is made for these sats rather than the trade's and its fee; [escrowSatoshisAnswered] is what `escrow_satoshis` then says (the invoice's own amount when `null`), and [tradeSatoshisAnswered] what `trade_satoshis` says (the trade's and its fee when `null`).
  int? escrowInvoiceSats;
  int? escrowSatoshisAnswered;
  int? tradeSatoshisAnswered;

  /// The seller's `confirm` is refused with 1028: the escrow is not above the buyer's payout (`api/logics.py:1706-1713`).
  bool escrowBelowPayout = false;

  /// The seller's `confirm` is answered `200` at 10 with nothing done, as the reference does when it cannot settle the escrow (`api/logics.py:1716-1735`).
  bool confirmFallsThrough = false;

  /// The buyer is paid on chain: the seller's confirmation completes the order at once, 14 (`Logics.pay_buyer`, `api/logics.py:1655-1667`).
  bool onchainPayout = false;

  /// How many times the seller's confirmation settled the escrow: never more than once by an honest coordinator.
  int escrowSettlements = 0;

  /// A coordinator that sends its swap rates with `swap_allowed` false, which the reference never does (it sends them only with a swap offered, `api/logics.py:724-728`).
  bool swapRatesWithoutSwap = false;

  /// The summaries `Logics.summarize_trade` adds to a participant's read at 13, 14 and 15 (`api/views.py:500-504`), when the test sets them: `maker_summary`, `taker_summary`, `platform_summary`.
  Map<String, Object?>? tradeSummary;

  /// Whether the coordinator no longer knows the order: every read of it is refused as an unknown order (`api/views.py`, « Invalid Order Id », 404).
  bool orderForgotten = false;

  /// The coordinator's economy estimate, which an address's mining fee rate must reach (`get_minning_fee("minimum")`, at least 2: `api/logics.py:780-793`).
  double minimumMiningFeeRate = 2;

  /// Whether the buyer's payout at 15 has expired (`invoice_expired`), so that a new invoice is taken.
  bool payoutExpired = false;

  /// The last rating the taker gave the coordinator (`robot.platform_rating`, `api/logics.py:1785-1789`), 1 to 5, or `null`.
  int? platformRating;

  /// What `POST /api/review/` gives as its token instead, when set: another form than the reference's.
  Object? reviewTokenOverride;

  /// The token `POST /api/review/` gives for the Nostr key [pubkey]: 128 lowercase hexadecimal characters, the form of the reference's signature of `<pubkey><order id>` (`api/nostr.py:164-175`), here a SHA-512 of that text, never a coordinator's signature.
  String reviewToken(String pubkey) =>
      sha512.convert(utf8.encode('$pubkey$orderId')).toString();

  /// Whether the taker reverted a « fiat sent » (`order.reverted_fiat_sent`, `api/logics.py:1748-1750`).
  bool revertedFiatSent = false;

  /// Whether the maker, the peer, asked for a collaborative cancel, and whether the taker did (`maker_asked_cancel`, `taker_asked_cancel`).
  bool _makerAskedCancel = false;
  bool _takerAskedCancel = false;

  /// The signed texts of the payouts the coordinator recorded, as it split them out, in order.
  final List<String> payoutsRecorded = [];

  /// The payment hash of the last invoice recorded as the payout (`order.payout`).
  String? _payoutHash;

  /// The peer's public key the chat gives (`peer_pubkey`, the maker robot's stored key, `chat/views.py:84,91,110`), armored; `null` for a robot without a key.
  String? peerPublicKey;

  /// Whether the chat says the peer made a request in the last minute (`peer_connected`).
  bool peerConnected = true;

  /// The messages of the chat as the coordinator stores them (`{index, time, message, nick}`, `chat/views.py:95-105`), in its order: the test may add, change, repeat or drop some, as a coordinator could.
  final List<Map<String, Object?>> chat = [];

  /// The maker's Nostr public key the order gives every robot that reads it (`maker_nostr_pubkey`, `api/views.py:278`): by default the x-only key of the secret key 3, the first official BIP-340 test vector, public; `null` gives `"None"`, a maker without one.
  String? makerNostrPublicKey =
      'f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9';

  /// The taker's Nostr public key the order gives once taken (`taker_nostr_pubkey`, `api/views.py:315-317`): when `null`, the key the robot sent at its first contact, as the coordinator keeps it.
  String? takerNostrPublicKey;

  /// The maker's description, which the coordinator shows a robot that reads the order (`api/views.py:280`), never in the book.
  String? description;

  /// The order's payment method text (`payment_method`, in the book and every read, `ListOrderSerializer`): « Cash F2F » is what makes the reference show the place (`components/OrderDetails/index.tsx:409`, #245).
  String paymentMethod = 'Revolut Instant SEPA';

  /// The order's meeting point, latitude then longitude (`latitude`, `longitude`, 6 decimals, `api/models/order.py:186-201`): in the book and in every read (`ListOrderSerializer`, `api/views.py:248`, `:320-321`), hidden from a robot that takes no part in a protected order (`:294-298`); `null` for none (#245).
  (double, double)? meetingPoint;

  /// What the coordinator also says, or says otherwise, to a robot that reads the public order without taking part in it: a coordinator that answers a robot otherwise than the book (#119).
  final Map<String, Object?> robotView = {};

  /// What the coordinator also says, or says otherwise, of the order in its book (#119).
  final Map<String, Object?> bookView = {};

  /// The sats of an order priced in sats, as the official client makes one: `is_explicit`, these `satoshis`, and a `premium` that the order's own answer gives as `null` (`frontend/src/models/Order.model.ts:206`, `OrderView.get` serialising the stored field), where the book gives the premium the coordinator computes at the price now (`api/views.py:809-812`) and a non-participant's read gives it as `premium_now` (`api/views.py:289`); its sats now are these sats whatever the price (`Logics.satoshis_now`, `api/logics.py:262-275`).
  int? explicitSatoshis;

  final Map<RobotSessionKey, Map<String, Object?>> _robotFields = {};
  final List<int> _takeRefusals = [];
  final Map<RobotSessionKey, DateTime> _penalties = {};
  final Map<RobotSessionKey, double> _chosen = {};
  int? _lastSatoshis;

  /// A coordinator that changes the trade's sats fixed at the take (`last_satoshis`) afterwards, which the reference never does (`api/logics.py:1332-1335`): what it pays and asks from then on follows them (#281, a smaller sum asked at 15).
  set lastSatoshis(int sats) => _lastSatoshis = sats;

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
    RobotIdentity? maker,
  }) : coordinator = switch (Federation.robosats.byAlias(alias)) {
         final found? => found,
         null => throw ArgumentError('no coordinator $alias'),
       },
       _robots = {for (final robot in robots) robot.sessionKey: robot},
       _maker =
           maker?.hashId ??
           switch (RobotHashId.parse(
             '5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5',
           )) {
             Ok(:final value) => value,
             Err(:final failure) => throw StateError('$failure'),
           },
       _createdAt = clock().toUtc().subtract(const Duration(hours: 1));

  /// Whether the coordinator checks the signature of every request of a robot that changes a state, as one running the fix of GHSA-22q8-9ghc-jg3h does (RoboSats pull request 2955, head `0943c97`): before anything else (after the participant check, 1047, for an action other than `take` and `cancel`, as the reference), a body with no signature is refused with 1059, one whose signature does not verify with the key the robot gave at its first contact or signs another text with 1048 ([scriptedSignatureRefusal]); the take, the cancel, the payout, the chat step's actions and the token to rate it, never the chat's post.
  ///
  /// `false` plays a coordinator not updated yet, at commit babf62e, which reads only the fields its serializers declare and ignores the signature.
  bool checksSignatures = true;

  /// The public key [robot] gave at its first contact, armored, as the coordinator keeps it: what the peer encrypts its messages to.
  String? publicKeyOf(RobotIdentity robot) =>
      _kept[robot.sessionKey]?['public_key'] as String?;

  /// The maker posts [message] in the chat, the next index after the highest stored, at the time now (`chat/views.py:158-166`).
  void peerSays(OutgoingChatMessage message) => chat.add({
    'index': _nextChatIndex,
    'time': clock().toUtc().toIso8601String(),
    'message': message.wire,
    'nick': _maker.nickname,
  });

  int get _nextChatIndex => chat.length + 1;

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
    // A new trade: no ask of a collaborative cancel yet.
    _makerAskedCancel = false;
    _takerAskedCancel = false;
    escrowInvoice = null;
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

  /// The seller's escrow locks (`Logics.trade_escrow_received`, `api/logics.py:1469-1481`): 6 → 8, 7 → 9, whose chat's time starts.
  void lockEscrow() {
    switch (_status) {
      case 6:
        _status = 8;
      case 7:
        moveTo(9);
      default:
        throw StateError('no escrow awaited at $_status');
    }
  }

  /// The order is public again, its taker gone (a taker's cancel or timeout after its bond locked, its bond settled).
  void backToPublic() {
    _status = 1;
    _taker = null;
    _lastSatoshis = null;
    _preTakes.clear();
  }

  /// The maker, the peer, asks for a collaborative cancel (at 8 or 9), as `Logics.cancel_order` answers it (`api/logics.py:1130-1181`): when the taker asked first, everything is returned and the order is cancelled for both, 12 (`:1151-1158`); otherwise the taker's read then says `pending_cancel`, and the taker's own ask cancels the order for both.
  void peerAsksToCancel() {
    if (_status != 8 && _status != 9) {
      throw StateError('a collaborative cancel is asked at 8 or 9 only');
    }
    if (_takerAskedCancel) {
      _status = 12;
    } else {
      _makerAskedCancel = true;
    }
  }

  /// The maker, the peer, accepts the taker's ask of a collaborative cancel: [peerAsksToCancel] once the taker asked, the order cancelled for both, 12.
  void peerAcceptsCancel() {
    if (!_takerAskedCancel) {
      throw StateError('the taker has not asked for a collaborative cancel');
    }
    peerAsksToCancel();
  }

  /// The requests held by [ScriptedFault.landsLate] reach the coordinator now, in order, and it acts on them; their answers are gone.
  void landLate() {
    final held = List.of(_late);
    _late.clear();
    for (final (kind, request) in held) {
      _answer(kind, request);
    }
  }

  /// The answers held by [ScriptedFault.answerDelayed] reach the app now, in order: all of them, or the first [count].
  void deliverDelayed([int? count]) {
    final held = _delayed.take(count ?? _delayed.length).toList();
    _delayed.removeRange(0, held.length);
    for (final delivered in held) {
      delivered.complete();
    }
  }

  final List<Completer<void>> _delayed = [];

  /// The requests held by [ScriptedFault.servedLate] are served now, in order, as the order then stands, and their answers go back.
  void serveLate() {
    final held = List.of(_servedLate);
    _servedLate.clear();
    for (final served in held) {
      served.complete();
    }
  }

  final List<Completer<void>> _servedLate = [];

  /// The requests held by [ScriptedFault.landsLate], not landed yet.
  final List<(ScriptedRequest, CoordinatorRequest)> _late = [];

  /// Whether the taker asked for a collaborative cancel.
  bool get takerAskedCancel => _takerAskedCancel;

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

  /// A hostile coordinator: the deadline of the trade's step (`expires_at`) is moved to [deadline], earlier or later.
  void moveDeadline(DateTime deadline) => _deadline = deadline.toUtc();

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
    // As the Tor transport (`CoordinatorRequest.onSending`): the request is written unless no place could be had for it or the coordinator could not be reached.
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
      case ScriptedFault.servedLate:
        final served = Completer<void>();
        _servedLate.add(served);
        await served.future;
        return Ok(_answer(kind, request));
      case ScriptedFault.refused:
        return Ok(_json(403, {'error_code': 1047, 'bad_request': 'refused'}));
      case ScriptedFault.answerDelayed:
        final answer = _answer(kind, request);
        final delivered = Completer<void>();
        _delayed.add(delivered);
        await delivered.future;
        return Ok(answer);
      case null:
        return Ok(_answer(kind, request));
    }
  }

  CoordinatorResponse _answer(
    ScriptedRequest kind,
    CoordinatorRequest request,
  ) {
    if (_signatureRefused(kind, request) case final refused?) return refused;
    switch (kind) {
      case ScriptedRequest.info:
        return _json(200, _info());
      case ScriptedRequest.book:
        // A protected order is left out of the book whatever the filter (`api/views.py:788-790`, #245).
        if (_status != 1 || _paused || password != null) {
          return _json(404, {'not_found': 'No orders found'});
        }
        return _json(200, [_bookOrder()]);
      case ScriptedRequest.robot:
        return _robot(request);
      case ScriptedRequest.order:
        // A POST whose action the serializer does not know is refused with an empty 400 before anything (`api/views.py:538-540`, `api/serializers.py:663-677`).
        if (request.method == CoordinatorHttpMethod.post) {
          return CoordinatorResponse(
            statusCode: 400,
            headers: const {},
            body: Uint8List(0),
          );
        }
        return _orderFor(_robotOf(request));
      case ScriptedRequest.take:
        final robot = _robotOf(request);
        final body = jsonDecode(utf8.decode(request.body ?? const []));
        final fields = body is Map<String, Object?> ? body : const {};
        if (_takeRefusals.isNotEmpty) {
          final code = _takeRefusals.removeAt(0);
          return _json(
            switch (code) {
              1000 || 1001 || 1002 || 1003 => 409,
              1012 => 403,
              _ => 400,
            },
            {
              'error_code': code,
              'bad_request': code == 1012
                  ? 'You need to wait 60 seconds to take an order'
                  : 'refused',
            },
          );
        }
        if (hasPenalty(robot)) {
          return _json(403, {
            'error_code': 1012,
            'bad_request': 'You need to wait 60 seconds to take an order',
          });
        }
        if (password case final expected?) {
          final hashed = sha256.convert(utf8.encode(expected)).toString();
          // Refused before anything is done, with the reference's status and message (`api/views.py:558-564`, `api/errors.py:52`, #245).
          if (fields['password'] != hashed) {
            return _json(403, {
              'error_code': 1045,
              'bad_request': 'Wrong password',
            });
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
      case ScriptedRequest.payout:
        return _payout(_robotOf(request), request);
      case ScriptedRequest.chat:
        return _chatRead(_robotOf(request), request);
      case ScriptedRequest.chatPost:
        return _chatPost(_robotOf(request), request);
      case ScriptedRequest.confirm ||
          ScriptedRequest.undoConfirm ||
          ScriptedRequest.dispute ||
          ScriptedRequest.rate:
        return _tradeAction(kind, _robotOf(request), request);
      case ScriptedRequest.review:
        return _review(_robotOf(request), request);
    }
  }

  /// The refusal of the signature of [request] when [checksSignatures] and it is a request of a robot that changes a state, `null` otherwise: see [checksSignatures].
  CoordinatorResponse? _signatureRefused(
    ScriptedRequest kind,
    CoordinatorRequest request,
  ) {
    if (!checksSignatures ||
        request.method != CoordinatorHttpMethod.post ||
        kind == ScriptedRequest.chatPost) {
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
      case '/api/review/':
        // Built here as `api/views.py` builds it, never with the package's own builders, so that a text the package changes is refused.
        expected = ScriptedExactText('review:${fields['pubkey']}');
      case '/api/order/' when action is String && orderId != null:
        // `take` and `cancel` are checked first; every other action after the participant check (1047, `api/views.py` at `0943c97`), which a robot that is no participant is left to.
        if (action != 'take' &&
            action != 'cancel' &&
            _taker != _robotOf(request).sessionKey) {
          return null;
        }
        expected = ScriptedExactText(
          '$action:$orderId:${coordinator.shortAlias}',
        );
      default:
        // The serializer's refusals come first: an action it does not know is an empty 400.
        return null;
    }
    final publicKey = publicKeyOf(_robotOf(request));
    // A robot the coordinator does not know is refused by its authentication first (7001).
    if (publicKey == null) return null;
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

  /// `POST /api/review/` as the reference answers it (`ReviewView`, `api/views.py:1236-1269`).
  CoordinatorResponse _review(RobotIdentity robot, CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final pubkey = body is Map<String, Object?> ? body['pubkey'] : null;
    if (pubkey is! String || pubkey.isEmpty) {
      return CoordinatorResponse(
        statusCode: 400,
        headers: const {},
        body: Uint8List(0),
      );
    }
    const noFinishedOrder = {
      'error_code': 1052,
      'bad_request': 'Robot has no finished order',
    };
    if (_taker != robot.sessionKey || !const {14, 17, 18}.contains(_status)) {
      return _json(400, noFinishedOrder);
    }
    final kept = _kept[robot.sessionKey];
    final held = kept?['nostr_pubkey'];
    if (held is String && held.isNotEmpty && held != pubkey) {
      return _json(400, noFinishedOrder);
    }
    return _json(200, {
      'pubkey': pubkey,
      'token': reviewTokenOverride ?? reviewToken(pubkey),
    });
  }

  /// `GET /api/chat/` as the reference answers it (`chat/views.py:40-113`): no `order_id` 6000, an unknown order a server error (`Order.objects.get`), for the taker at 9, 10, 11 and 16 the messages above the offset (0 when not given, a server error when not an integer), the peer's connection and key.
  ///
  /// Known gaps: the reference lets the maker read too (`views.py:53`), which these tests, a taker's, never need (the seller's slice will); and its query has no `ORDER BY` (`views.py:64`), where this one answers in index order.
  CoordinatorResponse _chatRead(
    RobotIdentity robot,
    CoordinatorRequest request,
  ) {
    final query = request.url.queryParameters;
    final order = query['order_id'];
    if (order == null) {
      return _json(400, {'error_code': 6000, 'bad_request': 'no order'});
    }
    if (int.tryParse(order) != orderId) {
      return _json(500, {'detail': 'DoesNotExist'});
    }
    if (_taker != robot.sessionKey) {
      return _json(400, {'error_code': 6001, 'bad_request': 'not yours'});
    }
    if (![9, 10, 11, 16].contains(_status)) {
      return _json(400, {'error_code': 6002, 'bad_request': 'not now'});
    }
    final given = query['offset'];
    final offset = given == null ? 0 : int.tryParse(given);
    if (offset == null) return _json(500, {'detail': 'ValueError'});
    return _json(200, _chatPage(offset));
  }

  /// `POST /api/chat/` as the reference answers it (`chat/views.py:116-218`, `chat/serializers.py:57-84`): a message empty or missing, an order id or an offset that is not a non-negative integer 6003, an unknown order a server error; stored at 9 and 10 as the next index, then the page above the offset when one is given, and `{}` otherwise.
  ///
  /// Known gaps: the reference lets the maker post too (`views.py:131`), which these tests, a taker's, never need; and its `IntegerField` takes an `order_id` sent as a string such as "42", refused here, which the package never sends.
  CoordinatorResponse _chatPost(
    RobotIdentity robot,
    CoordinatorRequest request,
  ) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final fields = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};
    final message = fields['PGP_message'];
    final order = fields['order_id'];
    final offset = fields['offset'];
    // DRF's `CharField` trims and refuses a blank text; `IntegerField(min_value=0)`.
    if (message is! String ||
        message.trim().isEmpty ||
        order is! int ||
        order < 0 ||
        (offset != null && (offset is! int || offset < 0))) {
      return _json(400, {'error_code': 6003, 'bad_request': 'invalid'});
    }
    if (order != orderId) return _json(500, {'detail': 'DoesNotExist'});
    if (_taker != robot.sessionKey) {
      return _json(400, {'error_code': 6001, 'bad_request': 'not yours'});
    }
    if (_status != 9 && _status != 10) {
      return _json(400, {'error_code': 6002, 'bad_request': 'not now'});
    }
    chat.add({
      'index': _nextChatIndex,
      'time': clock().toUtc().toIso8601String(),
      'message': message.trim(),
      'nick': robot.nickname,
    });
    if (offset is! int) return _json(200, const <String, Object?>{});
    return _json(200, _chatPage(offset));
  }

  Map<String, Object?> _chatPage(int offset) => {
    'peer_connected': peerConnected,
    'messages': [
      for (final message in chat)
        if ((message['index'] as int? ?? 0) > offset) message,
    ],
    'peer_pubkey': switch (peerPublicKey) {
      final key? => pgpArmorToWire(key),
      null => null,
    },
  };

  /// The actions only a participant may send (`api/views.py:617-619`), as `Logics` answers them (#95).
  CoordinatorResponse _tradeAction(
    ScriptedRequest kind,
    RobotIdentity robot,
    CoordinatorRequest request,
  ) {
    // The serializer first (`api/views.py:538-540`): a rating other than « 1 » to « 5 » is an empty 400 (`api/serializers.py:678-683`).
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final rating = body is Map<String, Object?> ? body['rating'] : null;
    // A blank rating passes (`allow_blank`), and is then refused by the view's `and rating`.
    if (rating != null &&
        rating != '' &&
        !const ['1', '2', '3', '4', '5'].contains('$rating')) {
      return CoordinatorResponse(
        statusCode: 400,
        headers: const {},
        body: Uint8List(0),
      );
    }
    if (_taker != robot.sessionKey || _status == 1) {
      return _json(403, {'error_code': 1047, 'bad_request': 'not yours'});
    }
    final buyer = orderType == 1;
    switch (kind) {
      case ScriptedRequest.confirm:
        // `Logics.confirm_fiat` (`api/logics.py:1686-1735`): the step's deadline is not moved.
        if (_status != 9 && _status != 10) {
          return _json(400, {'error_code': 1029, 'bad_request': 'not now'});
        }
        if (buyer) {
          _status = 10;
        } else if (_status != 10) {
          return _json(400, {'error_code': 1027, 'bad_request': 'not sent'});
        } else if (escrowBelowPayout) {
          return _json(400, {'error_code': 1028, 'bad_request': 'escrow'});
        } else if (!confirmFallsThrough) {
          escrowSettlements++;
          moveTo(onchainPayout ? 14 : 13);
        }
      case ScriptedRequest.undoConfirm:
        // `Logics.undo_confirm_fiat_sent` (`api/logics.py:1737-1756`).
        if (!buyer) {
          return _json(400, {'error_code': 1030, 'bad_request': 'not buyer'});
        }
        if (_status != 10) {
          return _json(400, {'error_code': 1031, 'bad_request': 'not now'});
        }
        _status = 9;
        revertedFiatSent = true;
      case ScriptedRequest.dispute:
        // `Logics.open_dispute` (`api/logics.py:485-533`).
        if (_status != 9 && _status != 10) {
          return _json(400, {'error_code': 1013, 'bad_request': 'not now'});
        }
        final opens = (_deadline ?? clock().toUtc()).subtract(
          const Duration(hours: 18),
        );
        if (clock().toUtc().isBefore(opens)) {
          return _json(400, {'error_code': 1054, 'bad_request': 'wait'});
        }
        moveTo(11);
      case ScriptedRequest.rate:
        // The view's `and rating` (`api/views.py:680`, else 1049 with a 501, `:692-693`).
        if (rating == null || rating == '') {
          return _json(501, {'error_code': 1049, 'bad_request': 'what?'});
        }
        platformRating = int.parse('$rating');
      default:
        throw StateError('not an action of the trade: $kind');
    }
    return _orderFor(robot);
  }

  /// `update_invoice` and `update_address` as the reference answers them (`api/views.py:617-649`, `api/logics.py:752-947`).
  CoordinatorResponse _payout(RobotIdentity robot, CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    final fields = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};
    final invoice = fields['action'] == 'update_invoice';
    final key = robot.sessionKey;
    if (_taker != key) {
      return _json(403, {
        'error_code': 1047,
        'bad_request': 'You are not a participant in this order',
      });
    }
    // The clear signature, checked against the public key the robot gave at its first contact, then split as `verify_signed_message` splits it (`api/utils.py:628-648`).
    // Checked on the device's clock, as a coordinator's GnuPG checks on its own: the tests' key pairs are dated by it, not by [clock].
    final signed = fields[invoice ? 'invoice' : 'address'];
    final publicKey = _kept[key]?['public_key'];
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
    if (parts.length < 2) {
      return _json(500, {'detail': 'IndexError'});
    }
    final text = parts[1].split(footer).first.trim();
    if (orderType != 1) {
      return _json(400, {
        'error_code': invoice ? 1017 : 1015,
        'bad_request': 'Only the buyer of this order can provide it.',
      });
    }
    final payout = _last - _fee;
    if (invoice) {
      final mayGive =
          _status == 6 || _status == 8 || (_status == 15 && payoutExpired);
      if (!mayGive) {
        return _json(400, {
          'error_code': 3001,
          'bad_invoice':
              'You can only submit an invoice after expiration or 3 failed attempts',
        });
      }
      final ppm = fields['routing_budget_ppm'];
      final budget = ppm is int ? ppm : 0;
      final asked = (payout.toDouble() - payout.toDouble() * (budget / 1000000))
          .truncate();
      final facts = switch (decoder.decode(text)) {
        Ok(:final value) when value.network.belongsTo(network) => value,
        _ => null,
      };
      if (facts == null) {
        return _json(400, {
          'bad_invoice': 'Does not look like a valid lightning invoice',
        });
      }
      if (facts.amount.value.toInt() != asked) {
        return _json(400, {
          'bad_invoice':
              'The invoice provided is not for ${_grouped(asked)} Sats',
        });
      }
      if (facts.expiresAt.isBefore(clock().toUtc())) {
        return _json(400, {
          'bad_invoice': 'The invoice provided has already expired',
        });
      }
      if (_payoutHash == facts.paymentHash) {
        return _json(400, {
          'error_code': 3002,
          'bad_invoice': 'You must submit a NEW invoice',
        });
      }
      _payoutHash = facts.paymentHash;
    } else {
      if (_status != 6 && _status != 8) {
        return _json(400, {
          'error_code': 1016,
          'bad_request': 'You cannot submit an address now.',
        });
      }
      // No `OnchainPayment` without a swap offered: the reference fails here with a `500` (`api/logics.py:800-803`).
      if (!swapAllowed) return _json(500, {'detail': 'AttributeError'});
      if (BitcoinAddress.check(text, network) is Err) {
        return _json(400, {'bad_address': 'Invalid address'});
      }
      final rateField = fields['mining_fee_rate'];
      final rate = rateField is num
          ? rateField.toDouble()
          : suggestedMiningFeeRate;
      final minimum = minimumMiningFeeRate < 2 ? 2.0 : minimumMiningFeeRate;
      if (rate < minimum) {
        return _json(400, {
          'error_code': 4001,
          'bad_address':
              'The mining fee is too low. Must be higher than $minimum Sat/vbyte',
        });
      }
      if (rate > 500) {
        return _json(400, {
          'error_code': 4002,
          'bad_address':
              'The mining fee is too high, must be less than 500 Sats/vbyte',
        });
      }
      final miningFee = (rate * 280).truncate();
      final sent =
          (payout.toDouble() -
                  payout.toDouble() * swapFeeRate / 100 -
                  miningFee)
              .truncate();
      if (sent < 20000) {
        return _json(400, {
          'error_code': 4003,
          'bad_address':
              'The amount remaining after subtracting mining fee is close to dust limit.',
        });
      }
    }
    payoutsRecorded.add(text);
    // `Logics.move_state_updated_payout_method` (`api/logics.py:909-947`): 8 → 9, 6 → 7 while the escrow is not locked, 15 → 13.
    switch (_status) {
      case 8:
        moveTo(9);
      case 6:
        moveTo(7);
      case 15:
        moveTo(13);
    }
    return _orderFor(robot);
  }

  /// [value] with commas between thousands, as Python's `"{:,}".format`.
  static String _grouped(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
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
      // The whole order at 4, as it would read with this robot named its taker (the parser takes a taker only with its hash id).
      if (cancelAnswersWholeOrderAt4) {
        return _json(200, {
          ..._orderJson(robot, 6),
          'status': 4,
          'total_secs_exp': 0,
        });
      }
      return _orderFor(robot);
    }
    switch (_status) {
      case 6 || 7:
        // The taker's bond is settled, the order back in the book (`api/logics.py:1108-1130`).
        backToPublic();
        return _orderFor(robot);
      case 8 || 9:
        // The collaborative cancel (`api/logics.py:1130-1202`): the second ask returns everything.
        if (_makerAskedCancel) {
          _status = 12;
          return _json(200, {
            'id': orderId,
            'status': 12,
            'type': orderType,
            'expires_at': (_deadline ?? clock().toUtc()).toIso8601String(),
            'bad_request': 'This order has been cancelled',
          });
        }
        _takerAskedCancel = true;
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
    if (orderForgotten) {
      return _json(404, {'bad_request': 'Invalid Order Id'});
    }
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
      '/api/chat/' when request.method == CoordinatorHttpMethod.post =>
        ScriptedRequest.chatPost,
      '/api/chat/' => ScriptedRequest.chat,
      '/api/info/' => ScriptedRequest.info,
      '/api/book/' => ScriptedRequest.book,
      '/api/robot/' => ScriptedRequest.robot,
      '/api/review/' => ScriptedRequest.review,
      _ when action == 'take' => ScriptedRequest.take,
      _ when action == 'cancel' => ScriptedRequest.cancel,
      _ when action == 'update_invoice' || action == 'update_address' =>
        ScriptedRequest.payout,
      _ when action == 'confirm' => ScriptedRequest.confirm,
      _ when action == 'undo_confirm' => ScriptedRequest.undoConfirm,
      _ when action == 'dispute' => ScriptedRequest.dispute,
      _ when action == 'rate_platform' => ScriptedRequest.rate,
      _ => ScriptedRequest.order,
    };
  }

  static String? _actionOf(CoordinatorRequest request) {
    final body = jsonDecode(utf8.decode(request.body ?? const [])) as Object?;
    return body is Map<String, Object?> ? body['action'] as String? : null;
  }

  /// The sats of [amount] at the price now: those of the largest amount, in proportion for a range.
  int _satsOf(double amount) =>
      range ? (_satsNow * amount / 200).truncate() : _satsNow;

  Bolt11TestInvoice _bondInvoice([int? sats]) {
    final invoice = Bolt11TestInvoice(
      network: network == RobosatsNetwork.mainnet
          ? Bolt11Network.mainnet
          : Bolt11Network.testnet,
      sats: sats ?? _satsNow * bondPercent ~/ 100,
      seed: _invoiceSeed++,
      createdAt: clock().toUtc(),
      expiry: const Duration(seconds: 200),
      description:
          "${coordinator.shortAlias} - Taking 'Order $orderId' Buying BTC for 100.0EUR - Taker bond",
    );
    decoder.add(invoice);
    return invoice;
  }

  Bolt11TestInvoice _escrowInvoice(int sats) {
    final invoice = Bolt11TestInvoice(
      network: network == RobosatsNetwork.mainnet
          ? Bolt11Network.mainnet
          : Bolt11Network.testnet,
      sats: sats,
      seed: _invoiceSeed++,
      createdAt: clock().toUtc(),
      expiry: const Duration(seconds: escrowSeconds),
      description:
          "${coordinator.shortAlias} - Escrow amount for 'Order $orderId' - It WILL FREEZE IN YOUR WALLET. It will be released to the buyer once you confirm you received the fiat. It will automatically return if buyer does not confirm the payment.",
    );
    decoder.add(invoice);
    return invoice;
  }

  int get _last => _lastSatoshis ?? _satsNow;

  /// The sats of the order's largest amount now: its own for an order priced in sats.
  int get _satsNow => explicitSatoshis ?? satoshisNow;

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
    'currency': currency,
    'amount': range ? null : '100.00000000',
    'has_range': range,
    'min_amount': range ? '50.00000000' : null,
    'max_amount': range ? '200.00000000' : null,
    'payment_method': paymentMethod,
    'is_explicit': explicitSatoshis != null,
    'premium': premium.toStringAsFixed(2),
    'satoshis': explicitSatoshis,
    'maker': 7,
    'escrow_duration': escrowSeconds,
    'bond_size': '3.00',
    'latitude': meetingPoint?.$1.toStringAsFixed(6),
    'longitude': meetingPoint?.$2.toStringAsFixed(6),
    'maker_hash_id': _maker.hex,
    'satoshis_now': _satsNow,
    'price': price,
    'maker_status': 'Active',
    ...bookView,
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
      'currency': currency,
      'amount': !range
          ? '100.00000000'
          : switch (_chosen[robot.sessionKey]) {
              final chosen? when participant => chosen.toStringAsFixed(8),
              _ => null,
            },
      'has_range': range,
      'min_amount': range ? '50.00000000' : null,
      'max_amount': range ? '200.00000000' : null,
      'payment_method': paymentMethod,
      'is_explicit': explicitSatoshis != null,
      'premium': explicitSatoshis != null ? null : premium.toStringAsFixed(2),
      'satoshis': explicitSatoshis,
      'maker': 7,
      'taker': taken ? 8 : null,
      'escrow_duration': escrowSeconds,
      'bond_size': '3.00',
      'latitude': meetingPoint?.$1.toStringAsFixed(6),
      'longitude': meetingPoint?.$2.toStringAsFixed(6),
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
      'maker_nostr_pubkey': makerNostrPublicKey ?? 'None',
      'description': description,
      'maker_status': 'Active',
    };
    if (!participant) {
      data
        ..['price_now'] = price
        ..['premium_now'] = premium
        ..['satoshis_now'] = _satsNow;
      // A protected order's description and place are hidden from a robot that takes no part in it (`api/views.py:294-298`, #245).
      if (password != null) {
        data
          ..['latitude'] = null
          ..['longitude'] = null
          ..['description'] = null;
      }
      data.addAll(robotView);
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
    if (taken) {
      data
        ..['taker_hash_id'] = robot.hashId.hex
        ..['taker_nostr_pubkey'] =
            takerNostrPublicKey ??
            _kept[robot.sessionKey]?['nostr_pubkey'] ??
            'None';
    }
    if ([6, 7, 8, 10, 11, 13, 14, 15].contains(status)) {
      data['trade_satoshis'] = buyer ? payout : tradeSatoshisAnswered ?? escrow;
    }
    switch (status) {
      case 3:
        final invoice = bond ?? _bondInvoice();
        data
          ..['bond_invoice'] = invoice.text
          ..['bond_satoshis'] = invoice.facts.amount.value.toInt()
          ..['price_now'] = price
          ..['premium_now'] = premium;
      case 6 || 8 when buyer:
        data
          ..['invoice_amount'] = payout
          ..['swap_allowed'] = swapAllowed;
        if (swapAllowed || swapRatesWithoutSwap) {
          data
            ..['suggested_mining_fee_rate'] = suggestedMiningFeeRate
            ..['swap_fee_rate'] = swapFeeRate;
        }
        if (!swapAllowed) {
          data['swap_failure_reason'] =
              'On-the-fly submarine swaps are disabled';
        }
      case 6 || 7 when !buyer:
        // Made once, at the first read that asks for it, and given again while it waits (`api/logics.py:1490-1496`).
        final invoice = escrowInvoice ??= _escrowInvoice(
          escrowInvoiceSats ?? escrow,
        );
        data
          ..['escrow_invoice'] = invoice.text
          ..['escrow_satoshis'] =
              escrowSatoshisAnswered ?? invoice.facts.amount.value.toInt();
      case 15 when buyer:
        data
          ..['retries'] = 3
          ..['next_retry_time'] = clock().toUtc().toIso8601String()
          // `LNPayment.FailureReason.NONRECO`'s label (`api/models/ln_payment.py`).
          ..['failure_reason'] = 'A non-recoverable error has occurred.';
        if (payoutExpired) data['invoice_expired'] = true;
      case 9 || 10:
        // `api/views.py:430-449`: `pending_cancel` when the peer asked, else whether this robot did.
        if (_makerAskedCancel) {
          data['pending_cancel'] = true;
        } else {
          data['asked_for_cancel'] = _takerAskedCancel;
        }
        // `api/views.py:451-456`: 0 for an empty chat, otherwise the highest index.
        data['chat_last_index'] = chat.fold<int>(
          0,
          (highest, message) => switch (message['index']) {
            final int index when index > highest => index,
            _ => highest,
          },
        );
      case 11:
        data['statement_submitted'] = false;
      case 5:
        data
          ..['public_duration'] = 86399
          ..['expiry_reason'] = 3
          ..['expiry_message'] = 'Invoice not submitted';
    }
    if (tradeSummary case final summary? when status >= 13 && status <= 15) {
      data.addAll(summary);
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
