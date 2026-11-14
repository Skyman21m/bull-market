import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/presentation/book_cubit.dart';
import 'package:p2p/src/ui/book_view.dart';
import 'package:p2p/src/ui/widgets/coordinator_avatar.dart';
import 'package:p2p/src/ui/widgets/coordinators_row.dart';
import 'package:p2p/src/ui/widgets/filter_choice.dart';
import 'package:p2p/src/ui/widgets/filter_sheet.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The filter sentence of the book in the tab (#101): the selectors named while nothing is chosen, several currencies, payment methods and hosts, and the sheets that choose them.
void main() {
  late GetIt locator;
  late FakeTransport transport;
  late StreamController<P2pTorState> tor;

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = StreamController<P2pTorState>.broadcast();
    transport = FakeTransport(
      books: {
        'temple': [
          bookOrder(id: 1, paymentMethod: 'Revolut Instant SEPA'),
          bookOrder(id: 2, paymentMethod: 'Wise', makerSeed: 2),
          bookOrder(id: 3, currency: 1, paymentMethod: 'Zelle', makerSeed: 3),
          bookOrder(id: 4, type: 0, paymentMethod: 'Revolut', makerSeed: 4),
        ],
        'lake': [
          bookOrder(id: 5, paymentMethod: 'Instant SEPA', makerSeed: 5),
          bookOrder(id: 6, currency: 7, paymentMethod: 'Bizum', makerSeed: 6),
        ],
        'freeport': [bookOrder(id: 7, paymentMethod: 'Revolut', makerSeed: 7)],
      },
    );
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
    );
  });

  tearDown(() async {
    await tor.close();
    await locator.reset();
  });

  /// The tab on a screen of [size] points, its book received.
  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
    tor.add(P2pTorState.ready);
    await settle(tester);
  }

  /// The open sheet of the filter, whatever the type of its options.
  final sheet = find.byWidgetPredicate((widget) => widget is FilterSheet);

  /// The ids of the offers the book lists, in their order, those below the screen included: the list builds only the rows on screen.
  List<int> listed(WidgetTester tester) => [
    for (final order in BlocProvider.of<BookCubit>(
      tester.element(find.byType(BookFilterSentence)),
    ).state.orders)
      order.id,
  ];

  /// The selector of the sentence that shows [label].
  Finder choice(String label) => find.descendant(
    of: find.byType(FilterChoice),
    matching: find.text(label),
  );

  /// The row of the open sheet that shows [label].
  Finder row(String label) =>
      find.descendant(of: sheet, matching: find.text(label));

  /// Scrolls [target] into view, then taps it.
  Future<void> tapShown(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  /// Scrolls the open sheet until the row [label] is built and shown, then taps it: the list builds only the rows near the screen.
  Future<void> pickRow(WidgetTester tester, String label) async {
    if (row(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        row(label),
        100,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
    }
    await tester.ensureVisible(row(label));
    await settle(tester);
    await tester.tap(row(label));
    await settle(tester);
  }

  /// Closes the open sheet by its button, or, when its title has scrolled away with the button, by a tap above it.
  Future<void> closeSheet(WidgetTester tester) async {
    final button = find
        .descendant(of: sheet, matching: find.byIcon(Icons.close))
        .hitTestable();
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
    } else {
      await tester.tapAt(const Offset(4, 4));
    }
    await settle(tester);
    expect(sheet, findsNothing);
  }

  group('nothing chosen', () {
    testWidgets('each selector names its subject, in English', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);

      expect(find.text('I want'), findsOneWidget);
      expect(find.text('I want to'), findsNothing);
      for (final label in [
        'Any type',
        'Any currency',
        'Any payment method',
        'Any host',
      ]) {
        expect(choice(label), findsOneWidget, reason: label);
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.text('ANY'), findsNothing);
      expect(listed(tester), [1, 2, 3, 4, 5, 6, 7]);
      semantics.dispose();
    });

    testWidgets('each selector names its subject, in French', (tester) async {
      await open(tester, locale: const Locale('fr'));

      expect(find.text('Je veux'), findsOneWidget);
      for (final label in [
        'Tout type',
        'Toute devise',
        'Tout mode de paiement',
        'Tout hôte',
      ]) {
        expect(choice(label), findsOneWidget, reason: label);
      }
      expect(find.text('Tous'), findsNothing);
    });
  });

  testWidgets('the order type is one choice, and « I want to » once made', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await tester.tap(choice('Any type'));
    await settle(tester);
    expect(find.byType(FilterPickerSheet<BookSide>), findsOneWidget);
    expect(find.text('Select Order Type'), findsOneWidget);
    await tester.tap(find.text('Buy').last);
    await settle(tester);

    // The picker closes on the choice, as the official client's select does.
    expect(find.byType(FilterPickerSheet<BookSide>), findsNothing);
    expect(find.text('I want to'), findsOneWidget);
    expect(choice('Buy'), findsOneWidget);
    expect(find.bySemanticsLabel('Order type: Buy'), findsOneWidget);
    expect(listed(tester), [1, 2, 3, 5, 6, 7]);

    await tester.tap(choice('Buy'));
    await settle(tester);
    await tester.tap(find.text('Any type').last);
    await settle(tester);
    expect(find.text('I want'), findsOneWidget);
    expect(listed(tester), [1, 2, 3, 4, 5, 6, 7]);
    semantics.dispose();
  });

  testWidgets(
    'the currency sheet: check marks, several chosen at once, « Any currency » clears',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);

      await tester.tap(choice('Any currency'));
      await settle(tester);
      expect(find.text('Select Payment Currency'), findsOneWidget);
      // « Any currency » first, checked while nothing is chosen.
      final rows = tester
          .widgetList<Text>(
            find.descendant(of: sheet, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      expect(rows.take(3), ['Select Payment Currency', 'Any currency', 'USD']);
      expect(
        tester.getSemantics(row('Any currency')),
        isSemantics(label: 'Any currency', isChecked: true, hasTapAction: true),
      );

      await tester.tap(row('EUR'));
      await settle(tester);
      // Applied at once, the sheet still open for more.
      expect(sheet, findsOneWidget);
      expect(listed(tester), [1, 2, 4, 5, 7]);
      expect(
        tester.getSemantics(row('EUR')),
        isSemantics(label: 'EUR', isChecked: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(row('Any currency')),
        isSemantics(label: 'Any currency', isChecked: false),
      );

      await tester.tap(row('CHF'));
      await settle(tester);
      expect(listed(tester), [1, 2, 4, 5, 6, 7]);
      await closeSheet(tester);

      expect(choice('EUR +1'), findsOneWidget);
      expect(find.bySemanticsLabel('Currency: EUR or CHF'), findsOneWidget);

      // Taking a choice back, then clearing them all.
      await tester.tap(choice('EUR +1'));
      await settle(tester);
      expect(
        tester.getSemantics(row('CHF')),
        isSemantics(label: 'CHF', isChecked: true),
      );
      await tester.tap(row('EUR'));
      await settle(tester);
      expect(listed(tester), [6]);
      await tester.tap(row('Any currency'));
      await settle(tester);
      expect(
        tester.getSemantics(row('CHF')),
        isSemantics(label: 'CHF', isChecked: false),
      );
      await closeSheet(tester);
      expect(choice('Any currency'), findsOneWidget);
      expect(listed(tester), [1, 2, 3, 4, 5, 6, 7]);
      semantics.dispose();
    },
  );

  testWidgets('the empty book names every currency chosen', (tester) async {
    await open(tester);

    await tester.tap(choice('Any currency'));
    await settle(tester);
    await tester.tap(row('JPY'));
    await settle(tester);
    await tester.tap(row('GBP'));
    await settle(tester);
    await tester.tap(row('AUD'));
    await settle(tester);
    await closeSheet(tester);

    expect(listed(tester), isEmpty);
    expect(
      find.text('No orders found to buy BTC for JPY, GBP or AUD'),
      findsOneWidget,
    );
  });

  testWidgets('several payment methods keep the orders that contain one of them', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    await tester.tap(choice('Any payment method'));
    await settle(tester);
    expect(find.text('Select Payment Method'), findsOneWidget);
    await tester.tap(row('Wise'));
    await settle(tester);
    await tester.tap(row('Zelle'));
    await settle(tester);
    expect(listed(tester), [2, 3]);
    // The rule of the official client: « Instant SEPA » keeps every order whose text contains it.
    await tester.tap(row('Instant SEPA'));
    await settle(tester);
    expect(listed(tester), [1, 2, 3, 5]);
    await closeSheet(tester);

    expect(choice('Wise +2'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Payment method: Wise, Zelle or Instant SEPA'),
      findsOneWidget,
    );

    // A method chosen stays in the list when another choice hides its orders, so that it can be taken back.
    await tester.tap(choice('Any currency'));
    await settle(tester);
    await tester.tap(row('CHF'));
    await settle(tester);
    await closeSheet(tester);
    expect(listed(tester), isEmpty);
    await tester.tap(choice('Wise +2'));
    await settle(tester);
    for (final method in ['Wise', 'Zelle', 'Instant SEPA', 'Bizum']) {
      expect(row(method), findsOneWidget, reason: method);
    }
    expect(row('Revolut'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'several hosts keep their orders; every coordinator is still asked and shown',
    (tester) async {
      await open(tester);
      final asked = [...transport.requested];

      await tester.tap(choice('Any host'));
      await settle(tester);
      expect(find.text('Select Host'), findsOneWidget);
      // Each coordinator with its image, as the official client's host select shows them.
      for (final coordinator in Federation.robosats.on(
        RobosatsNetwork.mainnet,
      )) {
        expect(row(coordinator.longAlias), findsOneWidget);
      }
      expect(
        find.descendant(of: sheet, matching: find.byType(CoordinatorAvatar)),
        findsNWidgets(6),
      );

      await tester.tap(row('TheBigLake'));
      await settle(tester);
      expect(listed(tester), [5, 6]);
      await tester.tap(row('FreePort'));
      await settle(tester);
      expect(listed(tester), [5, 6, 7]);
      await closeSheet(tester);

      expect(choice('TheBigLake +1'), findsOneWidget);
      expect(find.byType(CoordinatorRowPlace), findsNWidgets(6));
      expect(transport.requested, asked);
    },
  );

  testWidgets('the choices stay while the tab lives', (tester) async {
    await open(tester);
    await tester.tap(choice('Any currency'));
    await settle(tester);
    await tester.tap(row('EUR'));
    await settle(tester);
    await tester.tap(row('USD'));
    await settle(tester);
    await closeSheet(tester);

    await tester.tap(find.text('Chart'));
    await settle(tester);
    await tester.tap(find.text('List'));
    await settle(tester);

    expect(choice('EUR +1'), findsOneWidget);
    expect(listed(tester), [1, 2, 3, 4, 5, 7]);
  });

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: nothing overflows or is cut',
          (tester) async {
            await open(tester, locale: locale, size: const Size(320, 568));
            final l10n = lookupP2pLocalizations(locale);

            // Several of each, chosen through the cubit: the sheets are tested above.
            BlocProvider.of<BookCubit>(
                tester.element(find.byType(BookFilterSentence)),
              )
              ..selectSide(BookSide.buy)
              ..selectCurrencies([
                for (final code in ['EUR', 'USD', 'CHF'])
                  RobosatsCurrency.all.firstWhere((c) => c.code == code),
              ])
              ..selectPaymentMethods(['Instant SEPA', 'Revolut'])
              ..selectHosts([coordinator('temple'), coordinator('lake')]);
            await settle(tester);

            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await settle(tester);
            expect(tester.takeException(), isNull);

            final screen = Offset.zero & const Size(320, 568);
            for (final label in [
              l10n.p2pBookFilterBuy,
              l10n.p2pBookFilterMore('EUR', 2),
              l10n.p2pBookFilterMore('Instant SEPA', 1),
              l10n.p2pBookFilterMore('Temple of Sats', 1),
            ]) {
              final box = find.ancestor(
                of: choice(label),
                matching: find.byType(FilterChoice),
              );
              final rect = tester.getRect(box);
              expect(
                rect.left,
                greaterThanOrEqualTo(screen.left),
                reason: label,
              );
              expect(
                rect.right,
                lessThanOrEqualTo(screen.right),
                reason: label,
              );
              final paragraph = tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: choice(label),
                  matching: find.byType(RichText),
                ),
              );
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
            }

            // The sheets too.
            await tapShown(
              tester,
              choice(l10n.p2pBookFilterMore('Temple of Sats', 1)),
            );
            expect(tester.takeException(), isNull);
            await closeSheet(tester);
            // Nothing chosen, the longest label.
            await tapShown(
              tester,
              choice(l10n.p2pBookFilterMore('Instant SEPA', 1)),
            );
            await pickRow(tester, l10n.p2pBookFilterAnyMethod);
            expect(tester.takeException(), isNull);
            await closeSheet(tester);
            final any = find.ancestor(
              of: choice(l10n.p2pBookFilterAnyMethod),
              matching: find.byType(FilterChoice),
            );
            expect(tester.getRect(any).right, lessThanOrEqualTo(320));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
