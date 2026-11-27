import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/src/presentation/make_order_l10n.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_l10n.dart';
import 'package:p2p/src/testing/scripted_coordinator.dart';
import 'package:p2p/src/testing/scripted_signatures.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/harness.dart';
import 'support/trade_harness.dart' show TradeHarness, unlockedPairOf;

/// The signature of every request of a robot that changes a state (GHSA-22q8-9ghc-jg3h, RoboSats pull request 2955, head `0943c97`): what the scripted coordinators refuse, as a coordinator running the fix, and what the app says of the three new refusals.
void main() {
  const name = 'Temple of Sats';

  group('the texts of the refusals of a signature', () {
    Future<List<String>> textsOf(
      WidgetTester tester,
      ActionSignatureRefused refused, {
      required Locale locale,
    }) async {
      late List<String> texts;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) {
              texts = [
                MakeWasNotMade(refused).toText(context, coordinator: name),
                TakeWasNotMade(refused).toText(context, coordinator: name),
                CancelWasNotDone(refused).toText(context, coordinator: name),
                PauseWasNotDone(refused).toText(context, coordinator: name),
                for (final action in ChatStepAction.values)
                  ChatStepWasNotDone(
                    refused,
                  ).toText(context, coordinator: name, action: action),
              ];
              return const SizedBox.shrink();
            },
          ),
          locale: locale,
        ),
      );
      return texts;
    }

    for (final (locale, clock, newer) in [
      (
        const Locale('en'),
        "The time of this device is too far from Temple of Sats's. Turn on automatic time and try again.",
        'Temple of Sats asks for a newer version of Bull Market.',
      ),
      (
        const Locale('fr'),
        "L'heure de ce téléphone est trop éloignée de celle de Temple of Sats. Activez l'heure automatique et réessayez.",
        'Temple of Sats demande une version plus récente de Bull Market.',
      ),
    ]) {
      testWidgets(
        '${locale.languageCode}: 1060 says the clock, 1059 and 1061 a newer version, wherever the refusals of an action go',
        (tester) async {
          for (final (reason, said) in [
            (ActionSignatureRefusal.clockSkew, clock),
            (ActionSignatureRefusal.missing, newer),
            (ActionSignatureRefusal.otherCoordinator, newer),
          ]) {
            final texts = await textsOf(
              tester,
              ActionSignatureRefused(reason),
              locale: locale,
            );
            for (final text in texts) {
              expect(text, contains(said), reason: '$reason');
            }
          }
          // 1048 and a signature this app could not make keep the generic words of each place.
          for (final reason in [
            ActionSignatureRefusal.invalid,
            ActionSignatureRefusal.notSigned,
          ]) {
            final texts = await textsOf(
              tester,
              ActionSignatureRefused(reason),
              locale: locale,
            );
            for (final text in texts) {
              expect(text, isNot(contains(clock)), reason: '$reason');
              expect(text, isNot(contains(newer)), reason: '$reason');
            }
          }
        },
      );
    }
  });

  group('a coordinator running the fix', () {
    const network = RobosatsNetwork.testnet;
    final robots = TradeHarness.robotsOf(network);
    final taker = robots[0];
    final other = robots[1];
    final now = DateTime.utc(2026, 11, 14, 9);
    late ScriptedCoordinator coordinator;

    setUp(() {
      coordinator = ScriptedCoordinator(
        network: network,
        robots: robots,
        clock: () => now,
      );
    });

    /// Puts [robot] on the coordinator with its pair, as a first contact does.
    Future<void> put(RobotIdentity robot) async {
      final client = CoordinatorClient(coordinator, clock: () => now);
      final contact = await client.fetchRobot(
        coordinator.coordinator,
        network,
        identity: robot,
        pgpKey: unlockedPairOf(robot).key,
      );
      expect(contact, isA<Ok<CoordinatorRobotAnswer, CoordinatorFailure>>());
    }

    /// What the coordinator answers [robot]'s take with [fields], sent as is.
    Future<(int, Object?)> take(
      RobotIdentity robot,
      Map<String, Object?> fields,
    ) async {
      final answer = await coordinator.send(
        CoordinatorRequest(
          method: CoordinatorHttpMethod.post,
          url: Uri.parse(coordinator.coordinator.origins(network).onion ?? '')
              .replace(
                path: '/api/order/',
                queryParameters: {'order_id': '${coordinator.orderId}'},
              ),
          headers: {'Authorization': robot.authorizationHeader()},
          maxResponseBytes: CoordinatorReadBounds.orderBytes,
          body: utf8.encode(jsonEncode({'action': 'take', ...fields})),
          robot: robot.sessionKey,
        ),
      );
      return switch (answer) {
        Ok(:final value) => (
          value.statusCode,
          value.body.isEmpty ? null : jsonDecode(utf8.decode(value.body)),
        ),
        Err(:final failure) => fail('$failure'),
      };
    }

    String signed(RobotIdentity robot, String text) =>
        switch (unlockedPairOf(robot).signCleartext(text, now: now)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };

    test('refuses an unsigned take with 1059, nothing taken', () async {
      await put(taker);
      final (status, body) = await take(taker, {'amount': 0});
      expect(status, 400);
      expect((body as Map<String, Object?>)['error_code'], 1059);
      expect(coordinator.holdsPreTake(taker), isFalse);
    });

    test(
      'refuses with 1048 a take signed for another action, order, coordinator, or by another robot\'s key',
      () async {
        await put(taker);
        await put(other);
        final id = coordinator.orderId;
        for (final signature in [
          signed(taker, 'cancel:$id:temple'),
          signed(taker, 'take:${id + 1}:temple'),
          signed(taker, 'take:$id:lake'),
          signed(taker, 'temple:$id:take'),
          signed(other, 'take:$id:temple'),
          'not a signature',
        ]) {
          final (status, body) = await take(taker, {
            'amount': 0,
            'signature': signature,
          });
          expect(status, 400);
          expect((body as Map<String, Object?>)['error_code'], 1048);
        }
        expect(coordinator.holdsPreTake(taker), isFalse);
        // Signed as the fix wants, it is taken.
        final (status, _) = await take(taker, {
          'amount': 0,
          'signature': signed(taker, 'take:$id:temple'),
        });
        expect(status, 200);
        expect(coordinator.holdsPreTake(taker), isTrue);
      },
    );

    test('a coordinator not updated yet ignores the signature', () async {
      coordinator.checksSignatures = false;
      await put(taker);
      final (status, _) = await take(taker, {'amount': 0});
      expect(status, 200);
      expect(coordinator.holdsPreTake(taker), isTrue);
      // And a body with the field in too: the reference's serializers read only the fields they declare.
      final client = CoordinatorClient(coordinator, clock: () => now);
      final read = await client.fetchOrder(
        coordinator.coordinator,
        network,
        identity: taker,
        orderId: coordinator.orderId,
      );
      expect(read, isA<Ok<CoordinatorOrder, CoordinatorFailure>>());
    });

    test(
      'a timed text: 1061 for another alias, 1060 more than 300 s away, 1048 without the alias or in milliseconds',
      () async {
        final key = unlockedPairOf(taker);
        int? code(String text) => scriptedSignatureRefusal(
          {'signature': signed(taker, text)},
          publicKey: key.key.publicKey.armored,
          expected: const ScriptedTimedText('make', 'temple'),
          now: now,
        );
        final seconds = unixSeconds(now);
        expect(code('make:temple:$seconds'), isNull);
        expect(code('make:temple:${seconds + 300}'), isNull);
        expect(code('make:temple:${seconds - 300}'), isNull);
        expect(code('make:lake:$seconds'), 1061);
        expect(code('make:temple:${seconds + 301}'), 1060);
        expect(code('make:temple:${seconds - 301}'), 1060);
        expect(code('make:temple:${now.millisecondsSinceEpoch}'), 1060);
        expect(code('make:$seconds'), 1048);
        expect(code('stealth:temple:$seconds'), 1048);
        expect(
          scriptedSignatureRefusal(
            const {},
            publicKey: key.key.publicKey.armored,
            expected: const ScriptedTimedText('make', 'temple'),
            now: now,
          ),
          1059,
        );
      },
    );
  });
}
