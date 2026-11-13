import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/garage/closes_with_panel.dart';

/// What `ClosesWithPanel` removes once the panel that opened its route is gone, and what the opener of that route gets back: its own route only, as a dismissal (second security pass on #77).
void main() {
  testWidgets(
    'a dialog under another one: only it goes, as a dismissal, and the one above stays',
    (tester) async {
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final until = Completer<void>();
      Object? result = 'pending';
      unawaited(
        showDialog<bool>(
          context: page,
          builder: (_) =>
              ClosesWithPanel(until: until.future, child: const Text('mine')),
        ).then((value) => result = value),
      );
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(context: page, builder: (_) => const Text('above')),
      );
      await tester.pumpAndSettle();

      until.complete();
      await tester.pumpAndSettle();

      expect(find.text('mine'), findsNothing);
      expect(find.text('above'), findsOneWidget);
      expect(result, isNull);
    },
  );

  testWidgets(
    'a sheet on a nested navigator under a dialog of the root one: only the sheet goes, as a dismissal',
    (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) {
                inner = context;
                return const Scaffold(body: Text('page'));
              },
            ),
          ),
        ),
      );
      final until = Completer<void>();
      Object? result = 'pending';
      late BuildContext sheet;
      unawaited(
        showModalBottomSheet<String>(
          context: inner,
          builder: (_) => ClosesWithPanel(
            until: until.future,
            child: Builder(
              builder: (context) {
                sheet = context;
                return const Text('sheet');
              },
            ),
          ),
        ).then((value) => result = value),
      );
      await tester.pumpAndSettle();
      unawaited(
        showDialog<void>(
          context: sheet,
          builder: (_) => const Text('root dialog'),
        ),
      );
      await tester.pumpAndSettle();

      until.complete();
      await tester.pumpAndSettle();

      expect(find.text('sheet'), findsNothing);
      expect(find.text('root dialog'), findsOneWidget);
      expect(find.text('page'), findsOneWidget);
      expect(result, isNull);
    },
  );

  testWidgets('a panel already gone when the route is built: it goes at once', (
    tester,
  ) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const Text('page');
          },
        ),
      ),
    );
    Object? result = 'pending';
    unawaited(
      showDialog<bool>(
        context: page,
        builder: (_) => ClosesWithPanel(
          until: Future<void>.value(),
          child: const Text('mine'),
        ),
      ).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    expect(find.text('mine'), findsNothing);
    expect(find.text('page'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets(
    'the panel removed from the tree in a frame: no error, and the dialog goes',
    (tester) async {
      final shown = ValueNotifier<bool>(true);
      addTearDown(shown.dispose);
      final until = Completer<void>();
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, value, _) {
              page = context;
              return value ? _Panel(until) : const Text('other');
            },
          ),
        ),
      );
      Object? result = 'pending';
      unawaited(
        showDialog<bool>(
          context: page,
          builder: (_) =>
              ClosesWithPanel(until: until.future, child: const Text('mine')),
        ).then((value) => result = value),
      );
      await tester.pumpAndSettle();

      shown.value = false;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('mine'), findsNothing);
      expect(find.text('other'), findsOneWidget);
      expect(result, isNull);
    },
  );

  testWidgets('the whole app gone before the panel: no error', (tester) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final until = Completer<void>();
    unawaited(
      showDialog<bool>(
        context: page,
        builder: (_) =>
            ClosesWithPanel(until: until.future, child: const Text('mine')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());

    until.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

/// A panel that completes [gone] when it leaves the tree, as the robot panel does.
class _Panel extends StatefulWidget {
  final Completer<void> gone;

  const _Panel(this.gone);

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  @override
  void dispose() {
    widget.gone.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('panel');
}
