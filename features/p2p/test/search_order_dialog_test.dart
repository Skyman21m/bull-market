import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/order_search.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';

import 'support/harness.dart';

void main() {
  setUpAll(() async {
    // The app's own font, which the feature's harness does not set: with Flutter's test font, whose letters are wider, the old row overflowed in cases where the app does not.
    final golos = FontLoader('Golos Text')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('../../assets/fonts/GolosText.ttf').readAsBytesSync(),
          ),
        ),
      );
    await golos.load();
  });

  /// Opens « Search order » on a screen of [width] points at [textScale], in [locale], in the app's font.
  Future<void> open(
    WidgetTester tester, {
    required Locale locale,
    required double textScale,
    required double width,
  }) async {
    tester.view
      ..physicalSize = Size(width * 2, (width < 360 ? 568 : 844) * 2.0)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme.copyWith(
          textTheme: testTheme.textTheme.apply(fontFamily: 'Golos Text'),
        ),
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

  // The cases where « Cancel » and « Search » are too wide for one row, measured with the app's font: the old `Row` overflowed in exactly these (by 5.7, 20 and 69 points).
  final stacked = {('en', 320.0, 2.0), ('fr', 320.0, 1.5), ('fr', 320.0, 2.0)};

  for (final (locale, cancel, search) in [
    (const Locale('en'), 'Cancel', 'Search'),
    (const Locale('fr'), 'Annuler', 'Rechercher'),
  ]) {
    for (final width in [320.0, 390.0]) {
      for (final textScale in [1.0, 1.5, 2.0]) {
        final stacks = stacked.contains((
          locale.languageCode,
          width,
          textScale,
        ));
        testWidgets(
          'at $width points and text size $textScale, in ${locale.languageCode}: the buttons ${stacks ? 'stack, right-aligned' : 'sit side by side on the right'}',
          (tester) async {
            await open(
              tester,
              locale: locale,
              textScale: textScale,
              width: width,
            );

            // An overflow would have failed the test already.
            final dialog = tester.getRect(find.byType(SearchOrderDialog));
            final cancelButton = find.widgetWithText(TextButton, cancel);
            final searchButton = find.widgetWithText(TextButton, search);
            await tester.ensureVisible(searchButton);
            await settle(tester);
            final cancelRect = tester.getRect(cancelButton);
            final searchRect = tester.getRect(searchButton);
            for (final rect in [cancelRect, searchRect]) {
              expect(rect.left, greaterThanOrEqualTo(dialog.left - 0.5));
              expect(rect.right, lessThanOrEqualTo(dialog.right + 0.5));
            }
            // « Search » ends on the right edge either way, as the actions of a Material dialog.
            expect(searchRect.right, closeTo(dialog.right, 0.5));
            if (stacks) {
              // « Cancel » above « Search », both on the right.
              expect(
                searchRect.top,
                greaterThanOrEqualTo(cancelRect.bottom - 0.5),
              );
              expect(cancelRect.right, closeTo(dialog.right, 0.5));
            } else {
              // Side by side, « Cancel » just before « Search », with no space added between them.
              expect(cancelRect.top, closeTo(searchRect.top, 0.5));
              expect(cancelRect.right, closeTo(searchRect.left, 0.5));
            }

            // « Search » still searches: the text is not an order URL, so the field turns red and the dialog stays.
            await tester.tap(searchButton);
            await settle(tester);
            expect(find.byType(SearchOrderDialog), findsOneWidget);
            await tester.ensureVisible(cancelButton);
            await settle(tester);
            await tester.tap(cancelButton);
            await settle(tester);
            expect(find.byType(SearchOrderDialog), findsNothing);
          },
        );
      }
    }
  }
}
