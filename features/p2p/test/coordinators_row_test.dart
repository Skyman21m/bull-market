import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/presentation/book_state.dart';
import 'package:p2p/src/ui/widgets/coordinator_avatar.dart';
import 'package:p2p/src/ui/widgets/coordinators_row.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The six coordinators of mainnet, in the order of the federation.
final mainnet = Federation.robosats.on(RobosatsNetwork.mainnet);

/// The empty book of each coordinator of both networks, read through the real client from a `not_found` answer.
final Map<Coordinator, OrderBook> emptyBooks = {};

Future<void> readEmptyBooks() async {
  for (final network in RobosatsNetwork.values) {
    final client = CoordinatorClient(
      FakeTransport(network: network),
      clock: () => testNow,
    );
    for (final coordinator in Federation.robosats.on(network)) {
      switch (await client.fetchBook(coordinator, network)) {
        case Ok(:final value):
          emptyBooks[coordinator] = value;
        case Err(:final failure):
          throw StateError('$failure');
      }
    }
  }
}

/// The empty book of [coordinator].
OrderBook emptyBook(Coordinator coordinator) =>
    emptyBooks[coordinator] ?? (throw StateError('no book read'));

/// A book whose coordinators of mainnet stand as [states] says, by short alias, the others answered.
BookState bookWith(Map<String, CoordinatorRowState> states) => BookState(
  network: RobosatsNetwork.mainnet,
  coordinators: {
    for (final coordinator in mainnet)
      coordinator: switch (states[coordinator.shortAlias] ??
          CoordinatorRowState.answered) {
        CoordinatorRowState.answered => CoordinatorBookLoaded(
          emptyBook(coordinator),
        ),
        CoordinatorRowState.awaited => const CoordinatorBookLoading(),
        CoordinatorRowState.offline => const CoordinatorBookFailed(
          CoordinatorUnreachable(),
        ),
      },
  },
);

/// Three answered, two awaited, one offline.
BookState get waiting => bookWith(const {
  'lake': CoordinatorRowState.awaited,
  'freeport': CoordinatorRowState.awaited,
  'gumpellite': CoordinatorRowState.offline,
});

/// Four answered, two offline, none awaited.
BookState get settled => bookWith(const {
  'bazaar': CoordinatorRowState.offline,
  'gumpellite': CoordinatorRowState.offline,
});

/// All six answered.
BookState get allAnswered => bookWith(const {});

/// What is below the row, to see that it does not move.
const below = Key('below');

/// The row of [state] on a screen of [size] points with [textScale], in [locale], with a box below it; [still] asks for reduced motion, as the harness of the feature does.
Widget row(
  BookState state, {
  Locale locale = const Locale('en'),
  bool still = true,
  Size size = const Size(390, 844),
  double textScale = 1,
  ValueChanged<Coordinator>? onOpen,
  VoidCallback? onRetry,
}) => MaterialApp(
  theme: testTheme,
  locale: locale,
  localizationsDelegates: P2pLocalizations.localizationsDelegates,
  supportedLocales: P2pLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: still,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoordinatorsRow(
            state: state,
            onOpenCoordinator: onOpen ?? (_) {},
            onRetry: onRetry ?? () {},
          ),
          const SizedBox(key: below, height: 10),
        ],
      ),
    ),
  ),
);

/// Gives the test a screen of [size] points.
void useScreen(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Finder place(String alias) => find.byWidgetPredicate(
  (widget) =>
      widget is CoordinatorRowPlace && widget.coordinator.shortAlias == alias,
);

/// A text that is shown, not one of the forms the line keeps the room of.
Finder shown(String text) => find.text(text).hitTestable();

/// The sign at the corner of the image of [alias], by its icon.
Finder sign(String alias, IconData icon) =>
    find.descendant(of: place(alias), matching: find.byIcon(icon));

void main() {
  setUpAll(readEmptyBooks);

  group('each state of an image', () {
    testWidgets('answered: lit, with no sign', (tester) async {
      await tester.pumpWidget(row(waiting));

      final temple = place('temple');
      expect(
        find.descendant(of: temple, matching: find.byType(CoordinatorAvatar)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: temple, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        find.descendant(of: temple, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.descendant(of: temple, matching: find.byType(FadeTransition)),
        findsNothing,
      );
    });

    testWidgets('awaited: dimmed, with a clock', (tester) async {
      await tester.pumpWidget(row(waiting));

      expect(sign('lake', Icons.schedule), findsOneWidget);
      expect(sign('lake', Icons.cloud_off), findsNothing);
      final fade = tester.widget<FadeTransition>(
        find.descendant(
          of: place('lake'),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, CoordinatorsRow.dimmed);
      expect(
        find.descendant(
          of: place('lake'),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
    });

    testWidgets('offline: grey and dimmed, with the offline mark', (
      tester,
    ) async {
      await tester.pumpWidget(row(waiting));

      expect(sign('gumpellite', Icons.cloud_off), findsOneWidget);
      expect(sign('gumpellite', Icons.schedule), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: place('gumpellite'),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        CoordinatorsRow.dimmed,
      );
      expect(
        find.descendant(
          of: place('gumpellite'),
          matching: find.byType(ColorFiltered),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'every coordinator of the book, in the order of the federation',
      (tester) async {
        await tester.pumpWidget(row(waiting));

        expect(
          [
            for (final place in tester.widgetList<CoordinatorRowPlace>(
              find.byType(CoordinatorRowPlace),
            ))
              place.coordinator.shortAlias,
          ],
          [for (final coordinator in mainnet) coordinator.shortAlias],
        );
      },
    );

    testWidgets('nothing before the books are requested', (tester) async {
      await tester.pumpWidget(
        row(const BookState(network: RobosatsNetwork.mainnet)),
      );

      expect(find.byType(CoordinatorRowPlace), findsNothing);
      expect(find.byType(Text), findsNothing);
      expect(tester.getTopLeft(find.byKey(below)).dy, 0);
    });
  });

  group('the line', () {
    testWidgets('while any is awaited: how many answered, and no Retry', (
      tester,
    ) async {
      await tester.pumpWidget(row(waiting));

      expect(shown('3 of 6 coordinators answered'), findsOneWidget);
      expect(shown('Retry'), findsNothing);
    });

    testWidgets('once none is awaited: how many are offline, and Retry', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(row(settled, onRetry: () => retried++));

      expect(shown('2 coordinators offline'), findsOneWidget);
      await tester.tap(shown('Retry'));
      expect(retried, 1);
    });

    testWidgets('one offline: the singular', (tester) async {
      await tester.pumpWidget(
        row(bookWith(const {'bazaar': CoordinatorRowState.offline})),
      );

      expect(shown('1 coordinator offline'), findsOneWidget);
    });

    testWidgets('once all answered: quietly, how many, and no Retry', (
      tester,
    ) async {
      await tester.pumpWidget(row(allAnswered));

      expect(shown('6 of 6 coordinators answered'), findsOneWidget);
      expect(shown('Retry'), findsNothing);
    });

    testWidgets('in French', (tester) async {
      const fr = Locale('fr');
      await tester.pumpWidget(row(waiting, locale: fr));
      expect(shown('3 coordinateurs sur 6 ont répondu'), findsOneWidget);

      await tester.pumpWidget(
        row(
          bookWith({
            for (final coordinator in mainnet)
              coordinator.shortAlias: coordinator.shortAlias == 'temple'
                  ? CoordinatorRowState.answered
                  : CoordinatorRowState.awaited,
          }),
          locale: fr,
        ),
      );
      expect(shown('1 coordinateur sur 6 a répondu'), findsOneWidget);

      await tester.pumpWidget(
        row(
          bookWith({
            for (final coordinator in mainnet)
              coordinator.shortAlias: CoordinatorRowState.awaited,
          }),
          locale: fr,
        ),
      );
      expect(shown('0 coordinateur sur 6 a répondu'), findsOneWidget);

      await tester.pumpWidget(row(settled, locale: fr));
      expect(shown('2 coordinateurs hors ligne'), findsOneWidget);
      expect(shown('Réessayer'), findsOneWidget);

      await tester.pumpWidget(
        row(
          bookWith(const {'bazaar': CoordinatorRowState.offline}),
          locale: fr,
        ),
      );
      expect(shown('1 coordinateur hors ligne'), findsOneWidget);
    });

    testWidgets('on testnet: the two coordinators of the network', (
      tester,
    ) async {
      final testnet = Federation.robosats.on(RobosatsNetwork.testnet);
      await tester.pumpWidget(
        row(
          BookState(
            network: RobosatsNetwork.testnet,
            coordinators: {
              testnet.first: CoordinatorBookLoaded(emptyBook(testnet.first)),
              testnet.last: const CoordinatorBookLoading(),
            },
          ),
        ),
      );

      expect(find.byType(CoordinatorRowPlace), findsNWidgets(2));
      expect(shown('1 of 2 coordinators answered'), findsOneWidget);
    });
  });

  group('it fits', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final textScale in const [1.0, 2.0, 3.0]) {
        testWidgets(
          'six images in one row at 320 points, ${locale.languageCode}, text size $textScale, and nothing moves when the line changes',
          (tester) async {
            const size = Size(320, 568);
            useScreen(tester, size);
            double? belowTop;
            for (final state in [waiting, settled, allAnswered]) {
              await tester.pumpWidget(
                row(state, locale: locale, size: size, textScale: textScale),
              );
              // An overflow would have failed the test already.
              final places = find.byType(CoordinatorRowPlace);
              expect(places, findsNWidgets(6));
              final tops = {
                for (var i = 0; i < 6; i++) tester.getTopLeft(places.at(i)).dy,
              };
              expect(tops, hasLength(1), reason: 'one row');
              expect(
                tester.getTopRight(places.last).dx,
                lessThanOrEqualTo(size.width),
              );
              final top = tester.getTopLeft(find.byKey(below)).dy;
              belowTop ??= top;
              expect(top, belowTop, reason: 'the line keeps its room');
            }
          },
        );
      }
    }

    testWidgets('each image is a target of 48 points at least', (tester) async {
      useScreen(tester, const Size(320, 568));
      await tester.pumpWidget(row(waiting, size: const Size(320, 568)));

      for (final coordinator in mainnet) {
        final size = tester.getSize(place(coordinator.shortAlias));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  group('a tap', () {
    testWidgets('on an image opens its coordinator', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        row(
          waiting,
          onOpen: (coordinator) => opened.add(coordinator.shortAlias),
        ),
      );

      await tester.tap(place('lake'));
      await tester.tap(place('gumpellite'));
      await tester.tap(place('temple'));
      expect(opened, ['lake', 'gumpellite', 'temple']);
    });
  });

  group('motion', () {
    testWidgets(
      'the awaited images pulse on one animation, while any is awaited',
      (tester) async {
        await tester.pumpWidget(row(waiting, still: false));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, isTrue);
        // One controller: the two awaited images share its value.
        final fades = tester.widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(CoordinatorsRow),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fades, hasLength(2));
        expect(identical(fades.first.opacity, fades.last.opacity), isTrue);
        final before = fades.first.opacity.value;
        await tester.pump(const Duration(milliseconds: 300));
        expect(fades.first.opacity.value, isNot(before));

        // None awaited any more: it stops.
        await tester.pumpWidget(row(settled, still: false));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('with reduced motion nothing moves: the clock is the sign', (
      tester,
    ) async {
      await tester.pumpWidget(row(waiting));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isFalse);
      expect(sign('lake', Icons.schedule), findsOneWidget);
      expect(sign('freeport', Icons.schedule), findsOneWidget);
    });

    testWidgets('reduced motion asked while it pulses stops it', (
      tester,
    ) async {
      await tester.pumpWidget(row(waiting, still: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(row(waiting));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('semantics', () {
    for (final (locale, labels) in const [
      (
        Locale('en'),
        [
          'Temple of Sats, answered',
          'TheBigLake, awaited',
          'Gumpellite, offline',
        ],
      ),
      (
        Locale('fr'),
        [
          'Temple of Sats, a répondu',
          'TheBigLake, en attente',
          'Gumpellite, hors ligne',
        ],
      ),
    ]) {
      testWidgets(
        'one node per coordinator, its name and its state, a button, in ${locale.languageCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(row(waiting, locale: locale));

          for (final label in labels) {
            expect(
              tester.getSemantics(find.bySemanticsLabel(label)),
              isSemantics(label: label, isButton: true, hasTapAction: true),
              reason: label,
            );
          }
          // Nothing inside a place says anything of its own: the image and its sign are in its one node.
          expect(
            find.descendant(
              of: find.byType(CoordinatorAvatar),
              matching: find.bySemanticsLabel(RegExp('.')),
            ),
            findsNothing,
          );
          expect(
            tester
                .widgetList<Semantics>(
                  find.descendant(
                    of: find.byType(CoordinatorRowPlace),
                    matching: find.byType(Semantics),
                  ),
                )
                .where((widget) => widget.properties.label != null),
            hasLength(6),
          );
          semantics.dispose();
        },
      );
    }

    testWidgets('a tap through the semantics opens the coordinator', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final opened = <String>[];
      await tester.pumpWidget(
        row(
          waiting,
          onOpen: (coordinator) => opened.add(coordinator.shortAlias),
        ),
      );

      tester.semantics.tap(find.semantics.byLabel('TheBigLake, awaited'));
      expect(opened, ['lake']);
      semantics.dispose();
    });

    testWidgets('no change is announced: no live region', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(row(waiting));

      for (final label in [
        'TheBigLake, awaited',
        '3 of 6 coordinators answered',
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(label: label, isLiveRegion: false),
          reason: label,
        );
      }
      semantics.dispose();
    });
  });
}
