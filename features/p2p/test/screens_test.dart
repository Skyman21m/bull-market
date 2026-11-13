import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/ui/book_view.dart';
import 'package:p2p/src/ui/coordinator_details_dialog.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/widgets/coordinator_avatar.dart';
import 'package:p2p/src/ui/widgets/coordinator_mark.dart';
import 'package:p2p/src/ui/widgets/coordinators_row.dart';
import 'package:p2p/src/ui/widgets/no_robot_dialog.dart';
import 'package:p2p/src/ui/widgets/robot_avatar.dart';
import 'package:p2p/src/ui/tor_wait_view.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The recorded `/api/info/` of temple on mainnet, for the fees of the order page.
Map<String, Object?> templeInfo() =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  group('Tor wait', () {
    Future<void> show(
      WidgetTester tester,
      TorWait tor, {
      VoidCallback? onRetry,
    }) => tester.pumpWidget(
      harness(
        TorWaitView(
          tor: tor,
          shuffle: P2pShuffle.unshuffled,
          onRetry: onRetry ?? () {},
        ),
      ),
    );

    /// The bar below the steps.
    BullFadingLinearProgress bar(WidgetTester tester) =>
        tester.widget<BullFadingLinearProgress>(
          find.byType(BullFadingLinearProgress),
        );

    /// Lets a bar that stopped fade out: once it has, nothing on the screen moves any more.
    Future<void> fadeOut(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('initializing: the first step is current', (tester) async {
      await show(tester, TorWait.initializing);

      expect(find.text('Connecting to Tor network'), findsNWidgets(2));
      expect(find.text('Initializing Tor daemon'), findsOneWidget);
      expect(find.text('Connected to Tor network'), findsOneWidget);
      expect(
        find.text('Coordinators are only ever reached through Tor.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
    });

    // Before Tor reports a share of its start, the bar runs as the official Android client's spinner turns, with no share of the work done, even though the tests ask for reduced motion, until Tor is ready or fails.
    for (final tor in [TorWait.initializing, TorWait.connecting]) {
      testWidgets('${tor.name}: the bar runs', (tester) async {
        await show(tester, tor);
        await tester.pump(const Duration(milliseconds: 100));

        expect(bar(tester).trigger, isTrue);
        expect(
          find.descendant(
            of: find.byType(BullFadingLinearProgress),
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNull,
        );
        expect(tester.hasRunningAnimations, isTrue);
      });
    }

    testWidgets('failed: the error and a retry, and nothing runs', (
      tester,
    ) async {
      var retried = 0;
      await show(tester, TorWait.failed, onRetry: () => retried++);

      expect(find.text('Connection error'), findsOneWidget);
      expect(bar(tester).trigger, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('the bar stops when Tor fails, and runs again on retry', (
      tester,
    ) async {
      await show(tester, TorWait.connecting);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await show(tester, TorWait.failed);
      expect(bar(tester).trigger, isFalse);
      await fadeOut(tester);
      expect(tester.hasRunningAnimations, isFalse);

      await show(tester, TorWait.initializing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(bar(tester).trigger, isTrue);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('ready: the bar stops', (tester) async {
      await show(tester, TorWait.connecting);
      await show(tester, TorWait.ready);
      await fadeOut(tester);

      expect(bar(tester).trigger, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('in French', (tester) async {
      await tester.pumpWidget(
        harness(
          TorWaitView(
            tor: TorWait.connecting,
            shuffle: P2pShuffle.unshuffled,
            onRetry: () {},
          ),
          locale: const Locale('fr'),
        ),
      );

      expect(find.text('Connexion au réseau Tor'), findsNWidgets(2));
      expect(find.text('Initialisation du service Tor'), findsOneWidget);
      expect(
        find.text('La connexion aux coordinateurs passe uniquement par Tor.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(bar(tester).trigger, isTrue);
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('book and order', () {
    late GetIt locator;
    late FakeTransport transport;
    late StreamController<P2pTorState> tor;

    setUp(() {
      locator = GetIt.asNewInstance();
      tor = StreamController<P2pTorState>.broadcast();
      transport = FakeTransport(
        books: {
          'temple': [
            bookOrder(id: 48213, makerSeed: 1),
            bookOrder(
              id: 2,
              minAmount: 50,
              maxAmount: 300,
              premium: 3.5,
              paymentMethod: 'Instant SEPA',
              makerSeed: 2,
            ),
          ],
          'lake': [bookOrder(id: 3, type: 0, premium: 4, makerSeed: 3)],
        },
        failures: {'bazaar': const CoordinatorTimedOut()},
        infos: {'temple': templeInfo()},
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

    /// The scrollable list of the order page.
    final details = find
        .descendant(
          of: find.byType(OrderDetailsScreen),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> open(
      WidgetTester tester, {
      RobosatsNetwork network = RobosatsNetwork.mainnet,
      Locale locale = const Locale('en'),
    }) async {
      usePhoneScreen(tester);
      final router = GoRouter(
        initialLocation: P2pFeature.path,
        routes: [const P2pFeature().route(locator, network: (_) => network)],
      );
      await tester.pumpWidget(routerHarness(router, locale: locale));
      await settle(tester);
    }

    /// A text of the screen that is shown, not one of the forms the line of the row keeps the room of.
    Finder shown(String text) => find.text(text).hitTestable();

    /// « Retry » under the row, once it is shown.
    final retry = find.text('Retry').hitTestable();

    /// The place of the image of [alias] in the row above the book.
    Finder rowPlace(String alias) => find.byWidgetPredicate(
      (widget) =>
          widget is CoordinatorRowPlace &&
          widget.coordinator.shortAlias == alias,
    );

    /// How the row draws [alias].
    CoordinatorRowState rowState(WidgetTester tester, String alias) =>
        tester.widget<CoordinatorRowPlace>(rowPlace(alias)).state;

    /// The coordinators of the row, in its order.
    List<String> rowAliases(WidgetTester tester) => [
      for (final place in tester.widgetList<CoordinatorRowPlace>(
        find.byType(CoordinatorRowPlace),
      ))
        place.coordinator.shortAlias,
    ];

    testWidgets('waits for Tor, then lists every offer received', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.connecting);
      await settle(tester);
      expect(find.text('Initializing Tor daemon'), findsOneWidget);
      expect(transport.requested, isEmpty);

      tor.add(P2pTorState.ready);
      await settle(tester);

      expect(find.text('Offers'), findsOneWidget);
      expect(find.text('I want to'), findsOneWidget);
      expect(find.text('Seller'), findsNWidgets(2));
      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('100 EUR', findRichText: true), findsNWidgets(2));
      expect(find.text('50-300 EUR', findRichText: true), findsOneWidget);
      expect(find.textContaining('+3.5%', findRichText: true), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
    });

    testWidgets(
      'a coordinator that gives no answer is awaited while it is asked again, then offline with « Retry », which asks it again',
      (tester) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);

        // Asked again by itself: awaited, not offline yet, the others shown.
        expect(shown('5 of 6 coordinators answered'), findsOneWidget);
        expect(retry, findsNothing);
        expect(find.text('Seller'), findsNWidgets(2));
        expect(rowState(tester, 'bazaar'), CoordinatorRowState.awaited);

        await settleAttempts(tester);
        expect(
          transport.requested.where((request) => request == 'bazaar/api/book/'),
          hasLength(3),
        );
        expect(rowState(tester, 'bazaar'), CoordinatorRowState.offline);
        expect(shown('1 coordinator offline'), findsOneWidget);

        transport
          ..failures.clear()
          ..requested.clear();
        await tester.tap(retry);
        await settle(tester);

        expect(transport.requested, ['bazaar/api/book/']);
        expect(retry, findsNothing);
        expect(shown('6 of 6 coordinators answered'), findsOneWidget);
        expect(rowState(tester, 'bazaar'), CoordinatorRowState.answered);
      },
    );

    testWidgets(
      'the row stays above the offers, whatever the host chosen, and an image opens the dialog of its coordinator',
      (tester) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settleAttempts(tester);
        expect(find.text('Seller'), findsNWidgets(2));
        expect(rowAliases(tester), [
          for (final coordinator in Federation.robosats.on(
            RobosatsNetwork.mainnet,
          ))
            coordinator.shortAlias,
        ]);

        // « hosted by » Temple of Sats: the row still shows every coordinator, the offline one included.
        await tester.tap(find.text('ANY').last);
        await settle(tester);
        await tester.tap(find.text('Temple of Sats').last);
        await settle(tester);
        expect(rowAliases(tester), hasLength(6));
        expect(rowState(tester, 'bazaar'), CoordinatorRowState.offline);

        transport.requested.clear();
        await tester.tap(rowPlace('lake'));
        await settle(tester);
        expect(find.byType(CoordinatorDetailsDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CoordinatorDetailsDialog),
            matching: find.text('TheBigLake'),
          ),
          findsOneWidget,
        );
        // The dialog asks the coordinator for its info, as from an order; the book asks nothing.
        expect(transport.requested, ['lake/api/info/']);
      },
    );

    group('the wait for the book', () {
      /// The bar above the book.
      BullFadingLinearProgress bar(WidgetTester tester) =>
          tester.widget<BullFadingLinearProgress>(
            find.descendant(
              of: find.byType(BookView),
              matching: find.byType(BullFadingLinearProgress),
            ),
          );

      final mainnet = [
        for (final coordinator in Federation.robosats.on(
          RobosatsNetwork.mainnet,
        ))
          coordinator.shortAlias,
      ];

      /// Lets a bar that stopped fade out.
      Future<void> fadeOut(WidgetTester tester) async {
        await tester.pump(const Duration(milliseconds: 1100));
        await tester.pump();
        await tester.pump();
      }

      final skeletonRows = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SkeletonRow',
      );

      /// The scrolling part of the book, below the bar.
      Rect bookViewport(WidgetTester tester) => tester.getRect(
        find
            .descendant(
              of: find.byType(BookView),
              matching: find.byType(Scrollable),
            )
            .first,
      );

      testWidgets(
        'before the first book: skeleton rows that shimmer, then the offers',
        (tester) async {
          final semantics = tester.ensureSemantics();
          transport.held.addAll(mainnet);
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);

          expect(find.byType(BookSkeleton), findsOneWidget);
          expect(find.byType(BullShimmerLine), findsWidgets);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // The rows go down to the bottom of the book, as the official client's skeleton fills its grid.
          final bottom = [
            for (var row = 0; row < skeletonRows.evaluate().length; row++)
              tester.getRect(skeletonRows.at(row)).bottom,
          ].reduce(math.max);
          expect(bottom, greaterThanOrEqualTo(bookViewport(tester).bottom));
          // The skeleton says nothing: the line under the row says what the book waits for.
          expect(
            find.descendant(
              of: find.byType(BookSkeleton),
              matching: find.bySemanticsLabel(RegExp('.')),
            ),
            findsNothing,
          );
          expect(shown('0 of 6 coordinators answered'), findsOneWidget);
          expect(
            find.bySemanticsLabel('0 of 6 coordinators answered'),
            findsOneWidget,
          );
          // Nothing is shown yet: the skeleton is the wait, without the bar.
          expect(bar(tester).trigger, isFalse);
          expect(tester.hasRunningAnimations, isTrue);

          transport.failures.clear();
          for (final alias in mainnet) {
            transport.release(alias);
          }
          await settle(tester);

          expect(find.byType(BookSkeleton), findsNothing);
          expect(find.text('Seller'), findsNWidgets(2));
          expect(bar(tester).trigger, isFalse);
          await fadeOut(tester);
          expect(tester.hasRunningAnimations, isFalse);
          semantics.dispose();
        },
      );

      testWidgets(
        'offers shown while a coordinator is still awaited: a bar runs over them, in the chart too, until it answers, and the book does not move',
        (tester) async {
          transport
            ..failures.clear()
            ..held.add('lake');
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);

          expect(find.text('Seller'), findsNWidgets(2));
          expect(find.text('Buyer'), findsNothing);
          expect(find.byType(BookSkeleton), findsNothing);
          expect(shown('5 of 6 coordinators answered'), findsOneWidget);
          expect(bar(tester).trigger, isTrue);
          // The bar lies over the top of the book and takes no room: the book starts where the view starts.
          final top = tester.getRect(find.byType(BookView)).top;
          expect(
            tester
                .getRect(
                  find.descendant(
                    of: find.byType(BookView),
                    matching: find.byType(BullFadingLinearProgress),
                  ),
                )
                .top,
            top,
          );
          expect(tester.getRect(find.byType(BookFilterSentence)).top, top);
          final sentence = tester.getRect(find.text('I want to'));

          await tester.tap(find.text('Chart'));
          await settle(tester);
          expect(bar(tester).trigger, isTrue);
          await tester.tap(find.text('List'));
          await settle(tester);

          transport.release('lake');
          await settle(tester);

          expect(find.text('Buyer'), findsOneWidget);
          expect(shown('6 of 6 coordinators answered'), findsOneWidget);
          expect(bar(tester).trigger, isFalse);
          await fadeOut(tester);
          expect(tester.hasRunningAnimations, isFalse);
          // Gone, the bar leaves the book where it was.
          expect(tester.getRect(find.text('I want to')), sentence);
        },
      );

      testWidgets('a drag that starts on the bar scrolls the book', (
        tester,
      ) async {
        transport = FakeTransport(
          books: {
            'temple': [
              for (var id = 1; id <= 30; id++) bookOrder(id: id, makerSeed: id),
            ],
          },
          held: {'lake'},
        );
        await locator.reset();
        setUpP2pForTesting(
          locator,
          transport: transport,
          torStates: () => tor.stream,
          clock: () => testNow,
        );
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        expect(bar(tester).trigger, isTrue);

        final onBar = tester.getRect(
          find.descendant(
            of: find.byType(BookView),
            matching: find.byType(BullFadingLinearProgress),
          ),
        );
        final list = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(BookView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(list.position.pixels, 0);
        await tester.dragFrom(
          Offset(onBar.center.dx, onBar.top + 1),
          const Offset(0, -200),
        );
        await settle(tester);

        expect(list.position.pixels, greaterThan(100));
      });

      testWidgets(
        'when the first answer is an empty book, the line says what still loads and the skeleton says nothing',
        (tester) async {
          final semantics = tester.ensureSemantics();
          // Gumpellite answers an empty book; the others are held.
          transport.held.addAll(
            mainnet.where((alias) => alias != 'gumpellite'),
          );
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);

          expect(find.byType(BookSkeleton), findsOneWidget);
          expect(shown('1 of 6 coordinators answered'), findsOneWidget);
          expect(rowState(tester, 'gumpellite'), CoordinatorRowState.answered);
          expect(rowState(tester, 'temple'), CoordinatorRowState.awaited);
          expect(
            find.descendant(
              of: find.byType(BookSkeleton),
              matching: find.bySemanticsLabel(RegExp('.')),
            ),
            findsNothing,
          );
          semantics.dispose();
        },
      );

      testWidgets(
        'in the chart, before the first order, the spinner is the wait, without the bar',
        (tester) async {
          transport.held.addAll(mainnet);
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);

          await tester.tap(find.text('Chart'));
          await settle(tester);

          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(bar(tester).trigger, isFalse);
        },
      );

      // Each shimmer runs an animation and a mask layer of its own: one per row at most, on a phone as on a tablet.
      for (final (name, size) in const [
        ('phone', Size(390, 844)),
        ('tablet', Size(1024, 1366)),
      ]) {
        testWidgets('the skeleton shimmers once per row on a $name', (
          tester,
        ) async {
          transport.held.addAll(mainnet);
          await open(tester);
          tester.view
            ..physicalSize = size * 3
            ..devicePixelRatio = 3;
          tor.add(P2pTorState.ready);
          await settle(tester);

          final rows = skeletonRows.evaluate().length;
          expect(rows, greaterThan(1));
          expect(
            rows,
            lessThanOrEqualTo(
              (bookViewport(tester).height / BookSkeleton.rowExtent).ceil(),
            ),
          );
          expect(find.byType(BullShimmerLine), findsNWidgets(rows));
        });
      }

      testWidgets(
        'a pull to refresh keeps the offers and runs the bar until every coordinator answered again',
        (tester) async {
          transport.failures.clear();
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);
          await fadeOut(tester);
          expect(bar(tester).trigger, isFalse);

          transport.held.addAll({'temple', 'lake'});
          unawaited(
            tester
                .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
                .show(),
          );
          await settle(tester);

          expect(find.text('Seller'), findsNWidgets(2));
          expect(find.text('Buyer'), findsOneWidget);
          expect(bar(tester).trigger, isTrue);

          transport
            ..release('temple')
            ..release('lake');
          await settle(tester);
          await fadeOut(tester);
          expect(bar(tester).trigger, isFalse);
        },
      );

      testWidgets(
        'a coordinator still silent 75 seconds after the load began is shown offline, a late answer lights it, and « Retry » meanwhile sends nothing',
        (tester) async {
          transport
            ..failures.clear()
            ..held.add('lake');
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);
          expect(rowState(tester, 'lake'), CoordinatorRowState.awaited);

          await tester.pump(const Duration(seconds: 74));
          expect(rowState(tester, 'lake'), CoordinatorRowState.awaited);
          await tester.pump(const Duration(seconds: 1));
          await settle(tester);
          expect(rowState(tester, 'lake'), CoordinatorRowState.offline);
          expect(shown('1 coordinator offline'), findsOneWidget);

          await tester.tap(retry);
          await settle(tester);
          expect(
            transport.requested.where((request) => request == 'lake/api/book/'),
            hasLength(1),
          );
          expect(rowState(tester, 'lake'), CoordinatorRowState.awaited);

          transport.release('lake');
          await settle(tester);
          expect(rowState(tester, 'lake'), CoordinatorRowState.answered);
          expect(find.text('Buyer'), findsOneWidget);
          expect(shown('6 of 6 coordinators answered'), findsOneWidget);
        },
      );

      testWidgets('a retry runs the bar until the coordinator answers', (
        tester,
      ) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        // While the offline coordinator is asked again by itself, the bar runs too.
        expect(bar(tester).trigger, isTrue);
        await settleAttempts(tester);
        expect(bar(tester).trigger, isFalse);

        transport.failures.clear();
        transport.held.add('bazaar');
        await tester.tap(retry);
        await settle(tester);
        expect(bar(tester).trigger, isTrue);
        expect(rowState(tester, 'bazaar'), CoordinatorRowState.awaited);

        transport.release('bazaar');
        await settle(tester);
        expect(bar(tester).trigger, isFalse);
        expect(retry, findsNothing);
      });

      testWidgets('the line says what the book waits for in French', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        transport.held.addAll(mainnet);
        await open(tester, locale: const Locale('fr'));
        tor.add(P2pTorState.ready);
        await settle(tester);

        expect(find.byType(BookSkeleton), findsOneWidget);
        expect(shown('0 coordinateur sur 6 a répondu'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Temple of Sats, en attente'),
          findsOneWidget,
        );
        semantics.dispose();
      });
    });

    testWidgets('the filter sentence narrows the book', (tester) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      await tester.tap(find.text('ANY').first);
      await settle(tester);
      await tester.tap(find.text('Sell').last);
      await settle(tester);

      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('Seller'), findsNothing);
    });

    testWidgets('the host filter lists every coordinator of the network', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      await tester.tap(find.text('ANY').last);
      await settle(tester);

      expect(find.text('Select Host'), findsOneWidget);
      final hosts = [
        for (final coordinator in Federation.robosats.on(
          RobosatsNetwork.mainnet,
        ))
          coordinator.longAlias,
      ];
      for (final host in hosts) {
        expect(find.text(host), findsOneWidget, reason: host);
      }

      // Gumpellite answered an empty book: choosing it leaves no offer.
      await tester.tap(find.text('Gumpellite'));
      await settle(tester);
      expect(find.text('Gumpellite'), findsOneWidget);
      expect(find.text('Seller'), findsNothing);
      expect(find.text('Buyer'), findsNothing);
    });

    testWidgets('an offer opens its details, read-only', (tester) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.text('Order'), findsOneWidget);
      expect(find.text('Temple of Sats'), findsOneWidget);
      expect(find.text('Order host'), findsOneWidget);
      expect(find.text('# 48213'), findsOneWidget);
      // The host is drawn with its own image, not as one more robot.
      final host = find.descendant(
        of: find.byType(OrderDetailsScreen),
        matching: find.byType(CoordinatorAvatar),
      );
      expect(host, findsOneWidget);
      expect(
        tester.widget<CoordinatorAvatar>(host).coordinator.shortAlias,
        'temple',
      );
      expect(
        find.descendant(of: host, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(find.byType(CoordinatorMark), findsNothing);
      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('You send via Instant SEPA · Revolut'), findsNothing);
      expect(find.text('You send via Revolut Instant SEPA'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OrderDetailsScreen),
          matching: find.text('100 EUR'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('You receive'), findsOneWidget);
      expect(find.text('Accepted payment methods'), findsOneWidget);
      expect(find.text('Price and Premium'), findsOneWidget);
      expect(find.text('93,330 EUR/BTC - Premium: 2.0%'), findsOneWidget);
      expect(find.text('Expires in'), findsOneWidget);
      expect(find.text('17h 00m 00s'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('3h'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(BullButton),
        200,
        scrollable: details,
      );
      expect(find.text('Order maker · Active'), findsOneWidget);
      // The maker is the only robot of the page.
      expect(
        find.descendant(
          of: find.byType(OrderDetailsScreen),
          matching: find.byType(RobotAvatar),
        ),
        findsOneWidget,
      );
      final take = tester.widget<BullButton>(find.byType(BullButton));
      expect(take.label, 'Take Order');
      expect(take.disabled, isTrue);
    });

    testWidgets('the host opens the dialog of its coordinator', (tester) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      await tester.tap(find.text('Order host'));
      await settle(tester);

      expect(find.byType(CoordinatorDetailsDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CoordinatorDetailsDialog),
          matching: find.text('Temple of Sats'),
        ),
        findsOneWidget,
      );
      expect(find.text('Coordinator hosted web app'), findsOneWidget);
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(CoordinatorDetailsDialog),
            matching: find.byType(CoordinatorAvatar),
          ),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CoordinatorDetailsDialog),
          matching: find.byType(RobotAvatar),
        ),
        findsNothing,
      );
      // The page had read the fees: the dialog shows them without asking again.
      expect(transport.requested.where((request) => request.contains('info')), [
        'temple/api/info/',
      ]);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final (locale, host) in [
      (const Locale('en'), 'Order host'),
      (const Locale('fr'), "Hôte de l'ordre"),
    ]) {
      testWidgets(
        'the image of the host is out of the semantics tree and its name is announced, in ${locale.languageCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await open(tester, locale: locale);
          tor.add(P2pTorState.ready);
          await settle(tester);
          await tester.tap(find.text('100 EUR', findRichText: true).first);
          await settle(tester);

          Finder unlabelled() => find.descendant(
            of: find.byType(CoordinatorAvatar),
            matching: find.bySemanticsLabel(RegExp('.')),
          );
          expect(
            find.descendant(
              of: find.byType(OrderDetailsScreen),
              matching: find.byType(CoordinatorAvatar),
            ),
            findsOneWidget,
          );
          // No avatar of a coordinator, the host's or a badge of the book below, says anything.
          expect(unlabelled(), findsNothing);
          expect(find.bySemanticsLabel(RegExp('Temple of Sats')), findsWidgets);

          await tester.tap(find.text(host));
          await settle(tester);
          expect(find.byType(CoordinatorDetailsDialog), findsOneWidget);
          expect(unlabelled(), findsNothing);
          expect(
            find.descendant(
              of: find.byType(CoordinatorDetailsDialog),
              matching: find.bySemanticsLabel(RegExp('Temple of Sats')),
            ),
            findsWidgets,
          );
          semantics.dispose();
        },
      );
    }

    testWidgets('the dialog of a host that did not answer asks it again', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      // Temple gave its book, then does not answer the order page.
      transport.failures['temple'] = const CoordinatorUnreachable();
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);
      transport.failures.remove('temple');

      await tester.tap(find.text('Order host'));
      await settle(tester);

      expect(transport.requested.where((request) => request.contains('info')), [
        'temple/api/info/',
        'temple/api/info/',
      ]);
      expect(find.text('Coordinator offline'), findsNothing);
    });

    group('« Search »', () {
      final dialog = find.byType(SearchOrderDialog);
      Finder inDialog(Finder finder) =>
          find.descendant(of: dialog, matching: finder);
      final temple = hostOf('temple', RobosatsNetwork.mainnet);

      Future<void> searchFor(WidgetTester tester, String url) async {
        await tester.enterText(inDialog(find.byType(TextField)), url);
        await tester.tap(inDialog(find.text('Search')));
        await settle(tester);
      }

      Future<void> openSearch(
        WidgetTester tester, {
        String label = 'Search',
      }) async {
        await tester.tap(find.text(label));
        await settle(tester);
      }

      testWidgets(
        'opens « Search order », and an order of the book opens its page',
        (tester) async {
          await open(tester);
          tor.add(P2pTorState.ready);
          await settle(tester);
          final requests = transport.requested.length;

          await openSearch(tester);
          expect(find.text('Search order'), findsOneWidget);
          expect(
            find.text(
              "Enter here an order URL to search for it, even if it's password protected",
            ),
            findsOneWidget,
          );
          expect(find.text('Order URL'), findsOneWidget);
          expect(inDialog(find.text('Cancel')), findsOneWidget);

          await searchFor(tester, 'http://$temple/order/temple/48213');

          expect(dialog, findsNothing);
          expect(find.byType(OrderDetailsScreen), findsOneWidget);
          expect(find.text('# 48213'), findsOneWidget);
          // Searching asks no coordinator: the order page reads the fees of its host, as from the book.
          expect(transport.requested.skip(requests), ['temple/api/info/']);
        },
      );

      testWidgets('a text that is not an order URL turns the field red', (
        tester,
      ) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        await openSearch(tester);

        await searchFor(tester, 'temple 48213');

        expect(dialog, findsOneWidget);
        final field = tester.widget<TextField>(
          inDialog(find.byType(TextField)),
        );
        final border = field.decoration?.enabledBorder;
        expect(
          border is OutlineInputBorder ? border.borderSide.color : null,
          testBullTheme.error,
        );

        await tester.tap(inDialog(find.text('Cancel')));
        await settle(tester);
        expect(dialog, findsNothing);
        expect(find.byType(OrderDetailsScreen), findsNothing);
        // The bar is back on the list: « List » is in the colour of the chosen segment, « Search » is not.
        Color? colour(String label) => tester
            .widget<Text>(
              find.descendant(
                of: find.byType(BullSegmented).last,
                matching: find.text(label),
              ),
            )
            .style
            ?.color;
        expect(colour('List'), testBullTheme.primary);
        expect(colour('Search'), testBullTheme.secondary);
        // « Search » opens the dialog again.
        await openSearch(tester);
        expect(dialog, findsOneWidget);
      });

      testWidgets('the keyboard neither learns nor rewrites an order URL', (
        tester,
      ) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        await openSearch(tester);

        final field = tester.widget<TextField>(
          inDialog(find.byType(TextField)),
        );
        expect(field.enableIMEPersonalizedLearning, isFalse);
        expect(field.enableSuggestions, isFalse);
        expect(field.autocorrect, isFalse);
        expect(field.smartDashesType, SmartDashesType.disabled);
        expect(field.smartQuotesType, SmartQuotesType.disabled);
        expect(field.keyboardType, TextInputType.url);
        // A paste far longer than an order URL is cut at the bound of the field.
        await tester.enterText(inDialog(find.byType(TextField)), 'x' * 5000);
        await settle(tester);
        expect(
          tester
              .widget<TextField>(inDialog(find.byType(TextField)))
              .controller
              ?.text
              .length,
          SearchOrderDialog.maxLength,
        );
      });

      testWidgets('a swap order opens with its amount in sats', (tester) async {
        // A swap order is never listed by the book, but its URL finds it, as the official client opens it.
        transport.books['temple'] = [
          ...?transport.books['temple'],
          bookOrder(
            id: 77,
            currency: 1000,
            amount: 0.0512,
            paymentMethod: 'On-Chain BTC',
            premium: 1.5,
            price: null,
            makerSeed: 5,
          ),
        ];
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        expect(find.text('# 77'), findsNothing);
        await openSearch(tester);

        await searchFor(tester, 'http://$temple/order/temple/77');

        expect(find.text('# 77'), findsOneWidget);
        // As `btcToSatsString` of the official client: the amount row and the sentence of the taker.
        expect(
          find.descendant(
            of: find.byType(OrderDetailsScreen),
            matching: find.text('5,120,000 Sats'),
          ),
          findsNWidgets(2),
        );
        expect(find.text('You send via On-Chain BTC'), findsOneWidget);
        expect(find.textContaining('0.0512'), findsNothing);
        expect(find.text('Swap destination'), findsOneWidget);
      });

      testWidgets('an order the public book does not hold needs a robot', (
        tester,
      ) async {
        await open(tester);
        tor.add(P2pTorState.ready);
        await settle(tester);
        final requests = transport.requested.length;
        await openSearch(tester);

        await searchFor(tester, 'http://$temple/order/temple/1/');

        expect(dialog, findsNothing);
        expect(find.byType(NoRobotDialog), findsOneWidget);
        expect(find.text('You do not have a Garage Key'), findsOneWidget);
        expect(
          find.text(
            'Generate a Garage Key to get your first robot identity and start trading.',
          ),
          findsOneWidget,
        );
        final buttons = tester.widgetList<BullButton>(
          find.descendant(
            of: find.byType(NoRobotDialog),
            matching: find.byType(BullButton),
          ),
        );
        expect(
          [for (final button in buttons) (button.label, button.disabled)],
          [('I have a Garage Key', true), ('Generate Garage Key', true)],
        );
        expect(transport.requested.length, requests);

        await tester.tapAt(const Offset(4, 4));
        await settle(tester);
        expect(find.byType(NoRobotDialog), findsNothing);
        expect(find.byType(OrderDetailsScreen), findsNothing);
      });

      testWidgets('in French', (tester) async {
        await open(tester, locale: const Locale('fr'));
        tor.add(P2pTorState.ready);
        await settle(tester);
        await openSearch(tester, label: 'Rechercher');

        expect(find.text('Rechercher un ordre'), findsOneWidget);
        expect(
          find.text(
            "Saisissez ici l'URL d'un ordre pour le retrouver, même s'il est protégé par un mot de passe",
          ),
          findsOneWidget,
        );
        expect(find.text("URL de l'ordre"), findsOneWidget);
        expect(inDialog(find.text('Annuler')), findsOneWidget);

        await tester.enterText(
          inDialog(find.byType(TextField)),
          'http://$temple/order/temple/1',
        );
        await tester.tap(inDialog(find.text('Rechercher')));
        await settle(tester);

        expect(find.text("Vous n'avez pas de clé de garage"), findsOneWidget);
        expect(find.text("J'ai une clé de garage"), findsOneWidget);
        expect(find.text('Générer une clé de garage'), findsOneWidget);
      });
    });

    testWidgets('a reversible payment method shows the warning of RoboSats', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      // Order 48213 is paid with Revolut, which the community reports as reversible.
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      await settle(tester);
      expect(find.text('Reversible payments'), findsOneWidget);

      await tester.ensureVisible(find.text('Acknowledged'));
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settle(tester);
      expect(find.text('Reversible payments'), findsNothing);
    });

    testWidgets('a method that cannot be reversed shows no warning', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      // Order 2 is paid with Instant SEPA only.
      await tester.tap(find.text('50-300 EUR', findRichText: true));
      await settle(tester);

      expect(
        find.descendant(
          of: find.byType(OrderDetailsScreen),
          matching: find.text('Instant SEPA'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('the order page in French, with the fees of the host', (
      tester,
    ) async {
      await open(tester, locale: const Locale('fr'));
      tor.add(P2pTorState.ready);
      await settle(tester);
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.text('Ordre'), findsOneWidget);
      expect(
        find.descendant(
          of: find.descendant(
            of: find.byType(OrderDetailsScreen),
            matching: find.byType(CoordinatorAvatar),
          ),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('C 0,025'), findsOneWidget);
      // The on-chain payout fee with one decimal, as the official client writes it.
      expect(find.textContaining('3,4\u00a0%'), findsOneWidget);
      expect(find.text("Hôte de l'ordre"), findsOneWidget);
      expect(find.text("Détails de l'ordre"), findsOneWidget);
      expect(find.text('Montant'), findsOneWidget);
      expect(
        find.text('Vous envoyez via Revolut Instant SEPA'),
        findsOneWidget,
      );
      expect(find.text('Vous recevez'), findsOneWidget);
      expect(find.text('Modes de paiement acceptés'), findsOneWidget);
      expect(find.text('Prix et prime'), findsOneWidget);
      expect(find.text('Expire dans'), findsOneWidget);
      expect(find.text('17 h 00 min 00 s'), findsOneWidget);
      expect(find.text('Dépôt'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text("Prendre l'ordre"),
        200,
        scrollable: details,
      );
      expect(find.textContaining('Créateur de l'), findsWidgets);
      expect(find.text("Prendre l'ordre"), findsOneWidget);
    });

    testWidgets('testnet shows its banner', (tester) async {
      transport = FakeTransport(network: RobosatsNetwork.testnet);
      await locator.reset();
      setUpP2pForTesting(
        locator,
        transport: transport,
        torStates: () => tor.stream,
        clock: () => testNow,
      );
      await open(tester, network: RobosatsNetwork.testnet);

      expect(find.text('Using Testnet Bitcoin'), findsOneWidget);
      tor.add(P2pTorState.ready);
      await settle(tester);
      expect(find.text('No orders found to buy BTC for ANY'), findsOneWidget);
      expect(find.text('Be the first one to create an order'), findsOneWidget);
    });
  });
}
