import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/bond_warning.dart';
import 'package:p2p/src/presentation/p2p_failure_l10n.dart';
import 'package:p2p/src/ui/widgets/coordinator_avatar.dart';
import 'package:p2p/src/ui/widgets/expiry_ring.dart';
import 'package:p2p/src/ui/widgets/maker_avatar.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/src/ui/widgets/reversible_payments_dialog.dart';
import 'package:p2p/src/ui/widgets/robot_avatar.dart';
import 'package:primitives/primitives.dart';
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
      expect(
        await ringColor(tester, const Duration(hours: 1)),
        testBullTheme.error,
      );
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
      expect(
        await ringColor(tester, const Duration(hours: 20)),
        testBullTheme.success,
      );
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

  group('the badge of a maker', () {
    /// Temple of Sats, or a copy of it that is not a coordinator of the federation.
    Coordinator temple({required bool federated}) {
      final temple = coordinator('temple');
      return Coordinator(
        shortAlias: temple.shortAlias,
        longAlias: temple.longAlias,
        identifier: temple.identifier,
        description: temple.description,
        motto: temple.motto,
        color: temple.color,
        established: temple.established,
        nostrHexPubkey: temple.nostrHexPubkey,
        contact: temple.contact,
        badges: temple.badges,
        policies: temple.policies,
        mainnet: temple.mainnet,
        testnet: temple.testnet,
        mainnetNodesPubkeys: temple.mainnetNodesPubkeys,
        testnetNodesPubkeys: temple.testnetNodesPubkeys,
        federated: federated,
      );
    }

    /// Shows the row of an order of Temple of Sats, read from its book as the app reads it.
    Future<void> showRow(
      WidgetTester tester, {
      bool federated = true,
      Locale locale = const Locale('en'),
    }) async {
      final result = await CoordinatorClient(
        FakeTransport(
          books: {
            'temple': [bookOrder(id: 1)],
          },
        ),
        clock: () => testNow,
      ).fetchBook(temple(federated: federated), RobosatsNetwork.mainnet);
      final order = switch (result) {
        Ok(:final value) => value.orders.single,
        Err(:final failure) => throw StateError('$failure'),
      };
      usePhoneScreen(tester);
      await tester.pumpWidget(
        harness(
          OfferRow(order: order, now: testNow, onTap: () {}),
          locale: locale,
        ),
      );
    }

    testWidgets(
      'lies over the robot\'s bottom-left corner, on top of it, and takes no room',
      (tester) async {
        await showRow(tester);

        final robot = tester.getRect(find.byType(RobotAvatar));
        final badge = find.byType(CoordinatorAvatar);
        expect(
          tester.widget<CoordinatorAvatar>(badge).coordinator.shortAlias,
          'temple',
        );
        // The robot keeps its size and its place, after the row's padding.
        expect(robot.size, const Size.square(40));
        expect(robot.left, tester.getRect(find.byType(OfferRow)).left + 16);
        // Two fifths of the robot, passing its left and bottom edges by 8 % of it.
        expect(
          tester.getRect(badge),
          Rect.fromLTWH(robot.left - 3.2, robot.bottom + 3.2 - 16, 16, 16),
        );
        // Drawn after the robot, so over it, and not cut where it passes the robot's box.
        final stack = tester.widget<Stack>(
          find.descendant(
            of: find.byType(MakerAvatar),
            matching: find.byType(Stack),
          ),
        );
        expect(stack.children.last, isA<Positioned>());
        expect(stack.clipBehavior, Clip.none);
      },
    );

    for (final (locale, announced) in [
      (
        const Locale('en'),
        'Temple of Sats\nObliquePlush348\nSeller\nInstant SEPA · Revolut\nPremium +2.0% · Bond 3%\n100 EUR\n17h',
      ),
      (
        const Locale('fr'),
        'Temple of Sats\nObliquePlush348\nVendeur\nInstant SEPA · Revolut\nPrime +2,0\u00a0% · Caution 3\u00a0%\n100 EUR\n17 h',
      ),
    ]) {
      testWidgets(
        'tells a screen reader the coordinator\'s name, in a row that stays one announcement, in ${locale.languageCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await showRow(tester, locale: locale);

          final row = tester.getSemantics(find.byType(OfferRow));
          expect(row.label, announced);
          expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
          semantics.dispose();
        },
      );
    }

    testWidgets('only a coordinator of the federation is badged', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await showRow(tester, federated: false);

      expect(find.byType(RobotAvatar), findsOneWidget);
      expect(find.byType(CoordinatorAvatar), findsNothing);
      expect(
        tester.getSemantics(find.byType(OfferRow)).label,
        isNot(contains('Temple of Sats')),
      );
      semantics.dispose();
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

  group('the text of a coordinator failure', () {
    Future<void> show(WidgetTester tester, CoordinatorFailure failure) =>
        tester.pumpWidget(
          harness(
            Builder(builder: (context) => Text(failure.toTranslated(context))),
          ),
        );

    testWidgets('says offline for a coordinator that could not be reached', (
      tester,
    ) async {
      for (final failure in const <CoordinatorFailure>[
        CoordinatorUnreachable(),
        CoordinatorTimedOut(),
        CoordinatorTransportFailed(),
        CoordinatorNotOnNetwork(),
      ]) {
        await show(tester, failure);

        expect(find.text('Coordinator offline'), findsOneWidget);
      }
    });

    testWidgets('does not say offline when the transport was busy', (
      tester,
    ) async {
      await show(tester, const CoordinatorTransportBusy());

      expect(find.text('Coordinator offline'), findsNothing);
      expect(find.text('An error occurred.'), findsOneWidget);
    });
  });
}
