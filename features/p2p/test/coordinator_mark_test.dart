import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/coordinator_mark.dart';
import 'package:p2p/src/ui/widgets/robot_avatar.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// [temple] with another long alias, and another short alias when given.
Coordinator renamed(String longAlias, {String? shortAlias}) {
  final temple = coordinator('temple');
  return Coordinator(
    shortAlias: shortAlias ?? temple.shortAlias,
    longAlias: longAlias,
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
    federated: temple.federated,
  );
}

void main() {
  Future<void> show(
    WidgetTester tester,
    Coordinator coordinator, {
    double size = 40,
  }) => tester.pumpWidget(
    harness(
      Center(
        child: CoordinatorMark(coordinator: coordinator, size: size),
      ),
    ),
  );

  /// The frame of the mark shown.
  BoxDecoration frame(WidgetTester tester) {
    final decoration = tester
        .widget<Container>(
          find.descendant(
            of: find.byType(CoordinatorMark),
            matching: find.byType(Container),
          ),
        )
        .decoration;
    if (decoration is! BoxDecoration) {
      throw TestFailure('the mark has no box decoration');
    }
    return decoration;
  }

  /// The colour of the frame of the mark shown.
  Color frameColor(WidgetTester tester) => switch (frame(tester).border) {
    Border(:final top) => top.color,
    _ => throw TestFailure('the mark has no frame'),
  };

  /// The letters of the mark shown.
  String initials(WidgetTester tester) =>
      tester
          .widget<Text>(
            find.descendant(
              of: find.byType(CoordinatorMark),
              matching: find.byType(Text),
            ),
          )
          .data ??
      '';

  testWidgets(
    'a coordinator is a framed rounded square with its initials, not a round robot',
    (tester) async {
      await show(tester, coordinator('temple'), size: 96);

      expect(initials(tester), 'TS');
      expect(find.byType(RobotAvatar), findsNothing);
      expect(
        tester.getSize(find.byType(CoordinatorMark)),
        const Size.square(96),
      );
      final decoration = frame(tester);
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.border, isNotNull);
      // A robot is clipped to a circle: the corners of the mark are rounded far less than that.
      final corner = decoration.borderRadius
          ?.resolve(TextDirection.ltr)
          .topLeft;
      expect(corner?.x, lessThan(96 / 3));
    },
  );

  testWidgets(
    'every coordinator of the embedded federation list has a mark of its own',
    (tester) async {
      final marks = <(String, Color)>{};
      for (final coordinator in Federation.robosats.coordinators) {
        await show(tester, coordinator);

        expect(
          initials(tester),
          matches(RegExp(r'^[A-Z0-9]{1,2}$')),
          reason: coordinator.shortAlias,
        );
        // Neither the red of errors and « Seller » nor the grey of what is disabled.
        expect(
          frameColor(tester),
          isNot(anyOf(testBullTheme.primary, testBullTheme.onSurfaceVariant)),
          reason: coordinator.shortAlias,
        );
        marks.add((initials(tester), frameColor(tester)));
      }

      expect(marks, hasLength(Federation.robosats.coordinators.length));
    },
  );

  testWidgets(
    'whatever its short alias, a coordinator is drawn in one of five theme colours, never red or grey',
    (tester) async {
      final used = <Color>{};
      for (final alias in [
        for (final unit in 'abcdefghijklmnopqrstuvwxyz0123456789'.codeUnits)
          String.fromCharCode(unit),
      ]) {
        await show(tester, renamed('Example', shortAlias: alias));
        used.add(frameColor(tester));
      }

      expect(used, {
        testBullTheme.info,
        testBullTheme.success,
        testBullTheme.tertiary,
        testBullTheme.bitcoinOrange,
        testBullTheme.secondary,
      });
    },
  );

  testWidgets('a coordinator has the same mark from one screen to the next', (
    tester,
  ) async {
    await show(tester, coordinator('temple'), size: 44);
    final first = (initials(tester), frameColor(tester));
    await show(tester, coordinator('lake'), size: 96);
    await show(tester, coordinator('temple'), size: 96);

    expect((initials(tester), frameColor(tester)), first);
  });

  testWidgets(
    'only the capitals A to Z of the long alias are taken, else the first letter of the short alias',
    (tester) async {
      for (final (alias, expected) in [
        ('TheBigLake', 'TB'),
        ('Ammanaya', 'A'),
        ('\u202eTemple\u200d of Sats\u0301', 'TS'),
        ('\u00e9lan sans capitale', 'T'),
        // A capital outside A to Z is not taken.
        ('\u00c9lan Sats', 'S'),
        ('', 'T'),
      ]) {
        await show(tester, renamed(alias));

        expect(initials(tester), expected, reason: alias);
      }
    },
  );

  testWidgets(
    'keeps its size and its letters with a large text, and stays out of semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      Future<void> showScaled(double scale) => tester.pumpWidget(
        harness(
          MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: Center(
              child: CoordinatorMark(
                coordinator: coordinator('temple'),
                size: 44,
              ),
            ),
          ),
        ),
      );

      await showScaled(1);
      final letters = tester.getSize(find.text('TS'));
      await showScaled(3);

      expect(
        tester.getSize(find.byType(CoordinatorMark)),
        const Size.square(44),
      );
      // The letters are laid out at the same size, not three times larger and then shrunk to fit.
      expect(tester.getSize(find.text('TS')), letters);
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('TS'), findsNothing);
      semantics.dispose();
    },
  );
}
