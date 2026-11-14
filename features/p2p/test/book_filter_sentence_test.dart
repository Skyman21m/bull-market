import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
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

  /// The row of the open sheet of [option], whatever its label shows besides it (a payment method's number of orders).
  Finder optionRow(String option) => find.descendant(
    of: sheet,
    matching: find.byKey(ValueKey<String>(option)),
  );

  /// The top of the row of [option] in the open sheet.
  double topOf(WidgetTester tester, String option) =>
      tester.getRect(optionRow(option)).top;

  /// Types [text] in the search field of the open sheet.
  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(of: sheet, matching: find.byType(TextField)),
      text,
    );
    await settle(tester);
  }

  /// Scrolls [target] into view, then taps it.
  Future<void> tapShown(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  /// Scrolls the open sheet until the row [label] is built and shown, then taps it: the list builds only the rows near the screen.
  /// [step] is the scroll of each try, negative for a row above the ones shown.
  /// [target] finds the row instead of its label, such as [optionRow].
  Future<void> pickRow(
    WidgetTester tester,
    String label, {
    double step = 100,
    Finder? target,
  }) async {
    final found = target ?? row(label);
    if (found.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        found,
        step,
        scrollable: find
            .descendant(of: sheet, matching: find.byType(Scrollable))
            .first,
      );
    }
    await tester.ensureVisible(found);
    await settle(tester);
    await tester.tap(found);
    await settle(tester);
  }

  /// Closes the open sheet by its button, or, when its title has scrolled away with the button, by a tap above it.
  Future<void> closeSheet(WidgetTester tester) async {
    // The close button, the one with a tooltip: the search field's button that empties it has the same icon.
    final button = find
        .descendant(
          of: sheet,
          matching: find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip != null,
          ),
        )
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
    // One choice of several, as radio buttons: the screen reader says which is checked and that only one can be.
    Finder typeRow(String label) => find.descendant(
      of: find.byType(FilterPickerSheet<BookSide>),
      matching: find.text(label),
    );
    expect(
      tester.getSemantics(typeRow('Any type')),
      isSemantics(
        label: 'Any type',
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(typeRow('Buy')),
      isSemantics(
        label: 'Buy',
        isChecked: false,
        isInMutuallyExclusiveGroup: true,
      ),
    );
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
        isSemantics(
          label: 'EUR',
          isChecked: true,
          isInMutuallyExclusiveGroup: false,
          hasTapAction: true,
        ),
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
    await pickRow(tester, '', target: optionRow('Wise'));
    await pickRow(tester, '', target: optionRow('Zelle'));
    expect(listed(tester), [2, 3]);
    // The rule of the official client: « Instant SEPA » keeps every order whose text contains it.
    await pickRow(tester, '', step: -100, target: optionRow('Instant SEPA'));
    expect(listed(tester), [1, 2, 3, 5]);
    await closeSheet(tester);

    expect(choice('Wise +2'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Payment method: Wise, Zelle or Instant SEPA'),
      findsOneWidget,
    );

    // With a currency no order has, every method is still offered, the ones chosen and the others.
    await tester.tap(choice('Any currency'));
    await settle(tester);
    await tester.tap(row('CHF'));
    await settle(tester);
    await closeSheet(tester);
    expect(listed(tester), isEmpty);
    await tester.tap(choice('Wise +2'));
    await settle(tester);
    expect(optionRow('Advcash'), findsOneWidget);
    await pickRow(tester, '', step: 300, target: optionRow('Venmo'));
    await closeSheet(tester);
    expect(choice('Wise +3'), findsOneWidget);
    semantics.dispose();
  });

  group('the payment method sheet (#118)', () {
    testWidgets(
      'while no book is known: the official list, no count, no heading; frozen as opened; grouped when reopened',
      (tester) async {
        transport.held.addAll({
          for (final coordinator in Federation.robosats.on(
            RobosatsNetwork.mainnet,
          ))
            coordinator.shortAlias,
        });
        await open(tester);
        await tester.tap(choice('Any payment method'));
        await settle(tester);

        // The book is unknown, not empty: no « No orders right now », no count, nothing dimmed; the official list in its order.
        expect(row('No orders right now'), findsNothing);
        expect(optionRow('Advcash'), findsOneWidget);
        expect(
          tester.getRect(optionRow('Advcash')).top,
          lessThan(tester.getRect(optionRow('Airtel Money')).top),
        );
        expect(optionRow('Revolut'), findsNothing);
        final advcash = tester.widget<Text>(row('Advcash'));
        expect(advcash.style?.color, tester.element(sheet).bull.onSurface);
        await typeSearch(tester, 'rev');
        expect(row('Revolut'), findsOneWidget);
        expect(row('Revolut · 3 orders'), findsNothing);
        await typeSearch(tester, '');

        // The books arrive while the sheet is open: it stays as it was opened.
        for (final coordinator in Federation.robosats.on(RobosatsNetwork.mainnet)) {
          transport.release(coordinator.shortAlias);
        }
        await settle(tester);
        await settle(tester);
        expect(listed(tester), [1, 2, 3, 4, 5, 6, 7]);
        expect(row('No orders right now'), findsNothing);
        expect(optionRow('Revolut'), findsNothing);
        await closeSheet(tester);

        // Reopened: the groups and the counts of the book received.
        await tester.tap(choice('Any payment method'));
        await settle(tester);
        expect(row('Revolut · 3 orders'), findsOneWidget);
        expect(row('No orders right now'), findsOneWidget);
      },
    );

    /// The methods of the open sheet, in the order it lists them, as far as its rows are built.
    List<String> listedMethods(WidgetTester tester) {
      final rows = [
        for (final element
            in find
                .descendant(
                  of: sheet,
                  matching: find.byWidgetPredicate(
                    (widget) => widget.key is ValueKey<String>,
                  ),
                )
                .evaluate())
          element,
      ];
      rows.sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
      return [
        for (final element in rows)
          (element.widget.key as ValueKey<String>).value,
      ];
    }

    testWidgets(
      'the methods of the book first, the most orders first, then the others dimmed under a heading',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester);
        await tester.tap(choice('Any payment method'));
        await settle(tester);

        // Revolut 3 orders, Instant SEPA 2, then Bizum, Wise and Zelle 1 each in the official list's order; then the others from Advcash, in that order.
        expect(listedMethods(tester).take(6), [
          'Revolut',
          'Instant SEPA',
          'Bizum',
          'Wise',
          'Zelle',
          'Advcash',
        ]);
        expect(row('Revolut · 3 orders'), findsOneWidget);
        expect(row('Instant SEPA · 2 orders'), findsOneWidget);
        expect(row('Wise · 1 order'), findsOneWidget);
        expect(row('Advcash'), findsOneWidget);
        final heading = row('No orders right now');
        expect(
          tester.getRect(heading).top,
          greaterThan(topOf(tester, 'Zelle')),
        );
        expect(tester.getRect(heading).top, lessThan(topOf(tester, 'Advcash')));
        expect(
          tester.getSemantics(heading),
          isSemantics(label: 'No orders right now', isHeader: true),
        );
        expect(
          tester.getSemantics(optionRow('Revolut')),
          isSemantics(
            label: 'Revolut, 3 orders',
            isChecked: false,
            hasTapAction: true,
          ),
        );
        // Dimmed but selectable: a screen reader hears no disabled row.
        expect(
          tester.getSemantics(optionRow('Advcash')),
          isSemantics(
            label: 'Advcash',
            isChecked: false,
            hasTapAction: true,
            hasEnabledState: false,
          ),
        );
        final advcash = tester.widget<Text>(row('Advcash'));
        final wise = tester.widget<Text>(row('Wise · 1 order'));
        expect(advcash.style?.color, isNot(wise.style?.color));

        // The rows keep their places while the user ticks, the dimmed one too.
        final before = {
          for (final method in ['Revolut', 'Wise', 'Advcash'])
            method: topOf(tester, method),
        };
        await tester.tap(optionRow('Wise'));
        await settle(tester);
        await tester.tap(optionRow('Advcash'));
        await settle(tester);
        for (final MapEntry(key: method, value: top) in before.entries) {
          expect(topOf(tester, method), top, reason: method);
        }
        expect(
          tester.getSemantics(optionRow('Advcash')),
          isSemantics(label: 'Advcash', isChecked: true),
        );
        // A dimmed method once ticked is drawn as every chosen row, in the primary colour, not in the muted one.
        Color? colourOf(String label) =>
            tester.widget<Text>(row(label)).style?.color;
        expect(colourOf('Advcash'), colourOf('Wise · 1 order'));
        expect(colourOf('Advcash'), isNot(colourOf('Airtel Money')));
        expect(colourOf('Advcash'), isNot(colourOf('Revolut · 3 orders')));
        // No order has Advcash: with Wise or Advcash, Wise's order alone.
        expect(listed(tester), [2]);
        await closeSheet(tester);
        expect(choice('Wise +1'), findsOneWidget);

        // Reopened: the chosen methods first, in the order chosen, in view, each with its count.
        await tester.tap(choice('Wise +1'));
        await settle(tester);
        expect(listedMethods(tester).take(4), [
          'Wise',
          'Advcash',
          'Revolut',
          'Instant SEPA',
        ]);
        expect(row('Wise · 1 order').hitTestable(), findsOneWidget);
        expect(row('Advcash · no orders').hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(optionRow('Advcash')),
          isSemantics(label: 'Advcash, no orders', isChecked: true),
        );
        expect(
          tester.getRect(row('Any payment method')).top,
          lessThan(topOf(tester, 'Wise')),
        );

        // The search field stays at the top of the sheet while its rows scroll under it, on an opaque background, so that no row shows through.
        final field = find.descendant(of: sheet, matching: find.byType(TextField));
        final background = tester.widget<ColoredBox>(
          find.ancestor(of: field, matching: find.byType(ColoredBox)).first,
        );
        expect(background.color.a, 1.0);
        final list = find.descendant(
          of: sheet,
          matching: find.byType(CustomScrollView),
        );
        await tester.drag(list, const Offset(0, -1500));
        await settle(tester);
        expect(field.hitTestable(), findsOneWidget);
        final box = find.ancestor(of: field, matching: find.byType(ColoredBox)).first;
        expect(tester.getRect(box).top, tester.getRect(list).top);
        expect(row('Any payment method'), findsNothing);
        await tester.drag(list, const Offset(0, 3000));
        await settle(tester);

        // « Any payment method » clears every choice.
        await tester.tap(row('Any payment method'));
        await settle(tester);
        expect(listed(tester), [1, 2, 3, 4, 5, 6, 7]);
        await closeSheet(tester);
        expect(choice('Any payment method'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets(
      'the counts follow the other choices, with their plural in French',
      (tester) async {
        await open(tester, locale: const Locale('fr'));
        BlocProvider.of<BookCubit>(
            tester.element(find.byType(BookFilterSentence)),
          )
          ..selectSide(BookSide.buy)
          ..selectCurrencies([
            RobosatsCurrency.all.firstWhere((c) => c.code == 'EUR'),
          ]);
        await settle(tester);
        await tester.tap(choice('Tout mode de paiement'));
        await settle(tester);

        // To buy in euros: orders 1, 2, 5 and 7, so Revolut 2, Instant SEPA 2, Wise 1; Zelle (dollars), Bizum (francs) and order 4 (a buy order) are out.
        expect(listedMethods(tester).take(4), [
          'Instant SEPA',
          'Revolut',
          'Wise',
          'Advcash',
        ]);
        expect(row('Instant SEPA · 2 ordres'), findsOneWidget);
        expect(row('Wise · 1 ordre'), findsOneWidget);
        expect(row('Aucun ordre pour l\'instant'), findsOneWidget);
        expect(optionRow('Zelle'), findsNothing);
        await pickRow(tester, '', step: 300, target: optionRow('Zelle'));
        await closeSheet(tester);
        await tester.tap(choice('Zelle'));
        await settle(tester);
        expect(row('Zelle · aucun ordre'), findsOneWidget);
      },
    );

    testWidgets(
      'the search narrows every group, ignoring case and accents; « Any » hidden meanwhile',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await open(tester);
        await tester.tap(choice('Any payment method'));
        await settle(tester);
        // The field is labelled « Search » for a screen reader, once, before and after a text is typed.
        final textField = find.descendant(
          of: sheet,
          matching: find.byType(TextField),
        );
        expect(tester.getSemantics(textField).label, 'Search');
        // Narrowing the rows does not move the field: the sheet keeps its height.
        final fieldTop = tester.getRect(textField).top;

        await typeSearch(tester, 'RÉV');
        expect(tester.getSemantics(textField).label, 'Search');
        expect(tester.getRect(textField).top, fieldTop);
        expect(listedMethods(tester), ['Revolut']);
        expect(row('Revolut · 3 orders'), findsOneWidget);
        expect(row('Any payment method'), findsNothing);
        // No dimmed method matches: no heading.
        expect(row('No orders right now'), findsNothing);

        // Anywhere in the name, case ignored: the methods of the book and the others, each group in its order.
        await typeSearch(tester, 'pAy');
        final methods = listedMethods(tester);
        expect(methods.first, 'AliPay');
        expect(
          methods,
          everyElement(matches(RegExp('pay', caseSensitive: false))),
        );
        expect(row('No orders right now'), findsOneWidget);

        await typeSearch(tester, 'sepa');
        expect(listedMethods(tester), ['Instant SEPA']);
        await tester.tap(optionRow('Instant SEPA'));
        await settle(tester);
        expect(listed(tester), [1, 5]);

        await typeSearch(tester, 'zzz');
        expect(listedMethods(tester), isEmpty);
        expect(row('No payment method found'), findsOneWidget);
        expect(tester.getRect(textField).top, fieldTop);

        // The button that empties the field brings everything back.
        await tester.tap(find.bySemanticsLabel('Clear'));
        await settle(tester);
        expect(row('Any payment method'), findsOneWidget);
        // The order is the one computed when the sheet opened: Instant SEPA, chosen meanwhile, stays in its place.
        expect(listedMethods(tester).take(2), ['Revolut', 'Instant SEPA']);
        await closeSheet(tester);

        // The text typed is not kept; the choice is.
        expect(choice('Instant SEPA'), findsOneWidget);
        await tester.tap(choice('Instant SEPA'));
        await settle(tester);
        expect(
          tester
              .widget<TextField>(
                find.descendant(of: sheet, matching: find.byType(TextField)),
              )
              .controller
              ?.text,
          isEmpty,
        );
        expect(row('Any payment method'), findsOneWidget);
        semantics.dispose();
      },
    );
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

  testWidgets(
    'shown without the app\'s bottom bar, the last row stays above the system bar',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(bottom: 48 * 3);
      addTearDown(tester.view.reset);
      final options = [for (var i = 1; i <= 30; i++) 'Option $i'];
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => FilterSheet.show<String>(
                    context,
                    title: 'Title',
                    anyLabel: 'Any option',
                    options: options,
                    selected: const [],
                    label: (option) => option,
                    onChanged: (_) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.scrollUntilVisible(
        row('Option 30'),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.drag(
        find.descendant(of: sheet, matching: find.byType(Scrollable)),
        const Offset(0, -2000),
      );
      await settle(tester);

      expect(
        tester.getRect(row('Option 30')).bottom,
        lessThanOrEqualTo(844 - 48),
      );
      expect(row('Option 30').hitTestable(), findsOneWidget);
    },
  );

  for (final (scale, above) in const [
    (1.0, false),
    (2.0, false),
    (3.0, true),
  ]) {
    testWidgets(
      'at ×$scale the close button is ${above ? 'above' : 'beside'} the title',
      (tester) async {
        await open(
          tester,
          locale: const Locale('fr'),
          size: const Size(320, 568),
        );
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await settle(tester);
        await tapShown(tester, choice('Tout hôte'));

        final title = tester.getRect(
          find.descendant(
            of: sheet,
            matching: find.text("Sélectionner l'hôte"),
          ),
        );
        final close = tester.getRect(
          find.descendant(of: sheet, matching: find.byIcon(Icons.close)),
        );
        if (above) {
          expect(close.bottom, lessThanOrEqualTo(title.top));
        } else {
          expect(close.top, lessThan(title.bottom));
          expect(close.bottom, greaterThan(title.top));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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

            // The payment method sheet, its counts and heading, then its search with the keyboard up: the field and a row stay above the keyboard.
            await tapShown(tester, any);
            expect(tester.takeException(), isNull);
            tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 3);
            addTearDown(tester.view.resetViewInsets);
            await settle(tester);
            final fieldBefore = tester
                .getRect(find.descendant(of: sheet, matching: find.byType(TextField)))
                .top;
            await typeSearch(tester, 'e');
            expect(
              tester
                  .getRect(
                    find.descendant(of: sheet, matching: find.byType(TextField)),
                  )
                  .top,
              fieldBefore,
            );
            expect(tester.takeException(), isNull);
            final field = find.descendant(
              of: sheet,
              matching: find.byType(TextField),
            );
            await tester.ensureVisible(field);
            await settle(tester);
            expect(tester.getRect(field).bottom, lessThanOrEqualTo(568 - 260));
            expect(field.hitTestable(), findsOneWidget);
            // The list ends above the keyboard, and once the title has scrolled away its rows show there, under the field.
            final list = find.descendant(
              of: sheet,
              matching: find.byType(CustomScrollView),
            );
            expect(tester.getRect(list).bottom, lessThanOrEqualTo(568 - 260));
            await tester.drag(list, const Offset(0, -600));
            await settle(tester);
            final rows = find.descendant(
              of: sheet,
              matching: find.byWidgetPredicate(
                (widget) => widget.key is ValueKey<String>,
              ),
            );
            expect(rows.hitTestable(), findsWidgets);
            for (final element in rows.hitTestable().evaluate()) {
              expect(
                tester.getRect(find.byWidget(element.widget)).top,
                lessThan(568 - 260),
              );
            }
            expect(field.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
