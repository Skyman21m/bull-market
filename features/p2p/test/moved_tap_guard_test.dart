import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';

/// The guard of « Pay » (security review of #268, C1 and C2), alone: whatever the structure around the button, a move on the screen that is not a scroll sets it off, and no scroll does; since #288, the page brought back by the layout too (its content under the button that shrinks at its end, its viewport that grows), while a scroll of the user's, an animation's or a jump's never does; and a button that appears ignores taps for the delay, a button built again in place does not (security review of #291, B1).
void main() {
  var taps = 0;
  setUp(() => taps = 0);

  Widget button({bool armsWhenShown = true}) => MovedTapGuard(
    armsWhenShown: armsWhenShown,
    builder: (context, guard) =>
        TextButton(onPressed: guard(() => taps++), child: const Text('Pay')),
  );

  Widget app(Widget body) => MaterialApp(home: Scaffold(body: body));

  /// A tap on « Pay » a tenth of a second after the last frame.
  Future<void> tapSoon(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Pay'));
    await tester.pump();
  }

  testWidgets(
    'something above the list, outside it, grows: the button moves on the screen, a tap at once is ignored, one after the delay counts',
    (tester) async {
      final top = ValueNotifier<double>(50);
      addTearDown(top.dispose);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: top,
                builder: (_, height, _) => SizedBox(height: height),
              ),
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 100),
                    button(),
                    const SizedBox(height: 2000),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      // A button that appears ignores taps for the delay (security review of #291, B1): the move comes after it.
      await tester.pump(MovedTapGuard.afterMove);
      top.value = 130;
      await tester.pump();
      await tapSoon(tester);
      expect(taps, 0);
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(find.text('Pay'));
      expect(taps, 1);
    },
  );

  testWidgets(
    'each new move starts the delay again: moved twice 400 ms apart, a tap 500 ms after the second move is ignored, one 750 ms after it counts (security review of #296, C1)',
    (tester) async {
      final top = ValueNotifier<double>(50);
      addTearDown(top.dispose);
      await tester.pumpWidget(
        app(
          Column(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: top,
                builder: (_, height, _) => SizedBox(height: height),
              ),
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 100),
                    button(),
                    const SizedBox(height: 2000),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      top.value = 130;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      top.value = 210;
      await tester.pump();
      // 900 ms after the first move, 500 ms after the second.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Pay'));
      await tester.pump();
      expect(taps, 0);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Pay'));
      expect(taps, 1);
    },
  );

  testWidgets(
    'two nested lists, the inner one scrolled, then the outer one: no move but scrolls, every tap counts at once',
    (tester) async {
      final outer = ScrollController();
      final inner = ScrollController();
      addTearDown(outer.dispose);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        app(
          ListView(
            controller: outer,
            children: [
              const SizedBox(height: 100),
              SizedBox(
                height: 300,
                child: ListView(
                  controller: inner,
                  children: [
                    const SizedBox(height: 80),
                    button(),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      await tapSoon(tester);
      expect(taps, 1);
      inner.jumpTo(40);
      await tester.pump();
      await tapSoon(tester);
      expect(taps, 2);
      outer.jumpTo(60);
      await tester.pump();
      await tapSoon(tester);
      expect(taps, 3);
    },
  );

  testWidgets(
    'the content above the inner list grows in the outer list: the button moves on the screen, a tap at once is ignored',
    (tester) async {
      final top = ValueNotifier<double>(100);
      addTearDown(top.dispose);
      await tester.pumpWidget(
        app(
          ListView(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: top,
                builder: (_, height, _) => SizedBox(height: height),
              ),
              SizedBox(
                height: 300,
                child: ListView(
                  children: [
                    const SizedBox(height: 80),
                    button(),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      top.value = 170;
      await tester.pump();
      await tapSoon(tester);
      expect(taps, 0);
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(find.text('Pay'));
      expect(taps, 1);
    },
  );

  group('#288: the page brought back by the layout', () {
    /// A list of [viewport] points high whose content is 300 points, the button, then [below] points: scrolled to its end.
    Future<(ScrollController, ValueNotifier<double>, ValueNotifier<double>)>
    atEnd(WidgetTester tester, {double below = 200}) async {
      final controller = ScrollController();
      final under = ValueNotifier<double>(below);
      final viewport = ValueNotifier<double>(400);
      addTearDown(controller.dispose);
      addTearDown(under.dispose);
      addTearDown(viewport.dispose);
      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<double>(
              valueListenable: viewport,
              builder: (_, height, child) =>
                  SizedBox(height: height, child: child),
              child: ListView(
                controller: controller,
                children: [
                  const SizedBox(height: 300),
                  button(),
                  ValueListenableBuilder<double>(
                    valueListenable: under,
                    builder: (_, height, _) => SizedBox(height: height),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      return (controller, under, viewport);
    }

    testWidgets(
      'content under the button shrinks (« Hide details » under « Pay »): the page goes back to its new end without a scroll, the button moves down on the screen and not in the content: a tap at once is ignored, one after the delay counts',
      (tester) async {
        final (controller, under, _) = await atEnd(tester);
        final before = tester.getTopLeft(find.text('Pay'));
        under.value = 60;
        await tester.pump();
        expect(controller.position.isScrollingNotifier.value, isFalse);
        expect(tester.getTopLeft(find.text('Pay')).dy, before.dy + 140);
        await tapSoon(tester);
        expect(taps, 0);
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );

    testWidgets(
      'a line under the button that goes at a read, the page at its end: the one tap aimed at that line, where the button now is, is ignored',
      (tester) async {
        final (_, under, _) = await atEnd(tester, below: 260);
        final aimed = tester.getCenter(find.text('Pay')) + const Offset(0, 60);
        under.value = 200;
        await tester.pump();
        expect(tester.getCenter(find.text('Pay')).dy, closeTo(aimed.dy, 1));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(aimed);
        await tester.pump();
        expect(taps, 0);
      },
    );

    testWidgets(
      'the viewport grows, the page at its end (a system bar or the keyboard that goes, a rotation): ignored for the delay; it shrinks (the keyboard that comes): no move, every tap counts at once',
      (tester) async {
        final (controller, _, viewport) = await atEnd(tester);
        viewport.value = 300;
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        viewport.value = 400;
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1);
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 2);
      },
    );

    testWidgets(
      'the user drags the page, flings it, or it is animated or jumped: no move but scrolls, every tap counts at once, the last frame of a fling or an animation included',
      (tester) async {
        final (controller, _, _) = await atEnd(tester);
        await tester.drag(find.byType(ListView), const Offset(0, 80));
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1);
        await tester.fling(find.byType(ListView), const Offset(0, 40), 800);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pay'));
        expect(taps, 2);
        unawaited(
          controller.animateTo(
            40,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
        await tester.pumpAndSettle();
        await tapSoon(tester);
        expect(taps, 3);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 4);
      },
    );

    testWidgets(
      'a jump from a callback after the frame, the button already there, as `ensureVisible`: no move but a scroll, the tap counts at once',
      (tester) async {
        final (controller, _, _) = await atEnd(tester);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.jumpTo(100),
        );
        await tester.pump();
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1);
      },
    );

    /// A list 400 points high whose button appears under its edge when [shown] is set, below [above] points, and is brought into view by `ensureVisible` from a callback after the frame that builds it, as the panel of the payment brings « Pay » into view when the confirmation opens.
    Future<void> appearsBroughtIntoView(
      WidgetTester tester,
      ValueNotifier<bool> shown,
      ValueNotifier<double> above, {
      bool armsWhenShown = true,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          SizedBox(
            height: 400,
            child: ListView(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: above,
                  builder: (_, height, _) => SizedBox(height: height),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: shown,
                  builder: (_, on, _) => on
                      ? KeyedSubtree(
                          key: key,
                          child: button(armsWhenShown: armsWhenShown),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 600),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      // The reveal asked when the confirmation comes, before the frame that builds it: it runs before the guard's first measure, which is skipped.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (target != null) unawaited(Scrollable.ensureVisible(target));
      });
      shown.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(find.text('Pay')).dy,
        lessThan(400),
        reason: 'brought into view',
      );
    }

    testWidgets(
      'the button appears under the page\'s edge and is brought into view by `ensureVisible` after its first frame (the confirmation that opens, « Pay » where « Pay with this wallet » was): a tap within the delay is ignored, the first after it counts (security review of #291, B1)',
      (tester) async {
        final shown = ValueNotifier<bool>(false);
        final above = ValueNotifier<double>(380);
        addTearDown(shown.dispose);
        addTearDown(above.dispose);
        await appearsBroughtIntoView(tester, shown, above);
        for (final ms in const [100, 300, 200]) {
          await tester.pump(Duration(milliseconds: ms));
          await tester.tap(find.text('Pay'));
          expect(taps, 0, reason: 'within the delay');
        }
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );

    testWidgets(
      'a measure skipped (the jump after the first frame), then, the delay past, a move of the layout above the button: the guard measures again, the tap at once is ignored, the one after the delay counts (both reviews of #291, C1)',
      (tester) async {
        final shown = ValueNotifier<bool>(false);
        final above = ValueNotifier<double>(380);
        addTearDown(shown.dispose);
        addTearDown(above.dispose);
        await appearsBroughtIntoView(tester, shown, above);
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
        above.value = 420;
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1, reason: 'moved by the layout');
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 2);
      },
    );

    testWidgets(
      'a button that appears, no scroll: taps within the delay are ignored, the first after it counts; built again in place (its parent built anew, nothing moved), it starts no delay',
      (tester) async {
        final shown = ValueNotifier<bool>(false);
        final rebuilt = ValueNotifier<int>(0);
        addTearDown(shown.dispose);
        addTearDown(rebuilt.dispose);
        await tester.pumpWidget(
          app(
            ListView(
              children: [
                const SizedBox(height: 100),
                ValueListenableBuilder<int>(
                  valueListenable: rebuilt,
                  builder: (_, count, _) => ValueListenableBuilder<bool>(
                    valueListenable: shown,
                    builder: (_, on, _) => on
                        ? Padding(padding: EdgeInsets.zero, child: button())
                        : const SizedBox(height: 48),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        shown.value = true;
        await tester.pump();
        await tapSoon(tester);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Pay'));
        expect(taps, 0, reason: 'appeared 0.5 s ago');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
        for (var i = 1; i <= 3; i++) {
          rebuilt.value = i;
          await tester.pump();
          await tapSoon(tester);
          expect(taps, 1 + i, reason: 'built again in place');
        }
      },
    );

    testWidgets(
      'a button that starts no delay when shown (« Continue »), brought into view by `ensureVisible` after its first frame: that first measure, made after the jump and before the screen shows it, is skipped, never mixing the place before the jump with the offset after it; no move, the tap counts at once',
      (tester) async {
        final shown = ValueNotifier<bool>(false);
        final above = ValueNotifier<double>(380);
        addTearDown(shown.dispose);
        addTearDown(above.dispose);
        await appearsBroughtIntoView(
          tester,
          shown,
          above,
          armsWhenShown: false,
        );
        await tapSoon(tester);
        expect(taps, 1);
      },
    );
  });

  group('#294: a button shown again from under what covered it', () {
    /// A page whose button, at the middle of the screen, is drawn while [shown]; with [shell] the page is in a navigator nested in the app's root one (as the app's `ShellRoute` places the P2P pages), and the dialogs open on the root one (`showDialog`'s default), so that the page's route stays the current one of its own navigator while a dialog covers it.
    Future<BuildContext> covered(
      WidgetTester tester, {
      required ValueNotifier<bool> shown,
      bool shell = false,
      bool armsWhenShown = true,
    }) async {
      late BuildContext page;
      final body = Builder(
        builder: (context) {
          page = context;
          return ListView(
            children: [
              const SizedBox(height: 200),
              ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (_, on, _) => on
                    ? button(armsWhenShown: armsWhenShown)
                    : const SizedBox(height: 48),
              ),
              const SizedBox(height: 2000),
            ],
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: shell
              ? Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: body),
                  ),
                )
              : Scaffold(body: body),
        ),
      );
      await tester.pump();
      return page;
    }

    /// A dialog opened over [page], centred, its barrier dismissible.
    Future<void> openDialog(WidgetTester tester, BuildContext page) async {
      unawaited(
        showDialog<void>(
          context: page,
          builder: (_) => const Dialog(
            child: SizedBox(width: 100, height: 60, child: Text('dialog')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('dialog'), findsOneWidget);
    }

    /// The dialog closed by a double tap on its barrier at the button's place, the second tap [gap] after the first: whether that second tap counted.
    Future<bool> closeByDoubleTap(
      WidgetTester tester, {
      Duration gap = const Duration(milliseconds: 100),
    }) async {
      final point = tester.getCenter(find.text('Pay', skipOffstage: false));
      final before = taps;
      await tester.tapAt(point);
      await tester.pump();
      await tester.pump(gap);
      await tester.tapAt(point);
      await tester.pump();
      return taps > before;
    }

    for (final shell in const [false, true]) {
      final where = shell
          ? 'the page in a nested navigator, the dialog on the root one (the app\'s composition)'
          : 'the page and the dialog on one navigator';
      testWidgets(
        'built behind a dialog, its delay spent there ($where): the dialog closed by a double tap on its barrier, the second tap on the button 100 ms later is ignored; one after the delay counts',
        (tester) async {
          final shown = ValueNotifier<bool>(false);
          addTearDown(shown.dispose);
          final page = await covered(tester, shown: shown, shell: shell);
          await openDialog(tester, page);
          shown.value = true;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 1600));
          expect(await closeByDoubleTap(tester), isFalse);
          await tester.pump(MovedTapGuard.afterMove);
          expect(find.text('dialog'), findsNothing);
          await tester.tap(find.text('Pay'));
          expect(taps, 1);
        },
      );

      testWidgets(
        'shown, then covered by a dialog that moves nothing ($where): the double tap that closes it is ignored at 100 and 300 ms, a tap 700 ms after the closing counts',
        (tester) async {
          final shown = ValueNotifier<bool>(true);
          addTearDown(shown.dispose);
          final page = await covered(tester, shown: shown, shell: shell);
          await tester.pump(MovedTapGuard.afterMove);
          for (final gap in const [100, 300]) {
            await openDialog(tester, page);
            expect(
              await closeByDoubleTap(tester, gap: Duration(milliseconds: gap)),
              isFalse,
              reason: '$gap ms',
            );
            await tester.pump(MovedTapGuard.afterMove);
          }
          await openDialog(tester, page);
          // Closed by one tap on the barrier under the dialog, away from the button.
          await tester.tapAt(
            tester.getCenter(find.text('dialog')) + const Offset(0, 200),
          );
          await tester.pump();
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tap(find.text('Pay'));
          expect(taps, 1);
        },
      );
    }

    testWidgets(
      'a page pushed over it and left: the page\'s way out moves the button (the transition of the page under it), as on `main`; a tap 300 ms after it ends is ignored, one 700 ms after counts',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        final page = await covered(tester, shown: shown);
        await tester.pump(MovedTapGuard.afterMove);
        unawaited(
          Navigator.of(page).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('above')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Pay'), findsNothing);
        Navigator.of(page).pop();
        await tester.pump();
        var frames = 0;
        while (find.text('above').evaluate().isNotEmpty) {
          expect(frames++, lessThan(60));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Pay'));
        await tester.pump();
        expect(taps, 0);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );

    testWidgets(
      'scrolled out of view and back, by a finger and by a jump: never taken for covered, every tap counts at once',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        await covered(tester, shown: shown);
        await tester.pump(MovedTapGuard.afterMove);
        final position = Scrollable.of(
          tester.element(find.text('Pay')),
        ).position;
        // Out of view, within the list's cache, so that the button is kept (one built again is a button shown, as on `main`).
        position.jumpTo(300);
        await tester.pump();
        expect(find.text('Pay'), findsNothing);
        position.jumpTo(0);
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 1);
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        await tapSoon(tester);
        expect(taps, 2);
      },
    );

    testWidgets(
      'a button that starts no delay when shown (« Continue »): shown again from under a dialog closed by a double tap, the second tap counts, as before',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        final page = await covered(tester, shown: shown, armsWhenShown: false);
        await openDialog(tester, page);
        expect(await closeByDoubleTap(tester), isTrue);
      },
    );

    testWidgets(
      'covered by a dialog, the page scrolled behind it (a measure that cannot tell), then the dialog closed with no frame between: the cover is not forgotten, a tap 100 ms after the closing is ignored, one after the delay counts (security review of #296, R3)',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        final page = await covered(tester, shown: shown);
        await tester.pump(MovedTapGuard.afterMove);
        await openDialog(tester, page);
        final position = Scrollable.of(
          tester.element(find.text('Pay')),
        ).position;
        // A scroll: its frame tries no tap at the button, and says nothing of the cover.
        position.jumpTo(10);
        await tester.pump();
        Navigator.of(tester.element(find.text('dialog'))).pop();
        // The first frame of the closing: the dialog on its way out takes no tap, the button is reached again.
        await tester.pump();
        await tapSoon(tester);
        expect(taps, 0);
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );

    testWidgets(
      'covered by a dialog, then the dialog closed and the page jumped by a callback after that very frame, before the guard\'s measure (as another widget\'s `ensureVisible`): that measure is skipped, and the next one, the jump shown and the dialog on its way out, tries a tap and finds the button reached again: a tap right after that frame is ignored, one after the delay counts (#299)',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        ScrollPosition? jumping;
        var running = true;
        addTearDown(() => running = false);
        // Registered before the guard is built, and again at each frame before the guard's own callback: it runs first after every frame.
        void first(Duration _) {
          if (!running) return;
          final position = jumping;
          if (position != null) {
            jumping = null;
            position.jumpTo(position.pixels + 10);
          }
          WidgetsBinding.instance.addPostFrameCallback(first);
        }

        WidgetsBinding.instance.addPostFrameCallback(first);
        final page = await covered(tester, shown: shown);
        await tester.pump(MovedTapGuard.afterMove);
        await openDialog(tester, page);
        await tester.pump(MovedTapGuard.afterMove);
        final position = Scrollable.of(tester.element(find.text('Pay'))).position;
        final before = position.pixels;
        jumping = position;
        Navigator.of(tester.element(find.text('dialog'))).pop();
        // The first frame of the closing, the jump after it, its measure skipped.
        await tester.pump(const Duration(milliseconds: 16));
        expect(position.pixels, before + 10);
        // The next frame shows the jump; the dialog on its way out takes no tap.
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('dialog'), findsOneWidget);
        await tester.tap(find.text('Pay'));
        await tester.pump();
        expect(taps, 0, reason: 'shown again a frame ago');
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );

    testWidgets(
      'shown, then the page scrolled by an animation (the list ignores taps while it runs, which is no cover): nothing is tried while it runs, so its end starts no delay; a tap 100 ms after it counts (#299)',
      (tester) async {
        final shown = ValueNotifier<bool>(true);
        addTearDown(shown.dispose);
        await covered(tester, shown: shown);
        await tester.pump(MovedTapGuard.afterMove);
        final position = Scrollable.of(tester.element(find.text('Pay'))).position;
        unawaited(
          position.animateTo(
            20,
            duration: const Duration(milliseconds: 300),
            curve: Curves.linear,
          ),
        );
        await tester.pump();
        expect(position.isScrollingNotifier.value, isTrue);
        for (var i = 0; i < 25 && position.isScrollingNotifier.value; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(position.isScrollingNotifier.value, isFalse);
        expect(position.pixels, 20);
        await tapSoon(tester);
        expect(taps, 1);
      },
    );
  });
}
