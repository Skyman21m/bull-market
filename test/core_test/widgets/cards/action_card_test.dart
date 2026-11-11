import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/cards/action_card.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    // The app's own font, whose line is taller than the test font's: the overflow of issue #51 shows with it.
    final golos = FontLoader('Golos Text')
      ..addFont(rootBundle.load('assets/fonts/GolosText.ttf'));
    await golos.load();
  });

  /// The row of the wallet home on a phone 390 points wide, inside the 13-point side padding of `WalletHomeTopSection`.
  Future<void> pumpRow(
    WidgetTester tester, {
    required Locale locale,
    required double textScale,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeData(AppThemeType.dark),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 13),
              child: ActionCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (locale, labels) in [
    (const Locale('en'), ['Buy', 'Sell', 'Pay', 'Transfer']),
    (const Locale('fr'), ['Acheter', 'Vendre', 'Payer', 'Transférer']),
  ]) {
    for (final textScale in [1.0, 1.15, 1.3, 2.0]) {
      testWidgets(
        'in ${locale.languageCode} at text size $textScale: every label fits its button, the card keeps its height',
        (tester) async {
          await pumpRow(tester, locale: locale, textScale: textScale);

          // An overflow would have failed the test already; the card keeps its 80 points and its 1-point bottom border, on which the pinned header relies.
          expect(tester.getSize(find.byType(ActionCard)).height, 81);
          final buttons = find.descendant(
            of: find.byType(ActionCard),
            matching: find.byType(InkWell),
          );
          expect(buttons, findsNWidgets(4));
          for (final (index, label) in labels.indexed) {
            final button = tester.getRect(buttons.at(index));
            // Where the label is painted, after any shrinking.
            final shown = tester.getRect(find.text(label));
            expect(
              shown.left,
              greaterThanOrEqualTo(button.left),
              reason: label,
            );
            expect(shown.right, lessThanOrEqualTo(button.right), reason: label);
            expect(shown.top, greaterThanOrEqualTo(button.top), reason: label);
            expect(
              shown.bottom,
              lessThanOrEqualTo(button.bottom),
              reason: label,
            );
          }
        },
      );
    }
  }

  testWidgets(
    'at text size 1.0 the labels are not shrunk: the look is unchanged',
    (tester) async {
      // « Transférer » is left out: on a 390-point phone it is wider than its button, and used to wrap onto a second line that overflowed the card.
      for (final (locale, labels) in [
        (const Locale('en'), ['Buy', 'Sell', 'Pay', 'Transfer']),
        (const Locale('fr'), ['Acheter', 'Vendre', 'Payer']),
      ]) {
        await pumpRow(tester, locale: locale, textScale: 1);
        for (final label in labels) {
          // The painted size equals the laid-out size: no scaling.
          expect(
            tester.getRect(find.text(label)).size,
            tester.getSize(find.text(label)),
            reason: label,
          );
        }
      }
    },
  );

  testWidgets('at text size 2.0 a label is shrunk, not cut', (tester) async {
    await pumpRow(tester, locale: const Locale('fr'), textScale: 2);
    final laidOut = tester.getSize(find.text('Transférer'));
    final shown = tester.getRect(find.text('Transférer')).size;
    expect(shown.width, lessThan(laidOut.width));
    // Shrunk evenly, so the whole word is still drawn.
    expect(
      shown.width / laidOut.width,
      closeTo(shown.height / laidOut.height, 1e-6),
    );
  });
}
