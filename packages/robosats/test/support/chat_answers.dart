import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'coordinator.dart';

/// Answers derived from the reference code (commit ff1998c), never recorded: no trade has been made, and nothing here comes from a real coordinator.
///
/// The robots are those of `pgp.dart`: index 0 and index 1 of the example Garage Key of the RoboSats repository, whose tokens are published there and are no secret.

const chatNetwork = RobosatsNetwork.testnet;
const chatOrderId = 42;

/// The coordinator of every chat test: temple, on testnet.
Coordinator get chatCoordinator => coordinatorNamed('temple');

/// The answer of `OrderView.get` (`api/views.py:226-528`) about order [chatOrderId] to [reader], a participant, the order made by [maker] and taken by [taker], in [status] (6 or later, so the taker is named).
///
/// It follows the order tests' builder (`order_test.dart`, `_answer`), cut down to the statuses past the take; the maker sells, so the taker buys.
/// Every value has the JSON type the reference writes; [changes] is applied last, a `null` value removing its key.
Map<String, Object?> chatOrderAnswer(
  int status, {
  required RobotIdentity reader,
  required RobotIdentity maker,
  required RobotIdentity taker,
  Map<String, Object?> changes = const {},
}) {
  final isMaker = reader.hashId == maker.hashId;
  final buyer = !isMaker;
  final data = <String, Object?>{
    'id': chatOrderId,
    'status': status,
    'created_at': '2026-11-13T08:00:00.123456Z',
    'expires_at': '2026-11-14T08:00:00Z',
    'type': 1,
    'currency': 2,
    'amount': '150.00000000',
    'has_range': false,
    'min_amount': null,
    'max_amount': null,
    'payment_method': 'SEPA Revolut',
    'is_explicit': false,
    'premium': '1.50',
    'satoshis': null,
    'maker': 7,
    'taker': 8,
    'escrow_duration': 10799,
    'bond_size': '3.00',
    'latitude': 48.8566,
    'longitude': 2.3522,
    'is_maker': isMaker,
    'is_taker': !isMaker,
    'is_participant': true,
    'has_password': false,
    'total_secs_exp': status == 9 || status == 10 || status == 11
        ? 86400
        : status >= 13
        ? 8640000
        : 10799,
    'maker_nick': maker.nickname,
    'maker_hash_id': maker.hashId.hex,
    'maker_nostr_pubkey': maker.nostrKeyPair().publicKeyHex,
    'description': 'Revolut only.',
    'maker_status': 'Active',
    'taker_status': 'Seen recently',
    'is_buyer': buyer,
    'is_seller': !buyer,
    'taker_nick': taker.nickname,
    'taker_hash_id': taker.hashId.hex,
    'taker_nostr_pubkey': taker.nostrKeyPair().publicKeyHex,
    'status_message': 'Some label',
    'is_fiat_sent': status == 10,
    'is_disputed': status == 11 || status >= 16,
    'ur_nick': reader.nickname,
    'satoshis_now': 164414,
    'maker_locked': true,
    'taker_locked': true,
    'escrow_locked': status >= 8,
  };
  if ([6, 7, 8, 12, 10, 11, 13, 14, 15].contains(status)) {
    data['trade_satoshis'] = buyer ? 164126 : 164702;
  }
  if ([8, 9, 10].contains(status)) {
    data
      ..['asked_for_cancel'] = false
      ..['chat_last_index'] = 3;
  } else if (status == 11) {
    data['statement_submitted'] = false;
  }
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
  return data;
}

/// The order a read of [answer] gives [reader], through the client and a fake transport, as a trade use case gets it.
Future<CoordinatorOrder> readChatOrder(
  Map<String, Object?> answer,
  RobotIdentity reader,
) async {
  final transport = FakeCoordinatorTransport()
    ..answer(
      chatCoordinator,
      chatNetwork,
      '/api/order/',
      Ok(jsonResponse(answer)),
    );
  return switch (await CoordinatorClient(transport).fetchOrder(
    chatCoordinator,
    chatNetwork,
    identity: reader,
    orderId: chatOrderId,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('order not read: $failure'),
  };
}

/// One message as `ChatView` writes it (`chat/views.py:99-104`): `index`, `time` (a DRF `DateTimeField`, UTC with `Z`, `robosats/settings.py:248,252`), `message` (the `PGP_message` as stored) and `nick` (the sender's username, its nickname).
Map<String, Object?> chatMessageJson(
  int index,
  String message,
  String nick, {
  String time = '2026-11-13T09:00:00.123456Z',
}) => {'index': index, 'time': time, 'message': message, 'nick': nick};

/// A chat page as `ChatView.get` writes it (`chat/views.py:107-111`).
Map<String, Object?> chatPageJson({
  bool peerConnected = true,
  List<Map<String, Object?>> messages = const [],
  Object? peerPubkey,
}) => {
  'peer_connected': peerConnected,
  'messages': messages,
  'peer_pubkey': peerPubkey,
};

/// The error body of `new_error` (`api/errors.py:99-117`), the codes 6000 to 6003 and 7000 to 7004 all under `bad_request`.
Map<String, Object?> chatError(int code, [String message = 'Some text.']) => {
  'error_code': code,
  'bad_request': message,
};

/// The official client's line-break rules, reimplemented faithfully: `String(encrypted).split('\n').join('\\')` before a post (`frontend/src/components/TradeBox/EncryptedChat/index.tsx:263`) and `message.split('\\').join('\n')` after a read, for the message and the peer key alike (`EncryptedApiChat/index.tsx:141,166,189`).
///
/// JavaScript's `split` with a one-character string separator cuts at every occurrence and keeps empty pieces, as Dart's does.
String referenceToWire(String armored) => armored.split('\n').join(r'\');
String referenceFromWire(String wire) => wire.split(r'\').join('\n');

/// A chat coordinator that behaves as `ChatView` (`chat/views.py:40-218`) for two robots of order [chatOrderId], at [status]: it authenticates the short header, refuses with 6001, 6002 and 6003 as the view does, numbers a post `count + 1`, stores `PGP_message` as received, and answers pages of the messages above the offset with the peer's stored key.
///
/// The keys are stored as the coordinator stores them, with line feeds (`api/utils.py:524-526`).
final class ReferenceChatCoordinator {
  final RobotIdentity maker;
  final RobotIdentity taker;
  final String makerPublicKey;
  final String takerPublicKey;
  int status;
  final List<Map<String, Object?>> stored = [];

  /// Applied to every page before it is sent: a hostile coordinator's edits.
  Map<String, Object?> Function(Map<String, Object?> page, RobotIdentity to)?
  tamper;

  ReferenceChatCoordinator({
    required this.maker,
    required this.taker,
    required this.makerPublicKey,
    required this.takerPublicKey,
    this.status = 9,
  });

  /// Routes `/api/chat/` of [chatCoordinator] on [transport] to this coordinator.
  void serve(FakeCoordinatorTransport transport) => transport.route(
    chatCoordinator,
    chatNetwork,
    '/api/chat/',
    (request) async => Ok(_handle(request)),
  );

  RobotIdentity? _robotOf(CoordinatorRequest request) {
    final header = request.headers['Authorization'];
    for (final robot in [maker, taker]) {
      if (header == robot.authorizationHeader()) return robot;
    }
    return null;
  }

  CoordinatorResponse _handle(CoordinatorRequest request) {
    final robot = _robotOf(request);
    if (robot == null) return jsonResponse(chatError(7001), statusCode: 400);
    final int orderId;
    final int offset;
    if (request.method == CoordinatorHttpMethod.get) {
      final id = request.url.queryParameters['order_id'];
      if (id == null) return jsonResponse(chatError(6000), statusCode: 400);
      orderId = int.parse(id);
      offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      if (![9, 10, 11, 16].contains(status)) {
        return jsonResponse(chatError(6002), statusCode: 400);
      }
    } else {
      final body = jsonDecode(utf8.decode(request.body ?? const []));
      if (body is! Map<String, Object?> ||
          body['PGP_message'] is! String ||
          (body['PGP_message'] as String).trim().isEmpty ||
          body['order_id'] is! int) {
        return jsonResponse(chatError(6003), statusCode: 400);
      }
      orderId = body['order_id'] as int;
      final postedOffset = body['offset'] as int?;
      if (![9, 10].contains(status)) {
        return jsonResponse(chatError(6002), statusCode: 400);
      }
      stored.add(
        chatMessageJson(
          stored.length + 1,
          (body['PGP_message'] as String).trim(),
          robot.nickname,
        ),
      );
      if (postedOffset == null) {
        return jsonResponse(const <String, Object?>{});
      }
      offset = postedOffset;
    }
    if (orderId != chatOrderId) {
      return jsonResponse({'detail': 'Server Error'}, statusCode: 500);
    }
    final isMaker = robot.hashId == maker.hashId;
    final page = chatPageJson(
      peerConnected: true,
      messages: [
        for (final message in stored)
          if ((message['index'] as int) > offset) message,
      ],
      peerPubkey: isMaker ? takerPublicKey : makerPublicKey,
    );
    return jsonResponse(tamper?.call(page, robot) ?? page);
  }
}
