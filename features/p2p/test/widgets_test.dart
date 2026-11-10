import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/bond_warning.dart';
import 'package:p2p/src/ui/widgets/expiry_ring.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/reversible_payments_dialog.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  group('expiry ring', () {
    Future<Color?> ringColor(WidgetTester tester, Duration left) async {
      await tester.pumpWidget(
        harness(ExpiryRing(expiresAt: testNow.add(left), now: testNow)),
      );
      return tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color;
    }

    // As in the official client: red under 15 % of a day, orange under 30 %, green above.
    testWidgets('red, orange and green around 15 % and 30 % of a day', (
      tester,
    ) async {
      expect(await ringColor(tester, const Duration(hours: 1)), testBullTheme.error);
      expect(
        await ringColor(tester, const Duration(hours: 3, minutes: 30)),
        testBullTheme.error,
      );
      expect(
        await ringColor(tester, const Duration(hours: 3, minutes: 40)),
        testBullTheme.warning,
      );
      expect(
        await ringColor(tester, const Duration(hours: 7, minutes: 5)),
        testBullTheme.warning,
      );
      expect(
        await ringColor(tester, const Duration(hours: 7, minutes: 20)),
        testBullTheme.success,
      );
      expect(await ringColor(tester, const Duration(hours: 20)), testBullTheme.success);
    });

    testWidgets('an expired order shows an empty red ring', (tester) async {
      expect(
        await ringColor(tester, const Duration(minutes: -5)),
        testBullTheme.error,
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0,
      );
    });
  });

  group('low bond', () {
    BondSize bond(double percent) =>
        BondSize.tryCreate(percent) ?? (throw ArgumentError('$percent'));

    test('below the default of 3 % only', () {
      expect(bond(2).isLow, isTrue);
      expect(bond(2.9).isLow, isTrue);
      expect(bond(3).isLow, isFalse);
      expect(bond(5).isLow, isFalse);
      expect(bond(2).warningIntensity, closeTo(1 / 3, 1e-9));
      expect(bond(3).warningIntensity, 0);
    });

    Future<void> showRow(WidgetTester tester, double bondPercent) async {
      final [order] = await parseOrders([bookOrder(id: 1, bond: bondPercent)]);
      usePhoneScreen(tester);
      await tester.pumpWidget(
        harness(OfferRow(order: order, now: testNow, onTap: () {})),
      );
    }

    testWidgets('a low bond is orange, bold, and explained', (tester) async {
      await showRow(tester, 2);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(
        tooltip.message,
        'Low bond: This maker has set a bond below the default 3%. Lower bonds mean reduced trade security.',
      );
      final line = tester.widget<Text>(
        find.textContaining('Bond', findRichText: false),
      );
      final bondSpan = (line.textSpan as TextSpan).children?.last as TextSpan;
      expect(bondSpan.text, '2%');
      expect(bondSpan.style?.color, testBullTheme.warning);
      expect(bondSpan.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('the default bond has no warning', (tester) async {
      await showRow(tester, 3);

      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('reversible payments', () {
    testWidgets('the dialog names the reversible methods and the risks', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          ReversiblePaymentsDialog(
            methods: PaymentMethods.parse('Revolut Instant SEPA'),
          ),
        ),
      );

      expect(find.text('Reversible payments'), findsOneWidget);
      expect(
        find.text(
          'This order offers one or multiple payment methods that the community has consistently reported as reverting their transactions.',
        ),
        findsOneWidget,
      );
      // Only the reversible one of the two methods.
      expect(find.text('Revolut'), findsOneWidget);
      expect(
        find.text(
          'If you receive a fiat transaction, it can be unilatery reverted up to 80 days after the trade has been completed.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Robosats and their coordinators have no control over the fiat system.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Scammers can exploit this vulnerability in the fiat system to take away both your bitcoin and your fiat.',
        ),
        findsOneWidget,
      );
      expect(find.text('Acknowledged'), findsOneWidget);
    });

    testWidgets('in French', (tester) async {
      await tester.pumpWidget(
        harness(
          ReversiblePaymentsDialog(methods: PaymentMethods.parse('Revolut')),
          locale: const Locale('fr'),
        ),
      );

      expect(find.text('Paiements réversibles'), findsOneWidget);
      expect(find.text('Compris'), findsOneWidget);
    });
  });
}
