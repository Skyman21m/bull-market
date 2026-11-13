import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/map_marks.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/ui/map_chart_view.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

/// An order of the book at [latitude] and [longitude], written as a coordinator writes them, as decimal text.
Map<String, Object?> located(
  int id,
  Object latitude,
  Object longitude, {
  int type = 1,
}) => {
  ...bookOrder(id: id, type: type, makerSeed: id),
  'latitude': '$latitude',
  'longitude': '$longitude',
};

/// The orders of [elements], read by the package's parser.
Future<List<PublicOrder>> orders(List<Map<String, Object?>> elements) =>
    parseOrders(elements);

/// The ids of the orders of each mark of [marks], a pin as one id.
List<List<int>> ids(List<MapMark> marks) => [
  for (final mark in marks)
    switch (mark) {
      MapPin(:final order) => [order.id],
      MapGroup(:final pins) => [for (final pin in pins) pin.order.id],
    },
];

void main() {
  // On the equator, one degree of longitude is 256 × 2^level / 360 points at a level: 0.711 at level 0, 5.69 at level 3, 11.38 at level 4.
  // So two orders 10° apart are 56.9 points apart at level 3, within the 80 points of a group, and 113.8 at level 4, beyond them.
  test(
    'two orders 10° apart: one group up to level 3, two pins from level 4',
    () async {
      final marks = MapMarks.of(
        await orders([located(1, 0, 0), located(2, 0, 10)]),
      );
      expect(marks.pins, hasLength(2));
      for (var level = 0; level <= 3; level++) {
        expect(ids(marks.marksAt(level)), [
          [1, 2],
        ], reason: '$level');
      }
      for (var level = 4; level <= 15; level++) {
        expect(ids(marks.marksAt(level)), [
          [1],
          [2],
        ], reason: '$level');
      }
      // The group is drawn at the mean position of its orders, and its box is theirs.
      final group = marks.marksAt(0).single as MapGroup;
      expect(group.x, closeTo(5 / 360 + 0.5, 1e-12));
      expect(group.y, 0.5);
      expect(group.left, 0.5);
      expect(group.right, closeTo(10 / 360 + 0.5, 1e-12));
      expect((group.top, group.bottom), (0.5, 0.5));
      // Zooming in parts it at level 4; at the deepest level with groups it is two pins, so a tap zooms rather than lists.
      expect(marks.splitLevel(group, 0), 4);
      expect(marks.splitLevel(group, 3), 4);
      expect(marks.staysTogether(group), isFalse);
    },
  );

  test(
    'three orders at 0°, 10° and 20°: a group of two at level 3, of three from level 2',
    () async {
      // Level 3 (reach 14.06°): the first order takes the second, 10° away, not the third, 20° away.
      // Level 2 (reach 28.1°): that group, at 5°, takes the third, 15° from it.
      final marks = MapMarks.of(
        await orders([located(1, 0, 0), located(2, 0, 10), located(3, 0, 20)]),
      );
      expect(ids(marks.marksAt(4)), [
        [1],
        [2],
        [3],
      ]);
      expect(ids(marks.marksAt(3)), [
        [1, 2],
        [3],
      ]);
      for (var level = 0; level <= 2; level++) {
        expect(ids(marks.marksAt(level)), [
          [1, 2, 3],
        ], reason: '$level');
      }
      // The mean of the three orders, 10°, not the middle of the group of two and the third, 12.5°.
      final group = marks.marksAt(2).single as MapGroup;
      expect(group.x, closeTo(10 / 360 + 0.5, 1e-12));
      expect(group.count, 3);
      expect(marks.splitLevel(group, 2), 4);
    },
  );

  test(
    'the order of the orders decides between two groups, as documented',
    () async {
      // The middle one first: at level 3 it takes both others, 10° away each.
      final marks = MapMarks.of(
        await orders([located(2, 0, 10), located(1, 0, 0), located(3, 0, 20)]),
      );
      expect(ids(marks.marksAt(3)), [
        [2, 1, 3],
      ]);
      // On one line of latitude, the pins keep the order given.
      expect(ids(marks.marksAt(4)), [
        [2],
        [1],
        [3],
      ]);
    },
  );

  test(
    'marks are drawn from north to south, a mark further south over one further north',
    () async {
      final marks = MapMarks.of(
        await orders([
          located(1, -40, 0),
          located(2, 50, 100),
          located(3, 10, -100),
        ]),
      );
      expect(ids(marks.marksAt(14)), [
        [2],
        [3],
        [1],
      ]);
      expect(ids(marks.marksAt(5)), [
        [2],
        [3],
        [1],
      ]);
    },
  );

  test('a group of a level is whole at every level above it', () async {
    final random = math.Random(7);
    final marks = MapMarks.of(
      await orders([
        for (var id = 1; id <= 300; id++)
          located(
            id,
            (random.nextDouble() * 120 - 60).toStringAsFixed(4),
            (random.nextDouble() * 360 - 180).toStringAsFixed(4),
            type: id % 2,
          ),
      ]),
    );
    expect(marks.pins, hasLength(300));
    for (var level = 1; level <= 14; level++) {
      // Every order is in exactly one mark of each level.
      final shown = ids(marks.marksAt(level)).expand((ids) => ids).toList();
      expect(shown, hasLength(300), reason: '$level');
      expect(shown.toSet(), hasLength(300), reason: '$level');
      final above = {
        for (final mark in ids(marks.marksAt(level - 1)))
          for (final id in mark) id: mark.first,
      };
      for (final mark in ids(marks.marksAt(level))) {
        expect(
          mark.map((id) => above[id]).toSet(),
          hasLength(1),
          reason: '$level $mark',
        );
      }
    }
    // At each level with groups, two pins drawn by themselves are farther apart than the reach: closer, the first would have taken the second.
    for (var level = 0; level <= MapMarks.lastGroupedLevel; level++) {
      final world = WebMercator.worldSize(level.toDouble());
      final alone = marks.marksAt(level).whereType<MapPin>().toList();
      for (var i = 0; i < alone.length; i++) {
        for (var j = i + 1; j < alone.length; j++) {
          final dx = (alone[i].x - alone[j].x) * world;
          final dy = (alone[i].y - alone[j].y) * world;
          expect(
            math.sqrt(dx * dx + dy * dy),
            greaterThan(MapMarks.radius),
            reason: '$level',
          );
        }
      }
    }
  });

  test(
    'a thousand orders at one point: one group at every level with groups, then a thousand pins',
    () async {
      final marks = MapMarks.of(
        await orders([
          for (var id = 1; id <= 1000; id++) located(id, '48.8566', '2.3522'),
        ]),
      );
      for (var level = 0; level <= MapMarks.lastGroupedLevel; level++) {
        final group = marks.marksAt(level).single as MapGroup;
        expect(group.count, 1000, reason: '$level');
        expect(group.left, group.right);
        // Zooming in cannot part it: a tap lists its orders.
        expect(marks.staysTogether(group), isTrue);
        expect(marks.splitLevel(group, level), MapMarks.lastGroupedLevel + 1);
      }
      expect(marks.marksAt(14), hasLength(1000));
      expect(marks.marksAt(15), hasLength(1000));
    },
  );

  test(
    'two orders 10 metres apart stay together at level 13, where a tap lists them',
    () async {
      final marks = MapMarks.of(
        await orders([
          located(1, '48.85660', '2.35220'),
          located(2, '48.85669', '2.35220'),
        ]),
      );
      final deepest = marks.marksAt(13).single as MapGroup;
      expect(marks.staysTogether(deepest), isTrue);
      expect(marks.staysTogether(marks.marksAt(3).single as MapGroup), isTrue);
      expect(ids(marks.marksAt(14)), [
        [2],
        [1],
      ]);
    },
  );

  test(
    'a group with two orders at one point and a third 0.5° away parts at level 8, but its two stay together',
    () async {
      final marks = MapMarks.of(
        await orders([
          located(1, 0, 0),
          located(2, 0, 0),
          located(3, 0, '0.5'),
        ]),
      );
      // 0.5° is 45.5 points at level 7 and 91 at level 8.
      expect(ids(marks.marksAt(7)), [
        [1, 2, 3],
      ]);
      expect(ids(marks.marksAt(8)), [
        [1, 2],
        [3],
      ]);
      final group = marks.marksAt(7).single as MapGroup;
      expect(marks.staysTogether(group), isFalse);
      // Its orders stay grouped up to level 13, so zooming in on it is useful up to level 14.
      expect(marks.splitLevel(group, 7), 14);
      expect(marks.staysTogether(marks.marksAt(8).first as MapGroup), isTrue);
    },
  );

  test(
    'the poles and the antimeridian: the edges of the map, never wrapped',
    () async {
      final marks = MapMarks.of(
        await orders([
          located(1, 90, 0),
          located(2, -90, 0),
          located(3, 0, 180),
          located(4, 0, -180),
        ]),
      );
      final byId = {for (final pin in marks.pins) pin.order.id: pin};
      expect(byId[1]?.y, closeTo(0, 1e-9));
      expect(byId[2]?.y, closeTo(1, 1e-9));
      expect(byId[3]?.x, 1);
      expect(byId[4]?.x, 0);
      // At level 0 the two ends of the equator are 256 points apart: not grouped across the antimeridian, as Leaflet does not wrap.
      expect(ids(marks.marksAt(0)).where((mark) => mark.length > 1), isEmpty);
    },
  );

  test('orders without a position are left out', () async {
    final marks = MapMarks.of(
      await orders([bookOrder(id: 1), located(2, 1, 1), bookOrder(id: 3)]),
    );
    expect([for (final pin in marks.pins) pin.order.id], [2]);
    expect(MapMarks.of(const []).pins, isEmpty);
    expect(MapMarks.of(const []).marksAt(1), isEmpty);
  });

  test('the level of a zoom is the nearest whole one', () {
    expect(MapMarks.levelOf(0), 0);
    expect(MapMarks.levelOf(1.49), 1);
    expect(MapMarks.levelOf(1.5), 2);
    expect(MapMarks.levelOf(13.4), 13);
    expect(MapMarks.levelOf(13.5), 14);
    expect(MapMarks.levelOf(15), 15);
    expect(MapMarks.levelOf(-3), 0);
    expect(MapMarks.levelOf(40), 15);
  });

  test(
    'six coordinators sending a position with each of their 1,000 orders: grouped once, in a bounded time',
    () async {
      // The package reads at most 1,000 orders of a coordinator's book, and mainnet has six coordinators.
      final random = math.Random(3);
      final parsed = [
        for (final alias in [
          'temple',
          'lake',
          'bazaar',
          'freeport',
          'ammanaya',
          'gumpellite',
        ])
          ...await parseOrders([
            for (var id = 1; id <= 1000; id++)
              located(
                id,
                (random.nextDouble() * 170 - 85).toStringAsFixed(5),
                (random.nextDouble() * 360 - 180).toStringAsFixed(5),
                type: id % 2,
              ),
          ], alias: alias),
      ];
      expect(parsed, hasLength(6000));
      final watch = Stopwatch()..start();
      final marks = MapMarks.of(parsed);
      final built = watch.elapsed;
      watch.reset();
      // A view of the map at the deepest zoom, where every pin is a mark: what each frame of a drag computes.
      final camera = MapCamera.at(zoom: 15, x: 0.5, y: 0.5);
      for (var frame = 0; frame < 60; frame++) {
        MapLayout.of(marks, camera, const Size(390, 600));
      }
      final frames = watch.elapsed;
      expect(marks.pins, hasLength(6000));
      // Generous bounds for a test machine under load; the times measured are in the pull request.
      expect(built, lessThan(const Duration(seconds: 10)), reason: '$built');
      expect(frames, lessThan(const Duration(seconds: 10)), reason: '$frames');
    },
  );
}
