import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/chat_answers.dart';
import '../support/coordinator.dart';
import '../support/craft.dart';
import '../support/pgp.dart';

/// This device's robot, the taker (a buyer) of most tests: index 0 of the example Garage Key of the RoboSats repository, a published token, never a secret.
final _us = interopIdentity;

/// The peer, the maker of most tests: index 1 of the same example key.
final _peer = interopPeerIdentity;

/// A robot of the coordinator's own: test robot 3 of the RoboSats repository, a published token.
final _stranger = repositoryRobotIdentity(3);

/// Keys built by the test with a fast S2K, named as the official client names a robot's key: the robots' own, one of the coordinator's own robot, and one the coordinator made and named after the peer.
final _usKey = CraftedKey(label: 'chat-us', userId: _us.pgpUserId);
final _peerKey = CraftedKey(label: 'chat-peer', userId: _peer.pgpUserId);
final _strangerKey = CraftedKey(
  label: 'chat-stranger',
  userId: _stranger.pgpUserId,
);
final _forgedPeerKey = CraftedKey(
  label: 'chat-forged',
  userId: _peer.pgpUserId,
);

/// After the crafted keys' date, 2026-11-08 12:00 UTC.
final _now = DateTime.utc(2026, 11, 9, 12);

const _get = CoordinatorHttpMethod.get;
const _post = CoordinatorHttpMethod.post;

Future<CoordinatorOrder> _readAt(int status, {bool asMaker = false}) =>
    readChatOrder(
      chatOrderAnswer(
        status,
        reader: _us,
        maker: asMaker ? _us : _peer,
        taker: asMaker ? _peer : _us,
      ),
      _us,
    );

/// [plaintext] encrypted by this device's robot to the peer's crafted key, ready to post.
OutgoingChatMessage _outgoing(String plaintext, {UnlockedRobotPgpKey? key}) =>
    expectOk(
      (key ?? _usKey.unlockedFor(_us)).encryptChatMessageToPost(
        plaintext,
        peer: _peerKey.publicKey,
        now: _now,
      ),
    );

/// A transport whose `/api/chat/` always answers [response].
FakeCoordinatorTransport _answering(
  Result<CoordinatorResponse, CoordinatorTransportFailure> response,
) =>
    FakeCoordinatorTransport()
      ..answer(chatCoordinator, chatNetwork, '/api/chat/', response);

Future<Result<ChatPage, CoordinatorFailure>> _fetch(
  FakeCoordinatorTransport transport, {
  CoordinatorOrder? lastRead,
  int offset = 0,
  RobotIdentity? identity,
}) async => CoordinatorClient(transport).fetchChat(
  identity: identity ?? _us,
  lastRead: lastRead ?? await _readAt(9),
  offset: offset,
);

Future<Result<ChatPage, OrderActionFailure>> _postWith(
  FakeCoordinatorTransport transport, {
  CoordinatorOrder? lastRead,
  OutgoingChatMessage? message,
  int offset = 0,
  RobotIdentity? identity,
}) async => CoordinatorClient(transport).postChat(
  identity: identity ?? _us,
  lastRead: lastRead ?? await _readAt(9),
  message: message ?? _outgoing('Hello'),
  offset: offset,
);

/// A page with one message of each sender and kind of content, as the reference writes it.
Map<String, Object?> _page({
  List<Map<String, Object?>>? messages,
  Object? peerPubkey = _usePeerKey,
  bool peerConnected = true,
}) => chatPageJson(
  peerConnected: peerConnected,
  messages:
      messages ?? [chatMessageJson(1, _outgoing('Hi').wire, _us.nickname)],
  peerPubkey: identical(peerPubkey, _usePeerKey)
      ? _peerKey.publicKey.armored
      : peerPubkey,
);

const _usePeerKey = Object();

ChatPage _pageOk(Result<ChatPage, CoordinatorFailure> result) =>
    expectOk(result);

void main() {
  group('the requests', () {
    test(
      'fetchChat is the reference poll: GET /api/chat/?order_id=&offset= with the short header on the robot session',
      () async {
        final transport = _answering(Ok(jsonResponse(_page(messages: []))));
        expectOk(await _fetch(transport, offset: 7));
        final request = transport.requests.single;
        expect(request.method, _get);
        expect(request.url.scheme, 'http');
        expect(
          request.url.host,
          Uri.parse(chatCoordinator.origins(chatNetwork).onion ?? '').host,
        );
        expect(request.url.path, '/api/chat/');
        expect(request.url.query, 'order_id=$chatOrderId&offset=7');
        expect(request.headers, {
          'Accept': 'application/json',
          'Authorization': _us.authorizationHeader(),
        });
        expect(request.body, isNull);
        expect(request.robot, _us.sessionKey);
        expect(request.maxResponseBytes, CoordinatorReadBounds.chatBytes);
      },
    );

    test(
      'postChat is the reference post: POST /api/chat/ with PGP_message, order_id and offset, in that order, as JSON',
      () async {
        final message = _outgoing('Hello');
        final transport = _answering(Ok(jsonResponse(_page())));
        await _postWith(transport, message: message, offset: 3);
        final request = transport.requests.single;
        expect(request.method, _post);
        expect(request.url.path, '/api/chat/');
        expect(request.url.query, isEmpty);
        expect(request.headers, {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': _us.authorizationHeader(),
        });
        expect(request.robot, _us.sessionKey);
        expect(request.maxResponseBytes, CoordinatorReadBounds.chatBytes);
        final body = utf8.decode(request.body ?? const []);
        expect(
          body,
          '{"PGP_message":${jsonEncode(message.wire)},"order_id":$chatOrderId,"offset":3}',
        );
        expect(message.wire, isNot(contains('\n')));
        expect(message.wire, referenceToWire(message.armored));
      },
    );

    test(
      'a post is sent once, whatever the outcome, a timeout included',
      () async {
        for (final failure in <CoordinatorTransportFailure>[
          const CoordinatorTimedOut(),
          const CoordinatorUnreachable(),
          const CoordinatorTransportFailed(),
        ]) {
          final transport = _answering(Err(failure));
          final result = await _postWith(transport);
          expect(transport.requests, hasLength(1));
          expect(
            expectErr(result),
            isA<OrderActionOutcomeUnknown>().having(
              (f) => f.cause,
              'cause',
              same(failure),
            ),
          );
        }
      },
    );

    test(
      'an Error the transport throws on a post is an outcome unknown, on a read it propagates',
      () async {
        final throwing = FakeCoordinatorTransport()
          ..route(
            chatCoordinator,
            chatNetwork,
            '/api/chat/',
            (_) => throw StateError('broken adapter'),
          );
        expect(
          expectErr(await _postWith(throwing)),
          isA<OrderActionOutcomeUnknown>().having(
            (f) => f.cause,
            'cause',
            isA<CoordinatorTransportFailed>(),
          ),
        );
        final lastRead = await _readAt(9);
        await expectLater(
          CoordinatorClient(
            throwing,
          ).fetchChat(identity: _us, lastRead: lastRead, offset: 0),
          throwsStateError,
        );
        final excepting = FakeCoordinatorTransport()
          ..route(
            chatCoordinator,
            chatNetwork,
            '/api/chat/',
            (_) => throw const FormatException('broken adapter'),
          );
        expect(
          expectErr(await _fetch(excepting)),
          isA<CoordinatorTransportFailed>(),
        );
      },
    );
  });

  group('checks before anything is sent', () {
    test('a last read by another robot is refused', () async {
      final peerRead = await readChatOrder(
        chatOrderAnswer(9, reader: _peer, maker: _peer, taker: _us),
        _peer,
      );
      final transport = _answering(Ok(jsonResponse(_page())));
      expect(
        expectErr(await _fetch(transport, lastRead: peerRead)),
        isA<OrderReadElsewhere>(),
      );
      expect(
        expectErr(await _postWith(transport, lastRead: peerRead)),
        isA<OrderActionRefused>().having(
          (f) => f.cause,
          'cause',
          isA<OrderReadElsewhere>(),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'reading is sent at 9, 10, 11 and 16 only, posting at 9 and 10 only (chat/views.py:56-62, :136-137)',
      () async {
        const readable = {9, 10, 11, 16};
        const postable = {9, 10};
        for (final status in [6, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17, 18]) {
          for (final asMaker in [false, true]) {
            final lastRead = await _readAt(status, asMaker: asMaker);
            final transport = _answering(Ok(jsonResponse(_page())));
            final read = await _fetch(transport, lastRead: lastRead);
            if (readable.contains(status)) {
              expectOk(read);
            } else {
              expect(
                expectErr(read),
                isA<ChatRefused>().having(
                  (f) => f.reason,
                  'reason',
                  ChatRefusal.notInChat,
                ),
                reason: 'read at $status',
              );
            }
            final posted = await _postWith(transport, lastRead: lastRead);
            if (postable.contains(status)) {
              expectOk(posted);
            } else {
              expect(
                expectErr(posted),
                isA<OrderActionRefused>().having(
                  (f) => f.cause,
                  'cause',
                  isA<ChatRefused>().having(
                    (f) => f.reason,
                    'reason',
                    ChatRefusal.notInChat,
                  ),
                ),
                reason: 'post at $status',
              );
            }
            expect(
              transport.requests,
              hasLength(
                (readable.contains(status) ? 1 : 0) +
                    (postable.contains(status) ? 1 : 0),
              ),
            );
          }
        }
      },
    );

    test('a robot that is no participant is refused', () async {
      // The answer to a robot that is neither maker nor taker: a public order without any participant's field.
      final answer = chatOrderAnswer(1, reader: _us, maker: _peer, taker: _us)
        ..removeWhere(
          (key, _) => const {
            'is_buyer',
            'is_seller',
            'taker_nick',
            'taker_hash_id',
            'taker_nostr_pubkey',
            'ur_nick',
            'is_fiat_sent',
            'is_disputed',
            'maker_locked',
            'taker_locked',
            'escrow_locked',
            'taker',
            'taker_status',
          }.contains(key),
        )
        ..addAll({
          'is_taker': false,
          'is_participant': false,
          'price_now': 91234.5,
          'premium_now': 1.5,
          'latitude': '48.85660000',
          'longitude': '2.35220000',
        });
      final outsider = await readChatOrder(answer, _us);
      final transport = _answering(Ok(jsonResponse(_page())));
      expect(
        expectErr(await _fetch(transport, lastRead: outsider)),
        isA<ChatRefused>().having(
          (f) => f.reason,
          'reason',
          ChatRefusal.notParticipant,
        ),
      );
      expect(
        expectErr(await _postWith(transport, lastRead: outsider)),
        isA<OrderActionRefused>().having(
          (f) => f.cause,
          'cause',
          isA<ChatRefused>().having(
            (f) => f.reason,
            'reason',
            ChatRefusal.notParticipant,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });

    test(
      'an offset outside 0 to 2,147,483,647 is refused, the bounds are sent',
      () async {
        final transport = _answering(Ok(jsonResponse(_page(messages: []))));
        for (final offset in [-1, ChatPage.maxIndex + 1]) {
          expect(
            expectErr(await _fetch(transport, offset: offset)),
            isA<ChatRefused>().having(
              (f) => f.reason,
              'reason',
              ChatRefusal.offsetOutOfRange,
            ),
          );
          expect(
            expectErr(await _postWith(transport, offset: offset)),
            isA<OrderActionRefused>().having(
              (f) => f.cause,
              'cause',
              isA<ChatRefused>().having(
                (f) => f.reason,
                'reason',
                ChatRefusal.offsetOutOfRange,
              ),
            ),
          );
        }
        expect(transport.requests, isEmpty);
        for (final offset in [0, ChatPage.maxIndex]) {
          expectOk(await _fetch(transport, offset: offset));
        }
        expect(transport.requests, hasLength(2));
      },
    );

    test('a message encrypted by another robot is refused', () async {
      final theirs = _outgoing('Hello', key: _peerKey.unlockedFor(_peer));
      final transport = _answering(Ok(jsonResponse(_page())));
      expect(
        expectErr(await _postWith(transport, message: theirs)),
        isA<OrderActionRefused>().having(
          (f) => f.cause,
          'cause',
          isA<ChatRefused>().having(
            (f) => f.reason,
            'reason',
            ChatRefusal.messageOfAnotherRobot,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
    });
  });

  group('refusals of the coordinator', () {
    // Each row: HTTP status, body, the failure expected, and whether a post is refused (nothing stored) or its outcome unknown.
    final rows =
        <
          ({
            int status,
            Object? body,
            Matcher failure,
            bool refused,
            String label,
          })
        >[
          (
            status: 400,
            body: chatError(6000, 'Order ID does not exist'),
            failure: _chatRefused(ChatRefusal.orderIdMissing),
            refused: true,
            label: '6000',
          ),
          (
            status: 400,
            body: chatError(6001, 'You are not participant in this order'),
            failure: _chatRefused(ChatRefusal.notParticipant),
            refused: true,
            label: '6001',
          ),
          (
            status: 400,
            body: chatError(6002, 'Order is not in chat status'),
            failure: _chatRefused(ChatRefusal.notInChat),
            refused: true,
            label: '6002',
          ),
          (
            status: 400,
            body: chatError(6003, 'Invalid serializer'),
            failure: _chatRefused(ChatRefusal.invalidRequest),
            refused: true,
            label: '6003',
          ),
          (
            status: 400,
            body: chatError(7001),
            failure: isA<RobotUnknown>(),
            refused: true,
            label: '7001',
          ),
          (
            status: 400,
            body: chatError(7000),
            failure: isA<RobotCredentialsRejected>(),
            refused: true,
            label: '7000',
          ),
          (
            status: 401,
            body: chatError(7003),
            failure: isA<RobotCredentialsRejected>(),
            refused: true,
            label: '7003',
          ),
          (
            status: 401,
            body: {'detail': 'Authentication credentials were not provided.'},
            failure: isA<RobotCredentialsRejected>(),
            refused: true,
            label: '401 without code',
          ),
          (
            status: 403,
            body: {'detail': 'Forbidden'},
            failure: isA<RobotCredentialsRejected>(),
            refused: true,
            label: '403 without code',
          ),
          (
            status: 400,
            body: {'detail': 'JSON parse error'},
            failure: isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              400,
            ),
            refused: false,
            label: '400 without code',
          ),
          (
            status: 409,
            body: chatError(7004),
            failure: isA<OrderRequestRefused>().having(
              (f) => f.errorCode,
              'errorCode',
              7004,
            ),
            refused: false,
            label: '7004, never sent to a known robot',
          ),
          (
            status: 400,
            body: chatError(1042),
            failure: isA<OrderRequestRefused>().having(
              (f) => f.errorCode,
              'errorCode',
              1042,
            ),
            refused: false,
            label: 'a code of the order calls',
          ),
          (
            status: 404,
            body: chatError(6004),
            failure: isA<OrderRequestRefused>().having(
              (f) => f.errorCode,
              'errorCode',
              6004,
            ),
            refused: false,
            label: 'an unknown code',
          ),
          (
            status: 500,
            body: chatError(6001),
            failure: isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              500,
            ),
            refused: false,
            label: '500 with a code, read as a 500',
          ),
          (
            status: 502,
            body: 'Bad Gateway',
            failure: isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              502,
            ),
            refused: false,
            label: '502',
          ),
          (
            status: 302,
            body: chatError(6001),
            failure: isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              302,
            ),
            refused: false,
            label: '302 with a code',
          ),
          (
            status: 400,
            body: {'error_code': '6001', 'bad_request': 'x'},
            failure: isA<CoordinatorUnexpectedStatus>(),
            refused: false,
            label: 'a code that is not an integer',
          ),
        ];
    for (final row in rows) {
      test(
        '${row.label}: the failure, and ${row.refused ? 'refused' : 'outcome unknown'} for a post',
        () async {
          final response = Ok<CoordinatorResponse, CoordinatorTransportFailure>(
            jsonResponse(row.body, statusCode: row.status),
          );
          expect(expectErr(await _fetch(_answering(response))), row.failure);
          final posted = expectErr(await _postWith(_answering(response)));
          expect(
            posted,
            row.refused
                ? isA<OrderActionRefused>()
                : isA<OrderActionOutcomeUnknown>(),
          );
          expect(posted.cause, row.failure);
        },
      );
    }

    test('a refusal without a JSON body is the HTTP status alone', () async {
      for (final status in [400, 404, 500]) {
        final response = Ok<CoordinatorResponse, CoordinatorTransportFailure>(
          rawResponse(
            utf8.encode('<html>nope</html>'),
            statusCode: status,
            contentType: 'text/html',
          ),
        );
        expect(
          expectErr(await _fetch(_answering(response))),
          isA<CoordinatorUnexpectedStatus>().having(
            (f) => f.statusCode,
            'statusCode',
            status,
          ),
        );
        expect(
          expectErr(await _postWith(_answering(response))),
          isA<OrderActionOutcomeUnknown>(),
        );
      }
    });

    test(
      'busy and no transport: nothing was sent, a post is refused',
      () async {
        final busy = _answering(const Err(CoordinatorTransportBusy()));
        expect(expectErr(await _fetch(busy)), isA<CoordinatorTransportBusy>());
        expect(
          expectErr(await _postWith(busy)),
          isA<OrderActionRefused>().having(
            (f) => f.cause,
            'cause',
            isA<CoordinatorTransportBusy>(),
          ),
        );
      },
    );

    test(
      'timeouts and broken connections: a read fails, a post is an outcome unknown',
      () async {
        for (final failure in <CoordinatorTransportFailure>[
          const CoordinatorTimedOut(),
          const CoordinatorUnreachable(),
          const CoordinatorTransportFailed(),
          const CoordinatorResponseTooLarge(),
        ]) {
          expect(
            expectErr(await _fetch(_answering(Err(failure)))),
            same(failure),
          );
          expect(
            expectErr(await _postWith(_answering(Err(failure)))),
            isA<OrderActionOutcomeUnknown>(),
          );
        }
      },
    );

    test('a body over the bound is refused, at the bound it is read', () async {
      final over = jsonResponse(_page());
      final padded = CoordinatorResponse(
        statusCode: 200,
        headers: over.headers,
        body: Uint8List.fromList([
          ...over.body,
          ...List.filled(
            CoordinatorReadBounds.chatBytes - over.body.length + 1,
            0x20,
          ),
        ]),
      );
      expect(
        expectErr(await _fetch(_answering(Ok(padded)))),
        isA<CoordinatorResponseTooLarge>(),
      );
      expect(
        expectErr(await _postWith(_answering(Ok(padded)))),
        isA<OrderActionOutcomeUnknown>().having(
          (f) => f.cause,
          'cause',
          isA<CoordinatorResponseTooLarge>(),
        ),
      );
      final exact = CoordinatorResponse(
        statusCode: 200,
        headers: over.headers,
        body: Uint8List.fromList([
          ...over.body,
          ...List.filled(
            CoordinatorReadBounds.chatBytes - over.body.length,
            0x20,
          ),
        ]),
      );
      expectOk(await _fetch(_answering(Ok(exact))));
    });
  });

  group('malformed answers', () {
    final validMessage = chatMessageJson(
      1,
      _outgoing('Hi').wire,
      _peer.nickname,
    );
    Map<String, Object?> withMessage(Map<String, Object?> changes) => _page(
      messages: [
        {...validMessage, ...changes}..removeWhere((_, v) => v == _remove),
      ],
    );
    final cases = <String, (Object? body, String field)>{
      'a list': (<Object?>[], 'chat'),
      'a string': ('chat', 'chat'),
      'no peer_connected': (
        {..._page()}..remove('peer_connected'),
        'peer_connected',
      ),
      'peer_connected a string': (
        {..._page(), 'peer_connected': 'true'},
        'peer_connected',
      ),
      'no messages': ({..._page()}..remove('messages'), 'messages'),
      'messages an object': (
        {..._page(), 'messages': <String, Object?>{}},
        'messages',
      ),
      'too many messages': (
        _page(
          messages: [
            for (var i = 1; i <= ChatPage.maxMessages + 1; i++)
              chatMessageJson(i, 'x', _peer.nickname),
          ],
        ),
        'messages',
      ),
      'a message that is a string': (
        {
          ..._page(),
          'messages': ['hello'],
        },
        'messages',
      ),
      'peer_pubkey a number': ({..._page(), 'peer_pubkey': 3}, 'peer_pubkey'),
      'peer_pubkey a list': (
        {..._page(), 'peer_pubkey': <Object?>[]},
        'peer_pubkey',
      ),
      'no index': (withMessage({'index': _remove}), 'index'),
      'index 0': (withMessage({'index': 0}), 'index'),
      'index a float': (withMessage({'index': 1.0}), 'index'),
      'index a string': (withMessage({'index': '1'}), 'index'),
      'index over the bound': (
        withMessage({'index': ChatPage.maxIndex + 1}),
        'index',
      ),
      'index negative': (withMessage({'index': -1}), 'index'),
      'no time': (withMessage({'time': _remove}), 'time'),
      'time without zone': (
        withMessage({'time': '2026-11-13T09:00:00'}),
        'time',
      ),
      'time out of range': (
        withMessage({'time': '2026-11-13T25:00:00Z'}),
        'time',
      ),
      'time before 2020': (
        withMessage({'time': '2019-12-31T23:59:59Z'}),
        'time',
      ),
      'time a number': (withMessage({'time': 1794139200}), 'time'),
      'no nick': (withMessage({'nick': _remove}), 'nick'),
      'nick empty': (withMessage({'nick': ''}), 'nick'),
      'nick of 19 characters': (withMessage({'nick': 'A' * 19}), 'nick'),
      'nick with a space': (withMessage({'nick': 'Bad Nick1'}), 'nick'),
      'nick with a bidi control': (
        withMessage({'nick': 'Nick\u202E1'}),
        'nick',
      ),
      'nick with a line feed': (withMessage({'nick': 'Nick\n1'}), 'nick'),
      'nick a number': (withMessage({'nick': 7}), 'nick'),
      'no message': (withMessage({'message': _remove}), 'message'),
      'message null': (withMessage({'message': null}), 'message'),
      'message a number': (withMessage({'message': 12}), 'message'),
    };
    for (final MapEntry(key: name, value: (body, field)) in cases.entries) {
      test(
        '$name: CoordinatorResponseMalformed($field); a post is an outcome unknown',
        () async {
          final response = Ok<CoordinatorResponse, CoordinatorTransportFailure>(
            jsonResponse(body),
          );
          expect(
            expectErr(await _fetch(_answering(response))),
            isA<CoordinatorResponseMalformed>().having(
              (f) => f.field,
              'field',
              field,
            ),
          );
          expect(
            expectErr(await _postWith(_answering(response))),
            isA<OrderActionOutcomeUnknown>().having(
              (f) => f.cause,
              'cause',
              isA<CoordinatorResponseMalformed>(),
            ),
          );
        },
      );
    }

    test(
      'an index not above the offset is refused: the reference answers only `index > offset`',
      () async {
        final page = _page(messages: [chatMessageJson(5, 'x', _peer.nickname)]);
        for (final offset in [5, 6]) {
          expect(
            expectErr(
              await _fetch(_answering(Ok(jsonResponse(page))), offset: offset),
            ),
            isA<CoordinatorResponseMalformed>().having(
              (f) => f.field,
              'field',
              'index',
            ),
          );
        }
        expectOk(await _fetch(_answering(Ok(jsonResponse(page))), offset: 4));
      },
    );

    test('not JSON: content type, encoding, syntax', () async {
      final bodies = [
        rawResponse(utf8.encode(jsonEncode(_page())), contentType: 'text/html'),
        rawResponse(utf8.encode(jsonEncode(_page())), contentType: null),
        rawResponse([0xff, 0xfe, 0x7b]),
        rawResponse(utf8.encode('{"peer_connected": true,')),
        rawResponse(const []),
      ];
      for (final body in bodies) {
        expect(
          expectErr(await _fetch(_answering(Ok(body)))),
          isA<CoordinatorNotJson>(),
        );
        expect(
          expectErr(await _postWith(_answering(Ok(body)))),
          isA<OrderActionOutcomeUnknown>().having(
            (f) => f.cause,
            'cause',
            isA<CoordinatorNotJson>(),
          ),
        );
      }
    });

    test(
      'the empty object of a post without an offset is malformed: this package always sends one',
      () async {
        final response = Ok<CoordinatorResponse, CoordinatorTransportFailure>(
          jsonResponse(const <String, Object?>{}),
        );
        expect(
          expectErr(await _postWith(_answering(response))),
          isA<OrderActionOutcomeUnknown>().having(
            (f) => f.cause,
            'cause',
            isA<CoordinatorResponseMalformed>(),
          ),
        );
      },
    );

    test(
      'the bounds that are accepted: index 1 and 2,147,483,647, a nick of 18 characters with a hyphen and digits, a time with microseconds or an offset',
      () async {
        final page = expectOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [
                      chatMessageJson(
                        1,
                        'x',
                        'Ace-in-the-hole123',
                        time: '2026-11-13T09:00:00+01:00',
                      ),
                      chatMessageJson(
                        ChatPage.maxIndex,
                        'x',
                        'A' * 18,
                        time: '2026-11-13T09:00:00.999999Z',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(page.messages.map((m) => m.index), [1, ChatPage.maxIndex]);
        expect(page.messages.first.time, DateTime.utc(2026, 11, 13, 8));
        expect(
          page.messages.map((m) => m.sender),
          everyElement(ChatSender.unknown),
        );
      },
    );
  });

  group('the content of a message: what a peer posts never refuses a page', () {
    test(
      'a PGP message is given with its line feeds restored, as the reference restores them',
      () async {
        final message = _outgoing('Hi');
        final page = _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [chatMessageJson(1, message.wire, _us.nickname)],
                  ),
                ),
              ),
            ),
          ),
        );
        final read = page.messages.single;
        expect(read.content, ChatMessageContent.pgpMessage);
        expect(read.armored, message.armored);
        expect(read.armored, referenceFromWire(message.wire));
      },
    );

    test(
      'text that is not a PGP message is dropped and stated, as the reference ignores it',
      () async {
        for (final text in [
          'plain text sent by hand',
          '',
          ' -----BEGIN PGP MESSAGE-----',
          '-----BEGIN PGP SIGNED MESSAGE-----',
          '-----begin pgp message-----',
        ]) {
          final page = _pageOk(
            await _fetch(
              _answering(
                Ok(
                  jsonResponse(
                    _page(messages: [chatMessageJson(1, text, _peer.nickname)]),
                  ),
                ),
              ),
            ),
          );
          expect(
            page.messages.single.content,
            ChatMessageContent.notPgpMessage,
          );
          expect(page.messages.single.armored, isNull);
        }
      },
    );

    test(
      'a message over 65,536 characters is dropped unread and stated, at the bound it is given',
      () async {
        const begin = '-----BEGIN PGP MESSAGE-----';
        final atBound = begin + 'A' * (ChatMessage.maxReadChars - begin.length);
        final over = '${atBound}A';
        final page = _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [
                      chatMessageJson(1, atBound, _peer.nickname),
                      chatMessageJson(2, over, _peer.nickname),
                      chatMessageJson(3, _outgoing('after').wire, _us.nickname),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(page.messages.map((m) => m.content), [
          ChatMessageContent.pgpMessage,
          ChatMessageContent.tooLong,
          ChatMessageContent.pgpMessage,
        ]);
        expect(page.messages[1].armored, isNull);
        expect(page.lastIndex, 3);
      },
    );

    test(
      'a malformed PGP message is given as it is: decryption tells',
      () async {
        final page = _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [
                      chatMessageJson(
                        1,
                        '-----BEGIN PGP MESSAGE-----\\garbage',
                        _peer.nickname,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final read = page.messages.single;
        expect(read.content, ChatMessageContent.pgpMessage);
        expect(
          expectErr(
            _usKey
                .unlockedFor(_us)
                .decryptChatMessage(
                  read.armored ?? '',
                  sender: _peerKey.publicKey,
                  now: _now,
                ),
          ),
          isA<PgpArmorMalformed>(),
        );
      },
    );
  });

  group('the order of the messages: facts, not refusals', () {
    Future<ChatPage> pageOf(List<int> indexes, {int offset = 0}) async =>
        _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [
                      for (final index in indexes)
                        chatMessageJson(index, 'x', _peer.nickname),
                    ],
                  ),
                ),
              ),
            ),
            offset: offset,
          ),
        );

    test('contiguous from the offset', () async {
      final page = await pageOf([4, 5, 6], offset: 3);
      expect(page.isContiguous, isTrue);
      expect(page.inIndexOrder, isTrue);
      expect(page.repeatsAnIndex, isFalse);
      expect(page.lastIndex, 6);
      expect(page.offset, 3);
    });

    test('an empty page: last index is the offset', () async {
      final page = await pageOf([], offset: 9);
      expect(page.messages, isEmpty);
      expect(page.lastIndex, 9);
      expect(page.isContiguous, isTrue);
      expect(page.inIndexOrder, isTrue);
      expect(page.repeatsAnIndex, isFalse);
    });

    test(
      'reordered: delivered in the coordinator order, said out of order',
      () async {
        final page = await pageOf([2, 1, 3]);
        expect(page.messages.map((m) => m.index), [2, 1, 3]);
        expect(page.inIndexOrder, isFalse);
        expect(page.isContiguous, isFalse);
        expect(page.repeatsAnIndex, isFalse);
        expect(page.lastIndex, 3);
      },
    );

    test(
      'a repeated index (two posts at once on the reference, or a replay): both delivered, said repeated',
      () async {
        final page = await pageOf([1, 2, 2, 4]);
        expect(page.messages, hasLength(4));
        expect(page.repeatsAnIndex, isTrue);
        expect(page.inIndexOrder, isFalse);
        expect(page.isContiguous, isFalse);
      },
    );

    test(
      'a gap (a message dropped, or skipped by the numbering): said not contiguous',
      () async {
        final page = await pageOf([1, 3]);
        expect(page.inIndexOrder, isTrue);
        expect(page.repeatsAnIndex, isFalse);
        expect(page.isContiguous, isFalse);
        final late = await pageOf([5, 6], offset: 3);
        expect(late.isContiguous, isFalse);
        expect(late.inIndexOrder, isTrue);
      },
    );

    test('the messages cannot be changed', () async {
      final page = await pageOf([1]);
      expect(
        () => page.messages.add(page.messages.first),
        throwsUnsupportedError,
      );
    });
  });

  group('who sent a message', () {
    test(
      'as taker: own nick is self, the maker is the peer, any other nick is unknown',
      () async {
        final page = _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(
                    messages: [
                      chatMessageJson(1, 'x', _us.nickname),
                      chatMessageJson(2, 'x', _peer.nickname),
                      chatMessageJson(3, 'x', _stranger.nickname),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(page.messages.map((m) => m.sender), [
          ChatSender.self,
          ChatSender.peer,
          ChatSender.unknown,
        ]);
        expect(page.messages.map((m) => m.nick), [
          _us.nickname,
          _peer.nickname,
          _stranger.nickname,
        ]);
      },
    );

    test('as maker: the taker is the peer', () async {
      final page = _pageOk(
        await _fetch(
          _answering(
            Ok(
              jsonResponse(
                _page(
                  peerPubkey: _peerKey.publicKey.armored,
                  messages: [
                    chatMessageJson(1, 'x', _us.nickname),
                    chatMessageJson(2, 'x', _peer.nickname),
                  ],
                ),
              ),
            ),
          ),
          lastRead: await _readAt(9, asMaker: true),
        ),
      );
      expect(page.messages.map((m) => m.sender), [
        ChatSender.self,
        ChatSender.peer,
      ]);
      expect(page.peerKey, isA<ChatPeerKeyOfPeer>());
    });
  });

  group("the peer's key", () {
    Future<ChatPeerKey> keyOf(Object? peerPubkey, {bool omit = false}) async {
      final body = _page(peerPubkey: peerPubkey);
      if (omit) body.remove('peer_pubkey');
      return _pageOk(await _fetch(_answering(Ok(jsonResponse(body))))).peerKey;
    }

    test(
      'named after the peer: given, equal to the key read from its armor, with line feeds or backslashes',
      () async {
        final key = await keyOf(_peerKey.publicKey.armored);
        expect(
          key,
          isA<ChatPeerKeyOfPeer>().having(
            (k) => k.key,
            'key',
            _peerKey.publicKey,
          ),
        );
        final fromWire = await keyOf(
          referenceToWire(_peerKey.publicKey.armored),
        );
        expect(
          fromWire,
          isA<ChatPeerKeyOfPeer>().having(
            (k) => k.key,
            'key',
            _peerKey.publicKey,
          ),
        );
      },
    );

    test(
      "the coordinator's own robot's key, or this robot's own, is misnamed",
      () async {
        expect(
          await keyOf(_strangerKey.publicKey.armored),
          isA<ChatPeerKeyMisnamed>().having(
            (k) => k.key.fingerprint,
            'fingerprint',
            _strangerKey.publicKey.fingerprint,
          ),
        );
        expect(
          await keyOf(_usKey.publicKey.armored),
          isA<ChatPeerKeyMisnamed>(),
        );
      },
    );

    test(
      'a key the coordinator made and named after the peer reads as the peer\'s: only the pinned fingerprint tells',
      () async {
        final pinned = await keyOf(_peerKey.publicKey.armored);
        final replaced = await keyOf(_forgedPeerKey.publicKey.armored);
        expect(replaced, isA<ChatPeerKeyOfPeer>());
        expect(
          (replaced as ChatPeerKeyOfPeer).key,
          isNot((pinned as ChatPeerKeyOfPeer).key),
        );
        expect(replaced.key.fingerprint, isNot(pinned.key.fingerprint));
      },
    );

    test('absent, null or empty: missing', () async {
      expect(await keyOf(null), isA<ChatPeerKeyMissing>());
      expect(await keyOf('', omit: false), isA<ChatPeerKeyMissing>());
      expect(await keyOf(null, omit: true), isA<ChatPeerKeyMissing>());
    });

    test(
      'not a key, or over 20,000 characters: unreadable, with the reason and without the text',
      () async {
        expect(
          await keyOf('None'),
          isA<ChatPeerKeyUnreadable>().having(
            (k) => k.reason,
            'reason',
            isA<PgpArmorMalformed>(),
          ),
        );
        expect(
          await keyOf(
            '-----BEGIN PGP PUBLIC KEY BLOCK-----\\\\AAAA\\-----END PGP PUBLIC KEY BLOCK-----',
          ),
          isA<ChatPeerKeyUnreadable>(),
        );
        expect(
          await keyOf('A' * 20001),
          isA<ChatPeerKeyUnreadable>().having(
            (k) => k.reason,
            'reason',
            isA<PgpInputTooLarge>(),
          ),
        );
        final armored = _peerKey.publicKey.armored;
        final padded = armored.replaceFirst(
          '\n\n',
          '\nComment: ${'x' * (20000 - armored.length - 10)}\n\n',
        );
        expect(padded.length, lessThanOrEqualTo(20000));
        expect(await keyOf(padded), isA<ChatPeerKeyOfPeer>());
      },
    );
  });

  group('the line-break rule', () {
    // Strings over the characters that matter: line feed, backslash, armor characters; no carriage return, which this package's armor never holds (see below).
    String randomText(Random random) {
      const alphabet = 'aZ09+/=-\n\\ ';
      return String.fromCharCodes([
        for (var i = random.nextInt(40); i > 0; i--)
          alphabet.codeUnitAt(random.nextInt(alphabet.length)),
      ]);
    }

    test("both ways, the package's rule is the reference's on random text", () {
      final random = Random(92);
      for (var i = 0; i < 2000; i++) {
        final text = randomText(random);
        expect(
          pgpArmorToWire(text),
          referenceToWire(text),
          reason: jsonEncode(text),
        );
        expect(
          pgpArmorFromWire(text),
          referenceFromWire(text),
          reason: jsonEncode(text),
        );
      }
    });

    test(
      'an armored message goes there and back unchanged, with a backslash per line feed and none left',
      () {
        final message = _outgoing('Line one\nLine two\n\nLine four');
        expect(message.armored.endsWith('-----END PGP MESSAGE-----\n'), isTrue);
        expect(message.wire.endsWith(r'-----END PGP MESSAGE-----\'), isTrue);
        expect(
          r'\'.allMatches(message.wire).length,
          '\n'.allMatches(message.armored).length,
        );
        expect(message.wire, isNot(contains('\n')));
        expect(referenceFromWire(message.wire), message.armored);
        expect(pgpArmorFromWire(message.wire), message.armored);
      },
    );

    test(
      'a text with backslashes goes through encrypted: the rule never touches the plaintext',
      () {
        const text =
            r'C:\Users\me\n is not a line break \\ two'
            '\nreal line';
        final unlocked = _usKey.unlockedFor(_us);
        final message = _outgoing(text, key: unlocked);
        final read = expectOk(
          _peerKey
              .unlockedFor(_peer)
              .decryptChatMessage(
                referenceFromWire(message.wire),
                sender: _usKey.publicKey,
                now: _now,
              ),
        );
        expect(read.text, text);
        expect(read.validSignature, isTrue);
      },
    );

    test(
      'a received text with a backslash becomes a line feed, exactly as the reference reads it',
      () async {
        const wire =
            '-----BEGIN PGP MESSAGE-----\\\\abc\\def\nghi\\-----END PGP MESSAGE-----\\';
        final page = _pageOk(
          await _fetch(
            _answering(
              Ok(
                jsonResponse(
                  _page(messages: [chatMessageJson(1, wire, _peer.nickname)]),
                ),
              ),
            ),
          ),
        );
        expect(page.messages.single.armored, referenceFromWire(wire));
      },
    );

    test(
      'the one-line form cannot carry a backslash or a carriage return both ways, so an outgoing message never holds one',
      () {
        // `a\b` and `a` LF `b` have the same one-line form: the rule is not reversible on a text with a backslash.
        expect(referenceToWire(r'a\b'), referenceToWire('a\nb'));
        for (final armored in [
          '-----BEGIN PGP MESSAGE-----\n\nab\\c\n-----END PGP MESSAGE-----\n',
          '-----BEGIN PGP MESSAGE-----\r\n\r\nabc\r\n-----END PGP MESSAGE-----\r\n',
        ]) {
          expect(
            expectErr(
              OutgoingChatMessage.fromArmored(
                armored,
                sender: _us.hashId,
                peerFingerprint: 'F' * 40,
              ),
            ),
            isA<PgpArmorMalformed>(),
          );
        }
        // The package's rule turns CR LF into LF before; the reference's chat leaves a carriage return, which its armor never holds either, and which the armor reader drops.
        expect(pgpArmorToWire('a\r\nb'), r'a\b');
      },
    );
  });

  group('the outgoing message', () {
    test('bound to its robot and peer key, printed without its text', () {
      final message = _outgoing('secret plan');
      expect(message.sender, _us.hashId);
      expect(message.peerFingerprint, _peerKey.publicKey.fingerprint);
      expect(message.toString(), isNot(contains('BEGIN')));
      expect(message.toString(), isNot(contains('secret')));
      expect(message.toString(), contains('${message.wire.length} characters'));
    });

    test('the token is refused, as the official client refuses it', () {
      expect(
        expectErr(
          _usKey
              .unlockedFor(_us)
              .encryptChatMessageToPost(
                'my token is ${_us.token.reveal()}',
                peer: _peerKey.publicKey,
                now: _now,
              ),
        ),
        isA<PgpPlaintextContainsToken>(),
      );
    });

    test('a peer key out of date is refused', () {
      expect(
        expectErr(
          _usKey
              .unlockedFor(_us)
              .encryptChatMessageToPost(
                'hi',
                peer: _peerKey.publicKey,
                now: DateTime.utc(2026, 11, 1),
              ),
        ),
        isA<PgpKeyOutOfDate>(),
      );
    });

    test(
      'at most 5,000 characters on the wire: the longest text that always fits, and one that never does',
      () {
        final unlocked = _usKey.unlockedFor(_us);
        final random = Random(5000);
        String asciiText(int length) => String.fromCharCodes([
          for (var i = 0; i < length; i++) 0x21 + random.nextInt(94),
        ]);
        for (var round = 0; round < 8; round++) {
          final fits = expectOk(
            unlocked.encryptChatMessageToPost(
              asciiText(_longestFittingBytes),
              peer: _peerKey.publicKey,
              now: _now,
            ),
          );
          expect(
            fits.wire.length,
            lessThanOrEqualTo(OutgoingChatMessage.maxWireChars),
          );
          expect(
            expectErr(
              unlocked.encryptChatMessageToPost(
                asciiText(_longestFittingBytes + 50),
                peer: _peerKey.publicKey,
                now: _now,
              ),
            ),
            isA<ChatRefused>().having(
              (f) => f.reason,
              'reason',
              ChatRefusal.messageTooLong,
            ),
          );
        }
        // The design note's 4,000 characters do not fit.
        expect(
          expectErr(
            unlocked.encryptChatMessageToPost(
              asciiText(4000),
              peer: _peerKey.publicKey,
              now: _now,
            ),
          ),
          isA<ChatRefused>(),
        );
      },
    );

    test('exactly 5,000 characters is the bound', () {
      String armorOfWireLength(int length) {
        const head = '-----BEGIN PGP MESSAGE-----\n\n';
        const tail = '\n-----END PGP MESSAGE-----\n';
        return head + 'A' * (length - head.length - tail.length) + tail;
      }

      expect(
        expectOk(
          OutgoingChatMessage.fromArmored(
            armorOfWireLength(5000),
            sender: _us.hashId,
            peerFingerprint: 'F' * 40,
          ),
        ).wire.length,
        5000,
      );
      expect(
        expectErr(
          OutgoingChatMessage.fromArmored(
            armorOfWireLength(5001),
            sender: _us.hashId,
            peerFingerprint: 'F' * 40,
          ),
        ),
        isA<ChatRefused>().having(
          (f) => f.reason,
          'reason',
          ChatRefusal.messageTooLong,
        ),
      );
    });
  });

  group('a whole exchange through a coordinator that behaves as the reference', () {
    late UnlockedRobotPgpKey usUnlocked;
    late UnlockedRobotPgpKey peerUnlocked;
    late RobotPgpKey usPair;
    late RobotPgpKey peerPair;

    setUpAll(() {
      // The keys `RobotPgpKey.generate` makes for the two robots, with a fixed clock and randomness: 32 MiB of SHA-256 each to unlock.
      usPair = generateInteropKey();
      peerPair = generateInteropPeerKey();
      usUnlocked = expectOk(usPair.unlock(_us));
      peerUnlocked = expectOk(peerPair.unlock(_peer));
    });

    ReferenceChatCoordinator coordinator() => ReferenceChatCoordinator(
      maker: _peer,
      taker: _us,
      makerPublicKey: peerPair.publicKey.armored,
      takerPublicKey: usPair.publicKey.armored,
    );

    test(
      'A encrypts and posts, B reads and decrypts, the signature verifies with A\'s key only',
      () async {
        final reference = coordinator();
        final transport = FakeCoordinatorTransport();
        reference.serve(transport);
        final client = CoordinatorClient(transport);
        final usRead = await _readAt(9);
        final peerRead = await readChatOrder(
          chatOrderAnswer(9, reader: _peer, maker: _peer, taker: _us),
          _peer,
        );

        // A (the taker) reads first: no message yet, B's key named after B.
        final first = expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        expect(first.messages, isEmpty);
        final pinned = switch (first.peerKey) {
          ChatPeerKeyOfPeer(:final key) => key,
          final other => fail('expected the peer key, got $other'),
        };
        expect(pinned, peerPair.publicKey);

        const text = 'Hola, envío 50 € por Bizum ⚡\nIBAN to follow \\ thanks';
        final message = expectOk(
          usUnlocked.encryptChatMessageToPost(
            text,
            peer: pinned,
            now: interopReplayTime,
          ),
        );
        final echo = expectOk(
          await client.postChat(
            identity: _us,
            lastRead: usRead,
            message: message,
            offset: first.lastIndex,
          ),
        );
        expect(reference.stored.single['message'], message.wire);
        expect(echo.indexOf(message), 1);
        expect(echo.messages.single.sender, ChatSender.self);
        expect(echo.isContiguous, isTrue);

        // A reads its own message back with its own key.
        final own = expectOk(
          usUnlocked.decryptChatMessage(
            echo.messages.single.armored ?? '',
            sender: usPair.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(own.text, text);
        expect(own.validSignature, isTrue);

        // B (the maker) reads it as the peer's and checks it with A's key, which its page names after A.
        final page = expectOk(
          await client.fetchChat(
            identity: _peer,
            lastRead: peerRead,
            offset: 0,
          ),
        );
        final read = page.messages.single;
        expect(read.sender, ChatSender.peer);
        expect(read.index, 1);
        final aKey = switch (page.peerKey) {
          ChatPeerKeyOfPeer(:final key) => key,
          final other => fail('expected the peer key, got $other'),
        };
        expect(aKey, usPair.publicKey);
        final decrypted = expectOk(
          peerUnlocked.decryptChatMessage(
            read.armored ?? '',
            sender: aKey,
            now: interopReplayTime,
          ),
        );
        expect(decrypted.text, text);
        expect(decrypted.validSignature, isTrue);

        // With another key, the text still decrypts but the signature does not verify.
        final withOther = expectOk(
          peerUnlocked.decryptChatMessage(
            read.armored ?? '',
            sender: _forgedPeerKey.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(withOther.text, text);
        expect(withOther.validSignature, isFalse);

        // B answers; A polls from its last index and gets only the new message.
        final answer = expectOk(
          peerUnlocked.encryptChatMessageToPost(
            'Recibido',
            peer: aKey,
            now: interopReplayTime,
          ),
        );
        expectOk(
          await client.postChat(
            identity: _peer,
            lastRead: peerRead,
            message: answer,
            offset: page.lastIndex,
          ),
        );
        final next = expectOk(
          await client.fetchChat(
            identity: _us,
            lastRead: usRead,
            offset: echo.lastIndex,
          ),
        );
        expect(next.messages.map((m) => m.index), [2]);
        expect(next.isContiguous, isTrue);
        expect(next.messages.single.sender, ChatSender.peer);
        final reply = expectOk(
          usUnlocked.decryptChatMessage(
            next.messages.single.armored ?? '',
            sender: pinned,
            now: interopReplayTime,
          ),
        );
        expect(reply.text, 'Recibido');
        expect(reply.validSignature, isTrue);
      },
    );

    test(
      'the coordinator refuses as the reference: 6002 past the chat, 6001 for a robot it does not know as a participant',
      () async {
        final reference = coordinator()..status = 9;
        final transport = FakeCoordinatorTransport();
        reference.serve(transport);
        final client = CoordinatorClient(transport);
        final usRead = await _readAt(9);
        reference.status = 13;
        expect(
          expectErr(
            await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
          ),
          _chatRefused(ChatRefusal.notInChat),
        );
        reference.status = 11;
        expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        final message = expectOk(
          usUnlocked.encryptChatMessageToPost(
            'x',
            peer: peerPair.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(
          expectErr(
            await client.postChat(
              identity: _us,
              lastRead: usRead,
              message: message,
              offset: 0,
            ),
          ),
          isA<OrderActionRefused>().having(
            (f) => f.cause,
            'cause',
            _chatRefused(ChatRefusal.notInChat),
          ),
        );
        expect(reference.stored, isEmpty);
      },
    );

    test(
      "hostile: the peer's key replaced by the coordinator's own robot's, or by a key it made in the peer's name",
      () async {
        final reference = coordinator();
        final transport = FakeCoordinatorTransport();
        reference.serve(transport);
        final client = CoordinatorClient(transport);
        final usRead = await _readAt(9);
        final peerRead = await readChatOrder(
          chatOrderAnswer(9, reader: _peer, maker: _peer, taker: _us),
          _peer,
        );
        final pinned = switch (expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        ).peerKey) {
          ChatPeerKeyOfPeer(:final key) => key,
          final other => fail('expected the peer key, got $other'),
        };
        final fromPeer = expectOk(
          peerUnlocked.encryptChatMessageToPost(
            'pay to IBAN X',
            peer: usPair.publicKey,
            now: interopReplayTime,
          ),
        );
        expectOk(
          await client.postChat(
            identity: _peer,
            lastRead: peerRead,
            message: fromPeer,
            offset: 0,
          ),
        );

        // Its own robot's key: misnamed, another fingerprint.
        reference.tamper = (page, to) => {
          ...page,
          'peer_pubkey': _strangerKey.publicArmored,
        };
        final misnamed = expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        expect(
          misnamed.peerKey,
          isA<ChatPeerKeyMisnamed>().having(
            (k) => k.key == pinned,
            'equal to the pinned key',
            isFalse,
          ),
        );

        // A key it made in the peer's name: named after the peer, but not the pinned one, and the peer's real messages do not verify with it.
        reference.tamper = (page, to) => {
          ...page,
          'peer_pubkey': _forgedPeerKey.publicArmored,
        };
        final forged = expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        final forgedKey = (forged.peerKey as ChatPeerKeyOfPeer).key;
        expect(forgedKey == pinned, isFalse);
        expect(forgedKey.fingerprint, isNot(pinned.fingerprint));
        final checked = expectOk(
          usUnlocked.decryptChatMessage(
            forged.messages.single.armored ?? '',
            sender: forgedKey,
            now: interopReplayTime,
          ),
        );
        expect(checked.validSignature, isFalse);
        expect(
          expectOk(
            usUnlocked.decryptChatMessage(
              forged.messages.single.armored ?? '',
              sender: pinned,
              now: interopReplayTime,
            ),
          ).validSignature,
          isTrue,
        );
      },
    );

    test(
      'hostile: a message replayed at a second index, a reordered page, a message given to an unknown nick',
      () async {
        final reference = coordinator();
        final transport = FakeCoordinatorTransport();
        reference.serve(transport);
        final client = CoordinatorClient(transport);
        final usRead = await _readAt(9);
        final peerRead = await readChatOrder(
          chatOrderAnswer(9, reader: _peer, maker: _peer, taker: _us),
          _peer,
        );
        final m1 = expectOk(
          peerUnlocked.encryptChatMessageToPost(
            'one',
            peer: usPair.publicKey,
            now: interopReplayTime,
          ),
        );
        final m2 = expectOk(
          peerUnlocked.encryptChatMessageToPost(
            'two',
            peer: usPair.publicKey,
            now: interopReplayTime,
          ),
        );
        expectOk(
          await client.postChat(
            identity: _peer,
            lastRead: peerRead,
            message: m1,
            offset: 0,
          ),
        );
        expectOk(
          await client.postChat(
            identity: _peer,
            lastRead: peerRead,
            message: m2,
            offset: 0,
          ),
        );

        reference.tamper = (page, to) {
          final messages = [
            ...(page['messages'] as List<Map<String, Object?>>),
          ];
          return {
            ...page,
            'messages': [
              messages[1],
              messages[0],
              {...messages[0], 'index': 3},
              {...messages[1], 'index': 4, 'nick': _stranger.nickname},
            ],
          };
        };
        final page = expectOk(
          await client.fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        expect(page.messages.map((m) => m.index), [2, 1, 3, 4]);
        expect(page.inIndexOrder, isFalse);
        expect(page.isContiguous, isFalse);
        expect(page.messages.last.sender, ChatSender.unknown);
        // The replay at index 3 decrypts to the same text as index 1, validly signed: keyed by index, first seen kept, the caller sees the same ciphertext twice.
        final texts = [
          for (final message in page.messages)
            expectOk(
              usUnlocked.decryptChatMessage(
                message.armored ?? '',
                sender: peerPair.publicKey,
                now: interopReplayTime,
              ),
            ).text,
        ];
        expect(texts, ['two', 'one', 'one', 'two']);
        expect(page.messages[2].armored, page.messages[1].armored);
      },
    );

    test(
      'a post whose answer is lost: read again from the same offset and find it by its text',
      () async {
        final reference = coordinator();
        final transport = FakeCoordinatorTransport();
        reference.serve(transport);
        final usRead = await _readAt(9);
        final message = expectOk(
          usUnlocked.encryptChatMessageToPost(
            'did it arrive?',
            peer: peerPair.publicKey,
            now: interopReplayTime,
          ),
        );

        // The coordinator stores the message, then the answer is lost.
        final losing = FakeCoordinatorTransport()
          ..route(chatCoordinator, chatNetwork, '/api/chat/', (request) async {
            await transport.send(request);
            return const Err(CoordinatorTimedOut());
          });
        final lost = expectErr(
          await CoordinatorClient(losing).postChat(
            identity: _us,
            lastRead: usRead,
            message: message,
            offset: 0,
          ),
        );
        expect(lost, isA<OrderActionOutcomeUnknown>());
        expect(losing.requests, hasLength(1));
        expect(reference.stored, hasLength(1));

        final again = expectOk(
          await CoordinatorClient(
            transport,
          ).fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        expect(again.indexOf(message), 1);

        // A message attributed to the peer, or another text, is not it.
        final other = expectOk(
          usUnlocked.encryptChatMessageToPost(
            'did it arrive?',
            peer: peerPair.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(again.indexOf(other), isNull);
        reference.tamper = (page, to) => {
          ...page,
          'messages': [
            for (final m in page['messages'] as List<Map<String, Object?>>)
              {...m, 'nick': _peer.nickname},
          ],
        };
        final relabelled = expectOk(
          await CoordinatorClient(
            transport,
          ).fetchChat(identity: _us, lastRead: usRead, offset: 0),
        );
        expect(relabelled.indexOf(message), isNull);
      },
    );
  });

  group(
    'nothing of the coordinator, the peer or the chat in a failure, a toString or a print',
    () {
      test('random answers', () async {
        final random = Random(6000);
        final marker = 'MARKER-${random.nextInt(1 << 30)}';
        final markedKey = CraftedKey(
          label: 'chat-marked',
          userId: 'RoboSats ID $marker',
        ).publicArmored;
        final message = _outgoing('plaintext $marker');
        final secretParts = [
          marker,
          message.wire.substring(30, 90),
          'plaintext',
        ];
        Object? randomJson(int depth) => switch (random.nextInt(
          depth > 2 ? 4 : 7,
        )) {
          0 => marker,
          1 => random.nextInt(10000) - 10,
          2 => random.nextBool(),
          3 => null,
          4 => [
            for (var i = random.nextInt(3); i > 0; i--) randomJson(depth + 1),
          ],
          5 => {
            for (var i = random.nextInt(3); i > 0; i--)
              '$marker$i': randomJson(depth + 1),
          },
          _ => '-----BEGIN PGP MESSAGE-----$marker',
        };
        Map<String, Object?> randomPage() => {
          'peer_connected': random.nextInt(5) == 0 ? marker : random.nextBool(),
          'messages': [
            for (var i = random.nextInt(4); i > 0; i--)
              {
                'index': random.nextInt(6),
                'time': random.nextBool() ? '2026-11-13T09:00:00Z' : marker,
                'message': [
                  marker,
                  message.wire,
                  '-----BEGIN PGP MESSAGE-----\\$marker',
                  randomJson(0),
                ][random.nextInt(4)],
                'nick': [
                  _us.nickname,
                  _peer.nickname,
                  marker,
                  'Nick-$i',
                ][random.nextInt(4)],
                if (random.nextBool()) marker: marker,
              },
          ],
          'peer_pubkey': [
            null,
            marker,
            markedKey,
            _peerKey.publicKey.armored,
            randomJson(0),
          ][random.nextInt(5)],
          if (random.nextBool()) 'detail': marker,
        };
        Object? randomBody() => switch (random.nextInt(4)) {
          0 => {
            'error_code': [
              6000,
              6001,
              6002,
              6003,
              7000,
              7001,
              7003,
              1042,
              random.nextInt(99999),
            ][random.nextInt(9)],
            'bad_request': marker,
          },
          1 => randomPage(),
          2 => randomJson(0),
          _ => {'bad_request': marker, 'detail': marker},
        };
        const statuses = [200, 200, 200, 400, 401, 403, 404, 409, 500, 502];
        final printed = <String>[];
        final lastRead = await _readAt(9);
        await runZoned(
          () async {
            for (var i = 0; i < 400; i++) {
              final status = statuses[random.nextInt(statuses.length)];
              final response = random.nextInt(10) == 0
                  ? rawResponse(
                      utf8.encode('$marker ${message.wire}'),
                      statusCode: status,
                    )
                  : jsonResponse(randomBody(), statusCode: status);
              final transport = _answering(Ok(response));
              final fetched = await CoordinatorClient(transport).fetchChat(
                identity: _us,
                lastRead: lastRead,
                offset: random.nextInt(3),
              );
              final posted = await CoordinatorClient(transport).postChat(
                identity: _us,
                lastRead: lastRead,
                message: message,
                offset: random.nextInt(3),
              );
              final shown = <String>[
                '$fetched',
                '$posted',
                ...switch (fetched) {
                  Ok(value: final page) => [
                    '$page',
                    '${page.peerKey}',
                    for (final m in page.messages) '$m',
                  ],
                  Err(:final failure) => ['$failure'],
                },
                ...switch (posted) {
                  Ok(value: final page) => [
                    '$page',
                    '${page.peerKey}',
                    for (final m in page.messages) '$m',
                  ],
                  Err(:final failure) => ['$failure', '${failure.cause}'],
                },
                '$message',
              ];
              for (final text in shown) {
                for (final secret in secretParts) {
                  expect(
                    text,
                    isNot(contains(secret)),
                    reason: 'round $i: $text',
                  );
                }
              }
            }
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => printed.add(line),
          ),
        );
        expect(printed, isEmpty);
      });
    },
  );
}

const _remove = Object();

Matcher _chatRefused(ChatRefusal reason) =>
    isA<ChatRefused>().having((f) => f.reason, 'reason', reason);

/// A text of this many bytes of UTF-8 always fits in [OutgoingChatMessage.maxWireChars] once encrypted by a robot's key to one peer, and one of 50 more never does.
///
/// Measured with keys of the official client's shape (generated by this package, and crafted): 574 characters for an empty text, then about 1.34 per byte; 3,250 bytes take 4,982 characters, 3,300 take 5,051, and the signature's integers make a message vary by at most 4 characters.
const _longestFittingBytes = 3250;
