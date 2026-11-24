import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';

/// The guard of « Pay » (security review of #268, C1 and C2), alone: whatever the structure around the button, a move on the screen that is not a scroll sets it off, and no scroll does.
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
}
