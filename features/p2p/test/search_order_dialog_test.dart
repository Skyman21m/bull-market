import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/order_search.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';

import 'support/harness.dart';

void main() {
  /// Opens « Search order » on a screen of [width] by 568 points at [textScale], in [locale].
  Future<void> open(
    WidgetTester tester, {
    required Locale locale,
    required double textScale,
    double width = 320,
  }) async {
    tester.view
      ..physicalSize = Size(width * 2, 568 * 2)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        locale: locale,
        localizationsDelegates: P2pLocalizations.localizationsDelegates,
        supportedLocales: P2pLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => SearchOrderDialog.show(
                  context,
                  (_) => const OrderSearchInvalidUrl(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);
  }

  for (final (locale, cancel, search) in [
    (const Locale('en'), 'Cancel', 'Search'),
    (const Locale('fr'), 'Annuler', 'Rechercher'),
  ]) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets(
        'on a 320-point screen at text size $textScale, in ${locale.languageCode}: both buttons fit',
        (tester) async {
          await open(tester, locale: locale, textScale: textScale);

          // An overflow would have failed the test already.
          final dialog = tester.getRect(find.byType(SearchOrderDialog));
          for (final label in [cancel, search]) {
            final button = find.widgetWithText(TextButton, label);
            expect(button, findsOneWidget, reason: label);
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(dialog.left), reason: label);
            expect(rect.right, lessThanOrEqualTo(dialog.right), reason: label);
          }
          // « Search » still searches: the text is not an order URL, so the field turns red and the dialog stays; at a large text size the dialog scrolls to its buttons.
          await tester.ensureVisible(find.widgetWithText(TextButton, search));
          await settle(tester);
          await tester.tap(find.widgetWithText(TextButton, search));
          await settle(tester);
          expect(find.byType(SearchOrderDialog), findsOneWidget);
          await tester.ensureVisible(find.widgetWithText(TextButton, cancel));
          await settle(tester);
          await tester.tap(find.widgetWithText(TextButton, cancel));
          await settle(tester);
          expect(find.byType(SearchOrderDialog), findsNothing);
        },
      );
    }
  }

  testWidgets('on a phone at text size 1.0 the two buttons stay side by side', (
    tester,
  ) async {
    await open(tester, locale: const Locale('en'), textScale: 1, width: 390);
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    final search = tester.getRect(find.widgetWithText(TextButton, 'Search'));
    expect(cancel.top, search.top);
    expect(cancel.right, lessThanOrEqualTo(search.left));
  });
}
