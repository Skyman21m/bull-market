import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';

/// The guard of « Pay » (security review of #268, C1 and C2), alone: whatever the structure around the button, a move on the screen that is not a scroll sets it off, and no scroll does; since #288, the page brought back by the layout too (its content under the button that shrinks at its end, its viewport that grows), while a scroll of the user's, an animation's or a jump's never does.
void main() {
  var taps = 0;
  setUp(() => taps = 0);

  Widget button() => MovedTapGuard(
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

    testWidgets(
      'the button appears under the page\'s edge and is brought into view by `ensureVisible` after its first frame (the confirmation that opens): its first tap counts at once',
      (tester) async {
        final shown = ValueNotifier<bool>(false);
        addTearDown(shown.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            SizedBox(
              height: 400,
              child: ListView(
                children: [
                  const SizedBox(height: 380),
                  ValueListenableBuilder<bool>(
                    valueListenable: shown,
                    builder: (_, on, _) => on
                        ? KeyedSubtree(key: key, child: button())
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 600),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        // As the panel of the payment: the reveal asked when the confirmation comes, before the frame that builds it.
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
        await tester.tap(find.text('Pay'));
        expect(taps, 1);
      },
    );
  });
}
