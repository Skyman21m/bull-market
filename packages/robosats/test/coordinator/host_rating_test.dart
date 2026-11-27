import 'dart:convert';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../support/coordinator.dart';
import '../support/nip59.dart';
import '../support/order_answers.dart';
import '../support/pgp.dart';

/// « Rate your host » (#95): the token of `POST /api/review/` (`Robot.loadReviewToken`, `frontend/src/models/Robot.model.ts:220-245`; `ReviewView`, `api/views.py:1236-1269`) and the event of kind 31986 (`rateHostPlatform`, `frontend/src/components/TradeBox/Prompts/Successful.tsx:54-89`), commit ff1998c.
void main() {
  final us = interopIdentity;
  final temple = coordinatorNamed('temple');
  const network = RobosatsNetwork.testnet;

  // Made with `nostr-tools` 2.25.2 and `@noble/curves` 2.0.1, off the repository: a test key signed `<our Nostr key>42` as `api/nostr.py` signs it, and `finalizeEvent` gave these ids for the robot of the fixtures, `created_at` 1794830400 (2026-11-16 12:00:00.750 UTC rounded down) and the tags of the reference.
  const token =
      '2c523b2ad31fd3ede49eb3fcf537f21d6cca0b8e5ff114ab55c8a923b83443103fa2dc90fd6fad198112035f8aaff129a7faa71d8e17693b124bc2eebcfe8f55';
  const idsOfNostrTools = {
    1: '330b4c44c56d5e4f68cff060b4cb1ecd09166af9c7ff5250ecf55adf5df7b53f',
    2: 'd050fb84651207246dbd2417ba5b2936e5d826e4b2f2e0db4add6b13a5dcd695',
    3: '57b9e55f1c2fa74a2c23b41e365d77c1ad8f1586d6740d3279726224592bf941',
    4: 'bc27ec75ecb9656723e8973bf91cb2ae6f70786ac92d5f4b135c329e58604ac1',
    5: 'd504b1a44cf05821ad12bd65bb7e60f09ef7dfe3de71ac08fbcdac81c43f4fe5',
  };
  final now = DateTime.utc(2026, 11, 16, 12, 0, 0, 750);

  HostReviewToken tokenOf(String value) =>
      switch (HostReviewToken.parse(value)) {
        final parsed? => parsed,
        null => throw StateError('not a token'),
      };

  HostRating ratingOf(int stars) => switch (HostRating.of(stars)) {
    final rating? => rating,
    null => throw StateError('not a rating'),
  };

  OutgoingHostRating compose(int stars) => OutgoingHostRating.compose(
    us.nostrKeyPair(),
    token: tokenOf(token),
    coordinator: temple,
    orderId: testOrderId,
    rating: ratingOf(stars),
    now: now,
    random: DeterministicRandom('host rating'),
  );

  group('the token', () {
    test(
      'is 128 lowercase hexadecimal characters, as signature.hex() writes it',
      () {
        expect(HostReviewToken.parse(token)?.hex, token);
        expect(HostReviewToken.parse(token.toUpperCase()), isNull);
        expect(HostReviewToken.parse(token.substring(1)), isNull);
        expect(HostReviewToken.parse('${token}0'), isNull);
        expect(HostReviewToken.parse('${token.substring(1)}g'), isNull);
        expect(HostReviewToken.parse('${token.substring(2)}\n'), isNull);
        expect(HostReviewToken.parse(''), isNull);
        expect(HostReviewToken.parse(null), isNull);
        expect(HostReviewToken.parse(42), isNull);
      },
    );

    test('prints nothing of itself', () {
      expect('${tokenOf(token)}', isNot(contains(token.substring(0, 8))));
    });
  });

  group('the rating', () {
    test('has one to five stars', () {
      expect(HostRating.of(0), isNull);
      expect(HostRating.of(6), isNull);
      expect(
        [for (var s = 1; s <= 5; s++) HostRating.of(s)?.stars],
        [1, 2, 3, 4, 5],
      );
    });

    test('is tagged as String(stars / 5) of JavaScript', () {
      expect(
        [for (var s = 1; s <= 5; s++) ratingOf(s).tagValue],
        ['0.2', '0.4', '0.6', '0.8', '1'],
      );
    });
  });

  group('the event', () {
    test(
      'is the reference\'s, field for field, signed by the robot\'s Nostr key',
      () {
        final rating = compose(4);
        final message = rating.relayMessages.single;
        // The fields in the order of the reference's template, which `finalizeEvent` fills in place.
        expect(
          message,
          startsWith(
            '["EVENT",{"kind":31986,"created_at":1794830400,"tags":[["sig",',
          ),
        );
        expect(
          message,
          contains(
            '"]],"content":"","pubkey":"${us.nostrKeyPair().publicKeyHex}","id":"',
          ),
        );
        final json = message.substring('["EVENT",'.length, message.length - 1);
        final event = readEvent(json, signed: true);
        expect(event['kind'], 31986);
        expect(event['content'], '');
        expect(event['created_at'], 1794830400);
        expect(event['pubkey'], us.nostrKeyPair().publicKeyHex);
        expect(event['tags'], [
          ['sig', token],
          ['d', 'temple:$testOrderId'],
          ['p', temple.nostrHexPubkey],
          ['rating', '0.8'],
        ]);
        expect(rating.eventIds, [event['id']]);
        expect(jsonDecode(message), hasLength(2));
      },
    );

    test('has the id nostr-tools gives it, for each number of stars', () {
      for (final MapEntry(key: stars, value: id) in idsOfNostrTools.entries) {
        expect(compose(stars).eventIds, [id], reason: '$stars stars');
      }
    });

    test('is dated at the second, rounded down', () {
      final late = OutgoingHostRating.compose(
        us.nostrKeyPair(),
        token: tokenOf(token),
        coordinator: temple,
        orderId: testOrderId,
        rating: ratingOf(5),
        now: DateTime.utc(2026, 11, 16, 12, 0, 0, 999),
        random: DeterministicRandom('host rating'),
      );
      expect(late.event.createdAt, 1794830400);
      expect(late.eventIds, [idsOfNostrTools[5]]);
    });

    test('prints nothing of the token, the robot or the rating', () {
      expect('${compose(5)}', 'OutgoingHostRating');
    });
  });

  group('POST /api/review/', () {
    late FakeCoordinatorTransport transport;
    late CoordinatorClient client;

    setUp(() {
      transport = FakeCoordinatorTransport();
      client = CoordinatorClient(transport);
    });

    void serve(
      Result<CoordinatorResponse, CoordinatorTransportFailure> answer,
    ) => transport.answer(temple, network, '/api/review/', answer);

    Future<Result<HostReviewToken, CoordinatorFailure>> ask() =>
        client.fetchReviewToken(
          identity: us,
          key: interopUnlockedKey,
          coordinator: temple,
          network: network,
          nostrPublicKeyHex: us.nostrKeyPair().publicKeyHex,
        );

    test(
      'sends the robot\'s Nostr key with its short header, as the reference',
      () async {
        serve(Ok(jsonResponse({'pubkey': 'x', 'token': token})));
        expect(await ask(), isA<Ok<HostReviewToken, CoordinatorFailure>>());
        final request = transport.requests.single;
        expect(request.method, CoordinatorHttpMethod.post);
        expect(request.url.toString(), '${temple.testnet.onion}/api/review/');
        expect(request.headers, {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Authorization': us.authorizationHeader(),
        });
        // Then the signature of `review:{pubkey}`, last (GHSA-22q8-9ghc-jg3h).
        final pubkey = us.nostrKeyPair().publicKeyHex;
        expect(
          unsignedBody(request.body, 'review:$pubkey'),
          jsonEncode({'pubkey': pubkey}),
        );
        expect(request.robot, us.sessionKey);
        expect(request.maxResponseBytes, CoordinatorReadBounds.reviewBytes);
      },
    );

    test('gives the token of a 200', () async {
      serve(Ok(jsonResponse({'pubkey': 'x', 'token': token})));
      expect(expectOk(await ask()), tokenOf(token));
    });

    test(
      'refuses a token of another form: nothing of it reaches an event',
      () async {
        for (final wrong in <Object?>[
          '',
          token.toUpperCase(),
          '$token ',
          '${token.substring(2)}"]',
          null,
          128,
        ]) {
          serve(Ok(jsonResponse({'token': wrong})));
          expect(
            await ask(),
            isA<Err<HostReviewToken, CoordinatorFailure>>().having(
              (e) => e.failure,
              'failure',
              isA<CoordinatorResponseMalformed>(),
            ),
            reason: '$wrong',
          );
        }
        serve(Ok(jsonResponse({'pubkey': 'x'})));
        expect(
          await ask(),
          isA<Err<HostReviewToken, CoordinatorFailure>>(),
          reason: 'a 200 without a token',
        );
        serve(Ok(jsonResponse([token])));
        expect(
          await ask(),
          isA<Err<HostReviewToken, CoordinatorFailure>>(),
          reason: 'not an object',
        );
      },
    );

    test(
      'reads a 400 (1052) as an unexpected status, its text never kept',
      () async {
        serve(
          Ok(
            jsonResponse({
              'bad_request': 'Robot has no finished order',
            }, statusCode: 400),
          ),
        );
        expect(
          await ask(),
          isA<Err<HostReviewToken, CoordinatorFailure>>().having(
            (e) => e.failure,
            'failure',
            isA<CoordinatorUnexpectedStatus>().having(
              (f) => f.statusCode,
              'statusCode',
              400,
            ),
          ),
        );
      },
    );

    test('says a transport failure, an error thrown included', () async {
      serve(const Err(CoordinatorTimedOut()));
      expect(
        await ask(),
        isA<Err<HostReviewToken, CoordinatorFailure>>().having(
          (e) => e.failure,
          'failure',
          isA<CoordinatorTimedOut>(),
        ),
      );
      transport.route(
        temple,
        network,
        '/api/review/',
        (_) => throw StateError('broken'),
      );
      expect(
        await ask(),
        isA<Err<HostReviewToken, CoordinatorFailure>>().having(
          (e) => e.failure,
          'failure',
          isA<CoordinatorTransportFailed>(),
        ),
      );
    });
  });
}
