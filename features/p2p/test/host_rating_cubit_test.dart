import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/trade_host_rating.dart';
import 'package:p2p/src/presentation/host_rating_cubit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/trade_screens.dart';

/// The cubit of « Rate your host » (#95): the token asked once, the first time a status offers the rating, and a rating published only with a token in hand.
void main() {
  late TradeScreenStatuses statuses;
  final token = HostReviewToken.parse('cd' * 64);
  final rating = HostRating.of(4);

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
  });

  test('asked once, from a status that offers the rating only', () async {
    final asked = <Object>[];
    final published = <int>[];
    final cubit = HostRatingCubit(
      TradeScreenStatuses.record,
      (record, seen) async {
        asked.add(seen);
        return Ok(token ?? fail('token'));
      },
      (record, seen, token, rating) async => published.add(rating.stars),
    );
    addTearDown(cubit.close);
    await cubit.rate(await statuses.succeeded(), rating ?? fail('rating'));
    expect(published, isEmpty);
    await cubit.show(await statuses.chatting());
    expect(cubit.state, isA<HostRatingIdle>());
    final fourteen = await statuses.succeeded();
    await cubit.show(fourteen);
    await cubit.show(fourteen);
    expect(asked, [fourteen]);
    expect(cubit.state, isA<HostRatingReady>());
    await cubit.rate(fourteen, rating ?? fail('rating'));
    expect(published, [4]);
  });

  test(
    'a token not given leaves the rating unavailable, never asked again',
    () async {
      var asked = 0;
      final cubit = HostRatingCubit(
        TradeScreenStatuses.record,
        (record, seen) async {
          asked++;
          return const Err(HostTokenNotGiven());
        },
        (record, seen, token, rating) async => fail('published'),
      );
      addTearDown(cubit.close);
      final fourteen = await statuses.succeeded();
      await cubit.show(fourteen);
      await cubit.show(fourteen);
      expect(cubit.state, isA<HostRatingUnavailable>());
      expect(asked, 1);
      await cubit.rate(fourteen, rating ?? fail('rating'));
    },
  );

  test(
    'an Error of the use case leaves the rating unavailable and is passed on',
    () async {
      final cubit = HostRatingCubit(
        TradeScreenStatuses.record,
        (record, seen) async => throw StateError('bug'),
        (record, seen, token, rating) async => fail('published'),
      );
      addTearDown(cubit.close);
      await expectLater(
        cubit.show(await statuses.succeeded()),
        throwsStateError,
      );
      expect(cubit.state, isA<HostRatingUnavailable>());
    },
  );

  test('closed while the token is asked: nothing emitted after', () async {
    final answer = Completer<Result<HostReviewToken, HostTokenNotGiven>>();
    final cubit = HostRatingCubit(
      TradeScreenStatuses.record,
      (record, seen) => answer.future,
      (record, seen, token, rating) async => fail('published'),
    );
    final shown = cubit.show(await statuses.succeeded());
    expect(cubit.state, isA<HostRatingAsking>());
    await cubit.close();
    answer.complete(Ok(token ?? fail('token')));
    await shown;
    expect(cubit.state, isA<HostRatingAsking>());
  });
}
