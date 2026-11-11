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

  /// The row of the wallet home on a phone [width] points wide, inside the 13-point side padding of `WalletHomeTopSection`.
  Future<void> pumpRow(
    WidgetTester tester, {
    required Locale locale,
    required double textScale,
    double width = 390,
  }) async {
    tester.view
      ..physicalSize = Size(width * 3, 844 * 3)
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

  Finder inCard(Finder finder) =>
      find.descendant(of: find.byType(ActionCard), matching: finder);

  /// How much a label is shrunk: 1 when it is drawn at its own size.
  double scaleOf(WidgetTester tester, String label) =>
      tester.getRect(find.text(label)).width /
      tester.getSize(find.text(label)).width;

  const english = ['Buy', 'Sell', 'Pay', 'Transfer'];
  const french = ['Acheter', 'Vendre', 'Payer', 'Transférer'];

  for (final (locale, labels) in [
    (const Locale('en'), english),
    (const Locale('fr'), french),
  ]) {
    for (final width in [320.0, 360.0, 390.0]) {
      for (final textScale in [1.0, 1.15, 1.3, 2.0]) {
        testWidgets(
          'in ${locale.languageCode}, $width points wide, at text size $textScale: every label on one line inside its button',
          (tester) async {
            await pumpRow(
              tester,
              locale: locale,
              textScale: textScale,
              width: width,
            );

            // What tells the fix: the old card overflowed in many of these cases, and wrapped its longest label onto two lines, which would fail the test here.
            // The card's height is a fixed box, 80 points and a 1-point bottom border, so its check is a reminder for the pinned header, not a test of the fix.
            expect(tester.getSize(find.byType(ActionCard)).height, 81);
            final buttons = inCard(find.byType(InkWell));
            expect(buttons, findsNWidgets(4));
            // One line each: every label is laid out as tall as the shortest word of the row.
            final lineHeight = tester.getSize(find.text(labels[2])).height;
            for (final (index, label) in labels.indexed) {
              expect(
                tester.getSize(find.text(label)).height,
                lineHeight,
                reason: label,
              );
              final button = tester.getRect(buttons.at(index));
              // Where the label is painted, after any shrinking.
              final shown = tester.getRect(find.text(label));
              expect(
                shown.left,
                greaterThanOrEqualTo(button.left),
                reason: label,
              );
              expect(
                shown.right,
                lessThanOrEqualTo(button.right),
                reason: label,
              );
              expect(
                shown.top,
                greaterThanOrEqualTo(button.top),
                reason: label,
              );
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
  }

  testWidgets(
    'at text size 1.0, from 390 points wide, the labels are not shrunk: the look is unchanged',
    (tester) async {
      for (final (locale, labels) in [
        (const Locale('en'), english),
        (const Locale('fr'), french),
      ]) {
        await pumpRow(tester, locale: locale, textScale: 1);
        final buttons = inCard(find.byType(InkWell));
        final icons = inCard(find.byType(Image));
        for (final (index, label) in labels.indexed) {
          // The painted size equals the laid-out size: no scaling.
          expect(
            tester.getRect(find.text(label)).size,
            tester.getSize(find.text(label)),
            reason: label,
          );
          // The icon and the label stay centred in the card together, as before: as much room above the icon as below the label.
          final button = tester.getRect(buttons.at(index));
          final icon = tester.getRect(icons.at(index));
          final shown = tester.getRect(find.text(label));
          expect(
            icon.top - button.top,
            closeTo(button.bottom - shown.bottom, 0.5),
            reason: label,
          );
        }
      }
    },
  );

  testWidgets(
    'at text size 1.0, narrower, the longest labels shrink where the old card wrapped them',
    (tester) async {
      // 360 points: the English labels keep their size, « Transférer » is shrunk to about 90%.
      await pumpRow(
        tester,
        locale: const Locale('en'),
        textScale: 1,
        width: 360,
      );
      for (final label in english) {
        expect(scaleOf(tester, label), closeTo(1, 1e-6), reason: label);
      }
      await pumpRow(
        tester,
        locale: const Locale('fr'),
        textScale: 1,
        width: 360,
      );
      expect(scaleOf(tester, 'Transférer'), closeTo(0.905, 0.01));
      expect(scaleOf(tester, 'Acheter'), closeTo(1, 1e-6));
      // 320 points: « Transfer » to about 96%, « Transférer » to about 77%.
      await pumpRow(
        tester,
        locale: const Locale('en'),
        textScale: 1,
        width: 320,
      );
      expect(scaleOf(tester, 'Transfer'), closeTo(0.957, 0.01));
      expect(scaleOf(tester, 'Buy'), closeTo(1, 1e-6));
      await pumpRow(
        tester,
        locale: const Locale('fr'),
        textScale: 1,
        width: 320,
      );
      expect(scaleOf(tester, 'Transférer'), closeTo(0.770, 0.01));
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
