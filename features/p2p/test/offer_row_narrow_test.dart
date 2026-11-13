import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// An offer of each side on a phone 320 points wide, at the text sizes a user may ask for: the line of the role and the payment methods fits, the role shrinking only when it alone is wider than the line.
void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    for (final textScale in const [1.0, 1.5, 2.0, 3.0]) {
      testWidgets(
        'an offer fits 320 points at text size $textScale, in ${locale.languageCode}',
        (tester) async {
          const size = Size(320, 568);
          tester.view
            ..physicalSize = size * 3
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final orders = await parseOrders([
            bookOrder(id: 1, type: 1, paymentMethod: 'Revolut Instant SEPA'),
            bookOrder(id: 2, type: 0, makerSeed: 2, paymentMethod: 'Wise'),
          ]);
          await tester.pumpWidget(
            MaterialApp(
              theme: testTheme,
              locale: locale,
              localizationsDelegates: P2pLocalizations.localizationsDelegates,
              supportedLocales: P2pLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: Scaffold(
                  body: ListView(
                    children: [
                      for (final order in orders)
                        OfferRow(order: order, now: testNow, onTap: () {}),
                    ],
                  ),
                ),
              ),
            ),
          );

          // An overflow would have failed the test already.
          final pills = find.byType(RolePill);
          expect(pills, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            expect(
              tester.getRect(pills.at(i)).right,
              lessThanOrEqualTo(size.width),
            );
          }
        },
      );
    }
  }
}
