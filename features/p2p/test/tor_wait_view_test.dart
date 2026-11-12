import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/ui/book_view.dart';
import 'package:p2p/src/ui/tor_wait_view.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The wait at [tor] with [percent], on a screen of [size] points with [textScale], in [locale]; [still] asks for reduced motion, as the harness of the feature does.
Widget wait(
  TorWait tor, {
  int? percent,
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
      body: TorWaitView(tor: tor, percent: percent, onRetry: onRetry ?? () {}),
    ),
  ),
);

BullFadingLinearProgress bar(WidgetTester tester) => tester
    .widget<BullFadingLinearProgress>(find.byType(BullFadingLinearProgress));

/// The fill of the bar, drawn only with a percentage.
final fill = find.byType(AnimatedFractionallySizedBox);

/// The share of the bar the fill covers.
double filled(WidgetTester tester) =>
    tester
        .getSize(find.descendant(of: fill, matching: find.byType(ColoredBox)))
        .width /
    tester.getSize(fill).width;

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

      expect(find.textContaining('%'), findsNothing);
      expect(fill, findsNothing);
      expect(bar(tester).trigger, isTrue);
      expect(bar(tester).foregroundColor, testBullTheme.primary);
      expect(bar(tester).backgroundColor, testBullTheme.surfaceContainer);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets(
      'the bar filled to the percentage, which stands next to it, and still running',
      (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting, percent: 42));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('42%'), findsOneWidget);
        expect(filled(tester), closeTo(0.42, 0.001));
        expect(
          tester.getTopLeft(find.text('42%')).dx,
          greaterThan(tester.getTopRight(fill).dx),
        );
        // The run goes on over the fill, in a lighter tint, on no track of its own.
        expect(bar(tester).trigger, isTrue);
        expect(bar(tester).backgroundColor, testBullTheme.transparent);
        expect(
          bar(tester).foregroundColor,
          isNot(anyOf(testBullTheme.primary, testBullTheme.surfaceContainer)),
        );
        expect(tester.hasRunningAnimations, isTrue);
      },
    );

    for (final percent in [0, 99]) {
      testWidgets('$percent %: the bar still runs', (tester) async {
        await tester.pumpWidget(wait(TorWait.connecting, percent: percent));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('$percent%'), findsOneWidget);
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

        expect(find.textContaining('%'), findsNothing);
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
      expect(find.textContaining('%'), findsNothing);
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
      semantics.dispose();
    });

    testWidgets('in French, the percent sign as French writes it', (
      tester,
    ) async {
      await tester.pumpWidget(
        wait(TorWait.connecting, percent: 42, locale: const Locale('fr')),
      );

      expect(find.text('42\u00a0%'), findsOneWidget);
    });
  });

  group('in the tab', () {
    late GetIt locator;
    late StreamController<P2pTorReport> reports;

    setUp(() {
      locator = GetIt.asNewInstance();
      reports = StreamController<P2pTorReport>.broadcast();
      setUpP2pForTesting(
        locator,
        transport: FakeTransport(),
        torReports: () => reports.stream,
        clock: () => testNow,
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
        expect(find.textContaining('%'), findsNothing);

        reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.42));
        await settle(tester);
        expect(find.text('42%'), findsOneWidget);

        reports.add(P2pTorReport(P2pTorState.connecting, progress: 1));
        await settle(tester);
        expect(find.text('99%'), findsOneWidget);
        expect(find.text('100%'), findsNothing);

        reports.add(P2pTorReport(P2pTorState.ready));
        await settle(tester);
        expect(find.byType(BookView), findsOneWidget);
        expect(find.byType(TorWaitView), findsNothing);
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
    });

    testWidgets(
      'a failure hides the percentage; Retry starts a new wait without one',
      (tester) async {
        await open(tester);
        reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.3));
        await settle(tester);
        expect(find.text('30%'), findsOneWidget);

        reports.add(P2pTorReport(P2pTorState.failed));
        await settle(tester);
        expect(find.text('Connection error'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);

        await tester.tap(find.text('Retry'));
        await settle(tester);
        expect(find.text('Initializing Tor daemon'), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
      },
    );
  });
}
