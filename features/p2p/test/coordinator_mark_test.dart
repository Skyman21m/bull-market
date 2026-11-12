import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/ui/widgets/coordinator_mark.dart';
import 'package:p2p/src/ui/widgets/robot_avatar.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// [temple] with another long alias.
Coordinator renamed(String longAlias) {
  final temple = coordinator('temple');
  return Coordinator(
    shortAlias: temple.shortAlias,
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
        marks.add((initials(tester), frameColor(tester)));
      }

      expect(marks, hasLength(Federation.robosats.coordinators.length));
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
        ('', 'T'),
      ]) {
        await show(tester, renamed(alias));

        expect(initials(tester), expected, reason: alias);
      }
    },
  );

  testWidgets('keeps its size with a large text and stays out of semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        MediaQuery.withClampedTextScaling(
          minScaleFactor: 3,
          maxScaleFactor: 3,
          child: Center(
            child: CoordinatorMark(
              coordinator: coordinator('temple'),
              size: 44,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(CoordinatorMark)), const Size.square(44));
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('TS'), findsNothing);
    semantics.dispose();
  });
}
