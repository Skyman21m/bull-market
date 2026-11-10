import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';

/// The theme of the tests: the test colours of `bull_ui` and the text sizes of the app (`lib/core/themes/fonts.dart`).
final testTheme = ThemeData(
  extensions: const [testBullTheme],
  textTheme: const TextTheme(
    displaySmall: TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
    headlineLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    headlineSmall: TextStyle(fontSize: 16),
    bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(fontSize: 14),
    labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 12),
    labelSmall: TextStyle(fontSize: 10),
  ),
);

/// Shows [child] with the test theme of `bull_ui` and the texts of the feature in [locale], animations off.
Widget harness(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: testTheme,
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          disableAnimations: true,
        ),
        child: Scaffold(body: child),
      ),
    );

/// Pumps frames for half a second: the futures of the fakes, the stream of the cubit, and the opening of a sheet or a page.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Gives the test the screen of a phone, 390 by 844 points.
void usePhoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Shows the pages of [router] as [harness] does.
Widget routerHarness(GoRouter router, {Locale locale = const Locale('en')}) =>
    MaterialApp.router(
      routerConfig: router,
      theme: testTheme,
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
