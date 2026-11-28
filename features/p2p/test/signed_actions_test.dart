import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/usecases/trade/cancel_trade_usecase.dart';
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

/// The signature of every request of a robot that changes a state (GHSA-22q8-9ghc-jg3h, RoboSats pull request 2955, head `0943c97`): what the scripted coordinators refuse, as a coordinator running the fix, what the app says of the three new refusals, and a take and a cancel refused for their signature, played from the use case to the words of the screen (review of #305).
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

    for (final (locale, clock, newer, notSigned) in [
      (
        const Locale('en'),
        "The time of this device is too far from Temple of Sats's. Turn on automatic time and try again.",
        'Temple of Sats asks for a newer version of Bull Market.',
        'The key of your robot could not sign this. Nothing was sent.',
      ),
      (
        const Locale('fr'),
        "L'heure de ce téléphone est trop éloignée de celle de Temple of Sats. Activez l'heure automatique et réessayez.",
        'Temple of Sats demande une version plus récente de Bull Market.',
        'La clé de votre robot n’a pas pu signer ceci. Rien n’a été envoyé.',
      ),
    ]) {
      testWidgets(
        '${locale.languageCode}: 1060 says the clock, 1059 and 1061 a newer version, a signature not made here that nothing was sent, wherever the refusals of an action go',
        (tester) async {
          for (final (reason, said) in [
            (ActionSignatureRefusal.clockSkew, clock),
            (ActionSignatureRefusal.missing, newer),
            (ActionSignatureRefusal.otherCoordinator, newer),
            // Not made here, nothing sent: the payout's words for the same case, never « refused this robot ».
            (ActionSignatureRefusal.notSigned, notSigned),
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
          // 1048 keeps the generic words of each place.
          for (final reason in [ActionSignatureRefusal.invalid]) {
            final texts = await textsOf(
              tester,
              ActionSignatureRefused(reason),
              locale: locale,
            );
            for (final text in texts) {
              expect(text, isNot(contains(clock)), reason: '$reason');
              expect(text, isNot(contains(newer)), reason: '$reason');
              expect(text, isNot(contains(notSigned)), reason: '$reason');
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

    /// What the coordinator answers [robot]'s [action] with [fields], sent as is.
    Future<(int, Object?)> post(
      RobotIdentity robot,
      String action,
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
          body: utf8.encode(jsonEncode({'action': action, ...fields})),
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

    /// What the coordinator answers [robot]'s take with [fields], sent as is.
    Future<(int, Object?)> take(
      RobotIdentity robot,
      Map<String, Object?> fields,
    ) => post(robot, 'take', fields);

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

    test(
      'an action other than take and cancel by a robot that is no participant: 1047 first, as the reference',
      () async {
        await put(other);
        for (final action in ['confirm', 'undo_confirm', 'dispute']) {
          final (status, body) = await post(other, action, const {});
          expect(status, 403, reason: action);
          expect((body as Map<String, Object?>)['error_code'], 1047);
        }
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
      'a timed text: 1061 for another alias, 1060 more than 300 s away or in milliseconds, 1048 without the alias or for another action',
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

  group('a take and a cancel refused for their signature (review of #305)', () {
    /// The words of the screen for [notice]'s refusal, in English.
    Future<String> wordsOf(
      WidgetTester tester,
      String Function(BuildContext context) notice,
    ) async {
      late String words;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) {
              words = notice(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return words;
    }

    const clock =
        "The time of this device is too far from Temple of Sats's. Turn on automatic time and try again.";
    const newer = 'Temple of Sats asks for a newer version of Bull Market.';
    const notSigned =
        'The key of your robot could not sign this. Nothing was sent.';

    /// What the screen says for each code: its words, or for 1048 none of the three.
    void sayFor(int code, String words) {
      final saying = switch (code) {
        1060 => clock,
        1059 || 1061 => newer,
        _ => null,
      };
      for (final said in [clock, newer, notSigned]) {
        expect(
          words,
          said == saying ? contains(said) : isNot(contains(said)),
          reason: '$code',
        );
      }
    }

    ActionSignatureRefusal reasonOf(int code) => switch (code) {
      1059 => ActionSignatureRefusal.missing,
      1060 => ActionSignatureRefusal.clockSkew,
      1061 => ActionSignatureRefusal.otherCoordinator,
      _ => ActionSignatureRefusal.invalid,
    };

    for (final code in const [1059, 1060, 1061, 1048]) {
      testWidgets(
        'a take refused with $code: the take not made, the pending take closed, the screen\'s words of $code, nothing sent again',
        (tester) async {
          final (taken, takes, active) =
              await tester.runAsync(() async {
                final app = await TradeHarness.start();
                app.coordinator.refuseNextTake(code);
                final taken = await app.takeShown();
                // Time passes: no read nor resolution sends the take again.
                await app.elapse(const Duration(minutes: 5));
                return (
                  taken,
                  app.coordinator.received
                      .where((kind) => kind == ScriptedRequest.take)
                      .length,
                  await app.activeRecords(),
                );
              }) ??
              fail('not run');
          final notMade = switch (taken) {
            Ok(value: final TakeNotMade notMade) => notMade,
            final other => fail('$other'),
          };
          expect(
            notMade.refusal,
            isA<ActionSignatureRefused>().having(
              (refused) => refused.reason,
              'reason',
              reasonOf(code),
            ),
          );
          expect(notMade.record.closedAt, isNotNull);
          expect(notMade.closeProblem, isNull);
          expect(active, isEmpty);
          expect(takes, 1);
          sayFor(
            code,
            await wordsOf(
              tester,
              (context) => TakeWasNotMade(
                notMade.refusal,
              ).toText(context, coordinator: name),
            ),
          );
        },
      );

      testWidgets(
        'a cancel of a pre-take refused with $code: not done, the pre-take still held and the trade in progress, the screen\'s words of $code, nothing sent again',
        (tester) async {
          final (cancelled, cancels, held, active, record) =
              await tester.runAsync(() async {
                final app = await TradeHarness.start();
                final record = TradeHarness.recordOf(await app.takeShown());
                final run = app.watchOf(record);
                await app.settle();
                final seen = run.lastStatus.seen;
                expect(seen.status, isA<WaitingForTakerBond>());
                await run.subscription.cancel();
                final transport = _RefusingCancel(app.coordinator, code);
                final cancel = CancelTradeUsecase(
                  CoordinatorClient(transport, clock: () => app.now),
                  app.reader,
                  app.limiter,
                  app.locks,
                  app.keyring,
                );
                final cancelled = await cancel.execute(record, seen);
                // Time passes: nothing sends the cancel again.
                await app.elapse(const Duration(minutes: 1));
                return (
                  cancelled,
                  transport.cancels,
                  TradeHarness.robotsOf(
                    app.network,
                  ).any(app.coordinator.holdsPreTake),
                  await app.activeRecords(),
                  record,
                );
              }) ??
              fail('not run');
          final notDone = switch (cancelled) {
            Ok(value: final CancelNotDone notDone) => notDone,
            final other => fail('$other'),
          };
          expect(
            notDone.cause,
            isA<ActionSignatureRefused>().having(
              (refused) => refused.reason,
              'reason',
              reasonOf(code),
            ),
          );
          expect(cancels, 1);
          expect(held, isTrue);
          expect(active.map((trade) => trade.orderId), [record.orderId]);
          sayFor(
            code,
            await wordsOf(
              tester,
              (context) => CancelWasNotDone(
                notDone.cause,
              ).toText(context, coordinator: name),
            ),
          );
        },
      );
    }
  });
}

/// The scripted coordinator, whose cancels are refused for their signature with [code], as a coordinator running the fix refuses them: 1059 and 1048 by the coordinator itself, the signature taken out of the body or replaced by a text that is none; 1060 and 1061, which it gives only for a timed text (a make), answered as it answers them (`scriptedSignatureMessage`), the cancel not passed on.
final class _RefusingCancel implements CoordinatorTransport {
  final ScriptedCoordinator coordinator;
  final int code;

  /// How many cancels the app sent.
  int cancels = 0;

  _RefusingCancel(this.coordinator, this.code);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final body = request.body;
    final fields = request.method == CoordinatorHttpMethod.post && body != null
        ? jsonDecode(utf8.decode(body))
        : null;
    if (fields is! Map<String, Object?> || fields['action'] != 'cancel') {
      return coordinator.send(request);
    }
    cancels++;
    if (code == 1060 || code == 1061) {
      return Ok(
        CoordinatorResponse(
          statusCode: 400,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode(
            jsonEncode({
              'error_code': code,
              'bad_request': scriptedSignatureMessage(code),
            }),
          ),
        ),
      );
    }
    final changed = {...fields}..remove('signature');
    if (code == 1048) changed['signature'] = 'not a signature';
    return coordinator.send(
      CoordinatorRequest(
        method: request.method,
        url: request.url,
        headers: request.headers,
        maxResponseBytes: request.maxResponseBytes,
        body: Uint8List.fromList(utf8.encode(jsonEncode(changed))),
        robot: request.robot,
      ),
    );
  }
}
