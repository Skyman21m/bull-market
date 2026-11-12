import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/ui/book_view.dart';
import 'package:p2p/src/ui/tor_wait_view.dart';
import 'package:p2p/src/ui/widgets/tor_wait_phrases.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The twelve phrases the owner approved on 2026-11-12 (#68), in the order of his list.
const englishPhrases = [
  'Sats travelling at the speed of light',
  'Peeling the onion, layer by layer',
  'Bouncing from relay to relay',
  'Hiding your IP address from coordinators',
  'Waking up the robots',
  'No KYC, just robots',
  'Not your keys, not your coins',
  "Don't trust, verify",
  'Privacy is not a crime',
  'Be your own bank',
  'Tick tock, next block',
  'Loading with low time preference',
];

/// The same phrases in French, with the typographic apostrophe, as some of the Garage's French texts write it; most other French texts of the feature, taken from the phase-1 catalogue, use the straight one.
const frenchPhrases = [
  'Des sats à la vitesse de la lumière',
  'On épluche l’oignon, couche par couche',
  'Rebond de relais en relais',
  'Votre adresse IP reste cachée aux coordinateurs',
  'Réveil des robots',
  'Pas de KYC, juste des robots',
  'Pas vos clés, pas vos bitcoins',
  'Ne faites pas confiance, vérifiez',
  'La vie privée n’est pas un crime',
  'Soyez votre propre banque',
  'Tic tac, prochain bloc',
  'Chargement à faible préférence temporelle',
];

/// The phrases from last to first.
final reversed = P2pShuffle(
  (count) => [for (var i = count - 1; i >= 0; i--) i],
);

/// The wait at [tor] with [percent], on a screen of [size] points with [textScale], in [locale]; [still] asks for reduced motion, as the harness of the feature does.
Widget wait(
  TorWait tor, {
  int? percent,
  P2pShuffle shuffle = P2pShuffle.unshuffled,
  Locale locale = const Locale('en'),
  bool still = true,
  Size size = const Size(390, 844),
  double textScale = 1,
  VoidCallback? onRetry,
}) => MaterialApp(
  theme: testTheme,
  locale: locale,
  localizationsDelegates: P2pLocalizations.localizationsDelegates,
  supportedLocales: P2pLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: still,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: TorWaitView(
        tor: tor,
        percent: percent,
        shuffle: shuffle,
        onRetry: onRetry ?? () {},
      ),
    ),
  ),
);

/// Gives the test a screen of [size] points.
void useScreen(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

final phrases = find.byType(TorWaitPhrases);

/// The texts laid out only for the room they take, and not painted.
final footprint = find.descendant(
  of: find.descendant(of: phrases, matching: find.byType(Visibility)),
  matching: find.byType(Text),
);

/// The texts of the phrases that are painted.
List<String> shownPhrases(WidgetTester tester) {
  final hidden = footprint.evaluate().toSet();
  return [
    for (final element
        in find.descendant(of: phrases, matching: find.byType(Text)).evaluate())
      if (!hidden.contains(element)) (element.widget as Text).data ?? '',
  ];
}

/// The phrase painted.
Finder shownPhrase(WidgetTester tester) => find
    .descendant(of: phrases, matching: find.text(shownPhrases(tester).single))
    .last;

/// How far the gear has turned, in turns.
double gearTurns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(of: phrases, matching: find.byType(RotationTransition)),
    )
    .turns
    .value;

/// The opacity of the phrase painted.
double phraseOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.ancestor(
        of: shownPhrase(tester),
        matching: find.descendant(
          of: phrases,
          matching: find.byType(FadeTransition),
        ),
      ),
    )
    .opacity
    .value;

/// The run of the bar for the whole wait, dimmed once a percentage is shown.
BullFadingLinearProgress bar(WidgetTester tester) =>
    tester.widget<BullFadingLinearProgress>(
      find.byType(BullFadingLinearProgress).first,
    );

/// The texts with a percent sign that are painted: the one that keeps the room of the percentage for the whole wait is not.
List<String> shownPercents(WidgetTester tester) {
  final hidden = find
      .descendant(of: find.byType(Visibility), matching: find.byType(Text))
      .evaluate()
      .toSet();
  return [
    for (final element in find.textContaining('%').evaluate())
      if (!hidden.contains(element)) (element.widget as Text).data ?? '',
  ];
}

/// The bar under the steps.
final barArea = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_TorBar',
);

/// The fill of the bar, drawn only with a percentage.
final fill = find.byType(AnimatedFractionallySizedBox);

/// The share of the bar the fill covers.
double filled(WidgetTester tester) =>
    tester
        .getSize(
          find.descendant(of: fill, matching: find.byType(ColoredBox)).first,
        )
        .width /
    tester.getSize(fill).width;

/// The run drawn over the fill, in a lighter tint.
final lightRun = find.descendant(
  of: fill,
  matching: find.byType(BullFadingLinearProgress),
);

/// Lets a bar that stopped fade out: once it has, nothing on the screen moves any more.
Future<void> fadeOut(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1100));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('percentage', () {
    testWidgets('none before Tor reports one: the bar runs as before', (
      tester,
    ) async {
      await tester.pumpWidget(wait(TorWait.connecting));
      await tester.pump(const Duration(milliseconds: 100));

      expect(shownPercents(tester), isEmpty);
      expect(fill, findsNothing);
      expect(bar(tester).trigger, isTrue);
      expect(bar(tester).foregroundColor, testBullTheme.primary);
      expect(bar(tester).backgroundColor, testBullTheme.surfaceContainer);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets(
      'the bar filled to the percentage, which stands next to it, and still running',
      (tester) async {
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: 42, still: false),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('42%'), findsOneWidget);
        expect(filled(tester), closeTo(0.42, 0.001));
        expect(
          tester.getTopLeft(find.text('42%')).dx,
          greaterThan(tester.getTopRight(fill).dx),
        );
        // The run goes on over the whole bar: dimmed where the start is not done yet, with no track of its own.
        expect(find.byType(BullFadingLinearProgress), findsNWidgets(2));
        expect(bar(tester).trigger, isTrue);
        expect(bar(tester).backgroundColor, testBullTheme.transparent);
        expect(
          bar(tester).foregroundColor,
          testBullTheme.primary.withValues(alpha: 0.4),
        );
        // And in a lighter tint over the fill, laid out over the whole bar and cut to the part done.
        final light = tester.widget<BullFadingLinearProgress>(lightRun);
        expect(light.trigger, isTrue);
        expect(light.backgroundColor, testBullTheme.transparent);
        expect(
          light.foregroundColor,
          isNot(anyOf(testBullTheme.primary, testBullTheme.surfaceContainer)),
        );
        expect(tester.getSize(lightRun).width, tester.getSize(fill).width);
        expect(
          find.ancestor(of: lightRun, matching: find.byType(ClipRect)),
          findsWidgets,
        );
        expect(tester.hasRunningAnimations, isTrue);
      },
    );

    for (final percent in [0, 99]) {
      testWidgets('$percent %: the bar still runs', (tester) async {
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: percent, still: false),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(shownPercents(tester), ['$percent%']);
        expect(filled(tester), closeTo(percent / 100, 0.001));
        expect(bar(tester).trigger, isTrue);
        expect(tester.hasRunningAnimations, isTrue);
      });
    }

    for (final tor in [TorWait.initializing, TorWait.ready, TorWait.failed]) {
      testWidgets('${tor.name}: no percentage, whatever is given', (
        tester,
      ) async {
        await tester.pumpWidget(wait(tor, percent: 42));

        expect(shownPercents(tester), isEmpty);
        expect(fill, findsNothing);
      });
    }

    testWidgets('the fill follows the percentage, and goes with it', (
      tester,
    ) async {
      await tester.pumpWidget(wait(TorWait.connecting, percent: 10));
      await tester.pumpWidget(wait(TorWait.connecting, percent: 60));
      await tester.pump();

      expect(find.text('60%'), findsOneWidget);
      expect(filled(tester), closeTo(0.6, 0.001));

      // A new attempt of Tor: no share yet.
      await tester.pumpWidget(wait(TorWait.connecting));
      expect(shownPercents(tester), isEmpty);
      expect(fill, findsNothing);
      expect(bar(tester).foregroundColor, testBullTheme.primary);
    });

    testWidgets(
      'the fill slides to a new percentage, unless motion is reduced',
      (tester) async {
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: 40, still: false),
        );
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: 80, still: false),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(filled(tester), allOf(greaterThan(0.4), lessThan(0.8)));
        await tester.pump(const Duration(milliseconds: 250));
        expect(filled(tester), closeTo(0.8, 0.001));

        await tester.pumpWidget(wait(TorWait.connecting, percent: 90));
        await tester.pump();
        expect(filled(tester), closeTo(0.9, 0.001));
      },
    );

    testWidgets('a screen reader reads the steps and the percentage', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wait(TorWait.connecting, percent: 42));

      expect(find.bySemanticsLabel('Initializing Tor daemon'), findsOneWidget);
      expect(find.bySemanticsLabel('42%'), findsOneWidget);
      // The text that only keeps the room of the percentage is not read.
      expect(find.bySemanticsLabel('99%'), findsNothing);
      semantics.dispose();
    });

    testWidgets(
      'nothing moves when a percentage comes or gains a digit: the title, the bar and its length',
      (tester) async {
        Future<(Rect, Rect)> layout(TorWait tor, int? percent) async {
          await tester.pumpWidget(wait(tor, percent: percent));
          return (
            tester.getRect(find.text('Connecting to Tor network').first),
            tester.getRect(barArea),
          );
        }

        final before = await layout(TorWait.initializing, null);
        for (final (tor, percent) in [
          (TorWait.connecting, null),
          (TorWait.connecting, 0),
          (TorWait.connecting, 5),
          (TorWait.connecting, 42),
          (TorWait.connecting, 99),
        ]) {
          expect(await layout(tor, percent), before, reason: '$tor $percent');
        }
      },
    );

    testWidgets(
      'nothing moves on a 320-point screen at text scale 3, in French either',
      (tester) async {
        const size = Size(320, 568);
        useScreen(tester, size);
        Future<(Rect, Rect)> layout(int? percent) async {
          await tester.pumpWidget(
            wait(
              TorWait.connecting,
              percent: percent,
              locale: const Locale('fr'),
              size: size,
              textScale: 3,
            ),
          );
          return (
            tester.getRect(find.text('Connexion au réseau Tor').first),
            tester.getRect(barArea),
          );
        }

        final before = await layout(null);
        for (final percent in [0, 7, 99]) {
          expect(await layout(percent), before, reason: '$percent');
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'reduced motion: the run goes on before a percentage, and stops once one is shown',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting));
        await tester.pump(const Duration(milliseconds: 100));
        expect(bar(tester).trigger, isTrue);
        expect(tester.hasRunningAnimations, isTrue);

        await tester.pumpWidget(wait(TorWait.connecting, percent: 42));
        expect(bar(tester).trigger, isFalse);
        expect(
          tester.widget<BullFadingLinearProgress>(lightRun).trigger,
          isFalse,
        );
        await fadeOut(tester);
        expect(tester.hasRunningAnimations, isFalse);
        // The fill and the number carry the progress.
        expect(filled(tester), closeTo(0.42, 0.001));
        expect(shownPercents(tester), ['42%']);

        await tester.pumpWidget(wait(TorWait.connecting, percent: 60));
        await tester.pump();
        expect(filled(tester), closeTo(0.6, 0.001));
        expect(tester.hasRunningAnimations, isFalse);

        // A new attempt of Tor, with no share yet: the run comes back.
        await tester.pumpWidget(wait(TorWait.connecting));
        await tester.pump(const Duration(milliseconds: 100));
        expect(bar(tester).trigger, isTrue);
        expect(tester.hasRunningAnimations, isTrue);
      },
    );

    testWidgets(
      'Tor fails after a percentage: the run fades out, as it does without one',
      (tester) async {
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: 42, still: false),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final run = tester.element(find.byType(BullFadingLinearProgress).first);

        await tester.pumpWidget(
          wait(TorWait.failed, percent: 42, still: false),
        );
        expect(find.byType(BullFadingLinearProgress), findsOneWidget);
        // The same run, so its fade goes on from where it was.
        expect(tester.element(find.byType(BullFadingLinearProgress)), run);
        expect(bar(tester).trigger, isFalse);
        await tester.pump(const Duration(milliseconds: 500));
        final fading = tester
            .widget<FadeTransition>(
              find
                  .descendant(
                    of: find.byType(BullFadingLinearProgress),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;
        expect(fading, allOf(greaterThan(0), lessThan(1)));
        await fadeOut(tester);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('in French, the percent sign as French writes it', (
      tester,
    ) async {
      await tester.pumpWidget(
        wait(TorWait.connecting, percent: 42, locale: const Locale('fr')),
      );

      expect(find.text('42\u00a0%'), findsOneWidget);
    });
  });

  group('phrases', () {
    test('the list is the twelve phrases approved, in English and French', () {
      expect(TorWaitPhrases.count, englishPhrases.length);
      expect(
        TorWaitPhrases.phrasesOf(lookupP2pLocalizations(const Locale('en'))),
        englishPhrases,
      );
      expect(
        TorWaitPhrases.phrasesOf(lookupP2pLocalizations(const Locale('fr'))),
        frenchPhrases,
      );
    });

    testWidgets(
      'each of the twelve, in the order of the shuffle, one every 2 seconds',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting, shuffle: reversed));

        for (final phrase in englishPhrases.reversed) {
          expect(shownPhrases(tester), [phrase]);
          await tester.pump(const Duration(milliseconds: 1999));
          expect(shownPhrases(tester), [phrase]);
          await tester.pump(const Duration(milliseconds: 1));
        }
        // Then the order begins again.
        expect(shownPhrases(tester), [englishPhrases.last]);
      },
    );

    testWidgets('in French', (tester) async {
      await tester.pumpWidget(
        wait(TorWait.initializing, locale: const Locale('fr')),
      );

      for (final phrase in frenchPhrases) {
        expect(shownPhrases(tester), [phrase]);
        await tester.pump(TorWaitPhrases.period);
      }
    });

    testWidgets('one is painted; the others only take their room', (
      tester,
    ) async {
      await tester.pumpWidget(wait(TorWait.connecting));

      final hidden = tester.widgetList<Visibility>(
        find.descendant(of: phrases, matching: find.byType(Visibility)),
      );
      expect(hidden, hasLength(12));
      expect(hidden.every((visibility) => !visibility.visible), isTrue);
      expect(
        tester.widgetList<Text>(footprint).map((text) => text.data),
        englishPhrases,
      );
      expect(shownPhrases(tester), [englishPhrases.first]);
    });

    testWidgets('nothing on the screen moves when the phrase changes', (
      tester,
    ) async {
      useScreen(tester, const Size(320, 568));
      await tester.pumpWidget(
        wait(
          TorWait.connecting,
          percent: 42,
          locale: const Locale('fr'),
          size: const Size(320, 568),
        ),
      );
      final line = find.text(
        'La connexion aux coordinateurs passe uniquement par Tor.',
      );
      final area = tester.getRect(phrases);
      final below = tester.getTopLeft(line);

      for (var i = 0; i < TorWaitPhrases.count; i++) {
        expect(tester.getRect(phrases), area);
        expect(tester.getTopLeft(line), below);
        await tester.pump(TorWaitPhrases.period);
      }
    });

    for (final tor in [TorWait.ready, TorWait.failed]) {
      testWidgets('none once Tor is ${tor.name}, and nothing left running', (
        tester,
      ) async {
        await tester.pumpWidget(
          wait(TorWait.connecting, percent: 30, still: false),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(shownPhrases(tester), hasLength(1));
        expect(gearTurns(tester), greaterThan(0));

        await tester.pumpWidget(wait(tor, percent: 30, still: false));
        expect(phrases, findsNothing);
        for (final phrase in englishPhrases) {
          expect(find.text(phrase), findsNothing);
        }
        await fadeOut(tester);
        expect(tester.hasRunningAnimations, isFalse);
        expect(tester.binding.transientCallbackCount, 0);

        // A timer still running would rebuild a disposed widget here, and leave the test with a pending timer.
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('a new order at each wait, kept for the whole wait', (
      tester,
    ) async {
      var draws = 0;
      final shuffle = P2pShuffle((count) {
        draws++;
        return [for (var i = 0; i < count; i++) (i + draws) % count];
      });

      await tester.pumpWidget(wait(TorWait.initializing, shuffle: shuffle));
      expect(draws, 1);
      expect(shownPhrases(tester), [englishPhrases[1]]);
      await tester.pump(TorWaitPhrases.period);
      expect(shownPhrases(tester), [englishPhrases[2]]);

      // Tor connects, then reports a share: the same wait goes on.
      await tester.pumpWidget(wait(TorWait.connecting, shuffle: shuffle));
      await tester.pumpWidget(
        wait(TorWait.connecting, percent: 12, shuffle: shuffle),
      );
      expect(draws, 1);
      expect(shownPhrases(tester), [englishPhrases[2]]);
      await tester.pump(TorWaitPhrases.period);
      expect(shownPhrases(tester), [englishPhrases[3]]);

      // Tor fails, and the user retries: a new wait.
      await tester.pumpWidget(wait(TorWait.failed, shuffle: shuffle));
      expect(shownPhrases(tester), isEmpty);
      await tester.pumpWidget(wait(TorWait.initializing, shuffle: shuffle));
      expect(draws, 2);
      expect(shownPhrases(tester), [englishPhrases[2]]);
    });

    testWidgets(
      'the gear turns once and the phrase fades in and out, for each phrase',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting, still: false));
        // The first frame starts the controller.
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 150));
        expect(gearTurns(tester), closeTo(0.075, 0.01));
        expect(phraseOpacity(tester), closeTo(0.5, 0.05));

        await tester.pump(const Duration(milliseconds: 850));
        expect(gearTurns(tester), closeTo(0.5, 0.01));
        expect(phraseOpacity(tester), 1);

        await tester.pump(const Duration(milliseconds: 850));
        expect(phraseOpacity(tester), closeTo(0.5, 0.05));
        expect(shownPhrases(tester), [englishPhrases[0]]);

        await tester.pump(const Duration(milliseconds: 150));
        expect(shownPhrases(tester), [englishPhrases[1]]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(phraseOpacity(tester), closeTo(0.5, 0.05));
        expect(gearTurns(tester), closeTo(0.075, 0.01));
      },
    );

    testWidgets(
      'reduced motion: the gear stands still and nothing fades, the phrase still changes',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting));

        for (final phrase in englishPhrases.take(3)) {
          expect(shownPhrases(tester), [phrase]);
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 400));
            expect(gearTurns(tester), 0);
            expect(phraseOpacity(tester), 1);
          }
          await tester.pump(const Duration(milliseconds: 400));
        }
      },
    );

    testWidgets(
      'reduced motion asked during the wait stops the gear; allowed again, it starts with the next phrase',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting, still: false));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(gearTurns(tester), greaterThan(0));

        await tester.pumpWidget(wait(TorWait.connecting));
        expect(gearTurns(tester), 0);
        expect(phraseOpacity(tester), 1);
        await tester.pump(const Duration(milliseconds: 1500));
        expect(shownPhrases(tester), [englishPhrases[1]]);
        expect(gearTurns(tester), 0);

        // Allowed again in the middle of a phrase: it stays still until the next one, so that the fade keeps step with the change.
        await tester.pumpWidget(wait(TorWait.connecting, still: false));
        await tester.pump(const Duration(milliseconds: 1000));
        expect(gearTurns(tester), 0);
        expect(phraseOpacity(tester), 1);
        await tester.pump(const Duration(milliseconds: 1000));
        expect(shownPhrases(tester), [englishPhrases[2]]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(gearTurns(tester), greaterThan(0));
        expect(phraseOpacity(tester), lessThan(1));
      },
    );

    for (final (locale, texts) in [
      (const Locale('en'), englishPhrases),
      (const Locale('fr'), frenchPhrases),
    ]) {
      for (final textScale in [1.0, 2.0, 3.0]) {
        testWidgets(
          'a 320-point screen at text scale $textScale in ${locale.languageCode}: every phrase wraps whole, nothing overflows',
          (tester) async {
            const size = Size(320, 568);
            useScreen(tester, size);
            await tester.pumpWidget(
              wait(
                TorWait.connecting,
                percent: 42,
                locale: locale,
                size: size,
                textScale: textScale,
              ),
            );

            final shown = <String>[];
            for (var i = 0; i < TorWaitPhrases.count; i++) {
              expect(tester.takeException(), isNull);
              final phrase = shownPhrase(tester);
              shown.add(shownPhrases(tester).single);
              final rect = tester.getRect(phrase);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(size.width));
              // The area of the phrases holds the whole phrase.
              final area = tester.getRect(phrases);
              expect(area.top, lessThanOrEqualTo(rect.top));
              expect(area.bottom, greaterThanOrEqualTo(rect.bottom));
              expect(
                tester.renderObject<RenderParagraph>(phrase).didExceedMaxLines,
                isFalse,
              );
              await tester.pump(TorWaitPhrases.period);
            }
            expect(shown, texts);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'a screen reader reads the steps and the percentage, never the phrases',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(wait(TorWait.connecting, percent: 42));

        for (var i = 0; i < 3; i++) {
          expect(
            find.bySemanticsLabel('Initializing Tor daemon'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('Connected to Tor network'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('Connecting to Tor network'),
            findsWidgets,
          );
          expect(find.bySemanticsLabel('42%'), findsOneWidget);
          for (final phrase in englishPhrases) {
            expect(find.bySemanticsLabel(phrase), findsNothing);
          }
          await tester.pump(TorWaitPhrases.period);
        }
        semantics.dispose();
      },
    );
  });

  group('in the tab', () {
    late GetIt locator;
    late StreamController<P2pTorReport> reports;
    var draws = 0;

    setUp(() {
      locator = GetIt.asNewInstance();
      reports = StreamController<P2pTorReport>.broadcast();
      draws = 0;
      setUpP2pForTesting(
        locator,
        transport: FakeTransport(),
        torReports: () => reports.stream,
        clock: () => testNow,
        // One step further at each wait: the first wait begins with the second phrase.
        shuffle: P2pShuffle((count) {
          draws++;
          return [for (var i = 0; i < count; i++) (i + draws) % count];
        }),
      );
    });

    tearDown(() async {
      await reports.close();
      await locator.reset();
    });

    Future<void> open(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      usePhoneScreen(tester);
      final router = GoRouter(
        initialLocation: P2pFeature.path,
        routes: [
          const P2pFeature().route(
            locator,
            network: (_) => RobosatsNetwork.mainnet,
          ),
        ],
      );
      await tester.pumpWidget(routerHarness(router, locale: locale));
      await settle(tester);
    }

    testWidgets(
      'the share Tor reports while it connects, then the book without the wait',
      (tester) async {
        await open(tester);
        reports.add(P2pTorReport(P2pTorState.connecting));
        await settle(tester);
        expect(shownPercents(tester), isEmpty);
        expect(shownPhrases(tester), [englishPhrases[1]]);

        reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.42));
        await settle(tester);
        expect(find.text('42%'), findsOneWidget);

        reports.add(P2pTorReport(P2pTorState.connecting, progress: 1));
        await settle(tester);
        expect(shownPercents(tester), ['99%']);
        expect(find.text('100%'), findsNothing);

        reports.add(P2pTorReport(P2pTorState.ready));
        await settle(tester);
        expect(find.byType(BookView), findsOneWidget);
        expect(find.byType(TorWaitView), findsNothing);
        expect(phrases, findsNothing);
        expect(find.text('99%'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('in French', (tester) async {
      await open(tester, locale: const Locale('fr'));
      reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.07));
      await settle(tester);

      expect(find.text('7\u00a0%'), findsOneWidget);
      expect(shownPhrases(tester), [frenchPhrases[1]]);
    });

    testWidgets(
      'a failure hides the percentage and the phrases; Retry starts a new wait',
      (tester) async {
        await open(tester);
        reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.3));
        await settle(tester);
        expect(find.text('30%'), findsOneWidget);
        expect(draws, 1);

        reports.add(P2pTorReport(P2pTorState.failed));
        await settle(tester);
        expect(find.text('Connection error'), findsOneWidget);
        expect(shownPercents(tester), isEmpty);
        expect(phrases, findsNothing);

        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(draws, 2);
        expect(shownPhrases(tester), [englishPhrases[2]]);
        expect(shownPercents(tester), isEmpty);
      },
    );
  });
}
