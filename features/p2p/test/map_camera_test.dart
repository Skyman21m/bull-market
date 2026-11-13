import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/map_marks.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/ui/map_chart_view.dart';

import 'map_marks_test.dart' show located, orders;

void main() {
  const view = Size(300, 400);

  group('the camera', () {
    test(
      'opens as the official client: zoom 1, on latitude 0 and longitude 0',
      () {
        const camera = MapCamera();
        expect((camera.zoom, camera.x, camera.y), (1.0, 0.5, 0.5));
        expect(camera.worldSize, 512);
        // The centre of the map is the centre of the view; the map is 512 points wide.
        expect(camera.toView(0.5, 0.5, view), const Offset(150, 200));
        expect(camera.toView(1, 0.5, view), const Offset(406, 200));
        expect(camera.toMap(const Offset(406, 200), view), (x: 1.0, y: 0.5));
      },
    );

    test('a zoom keeps the point under the fingers where it was', () {
      const camera = MapCamera();
      const anchor = Offset(250, 100);
      final before = camera.toMap(anchor, view);
      final zoomed = camera.zoomedTo(3, anchor: anchor, view: view);
      expect(zoomed.zoom, 3);
      final after = zoomed.toView(before.x, before.y, view);
      expect(after.dx, closeTo(anchor.dx, 1e-9));
      expect(after.dy, closeTo(anchor.dy, 1e-9));
      // A pinch whose fingers move takes the point with them.
      final moved = camera.zoomedTo(
        2,
        anchor: anchor,
        to: const Offset(100, 300),
        view: view,
      );
      final there = moved.toView(before.x, before.y, view);
      expect(there.dx, closeTo(100, 1e-9));
      expect(there.dy, closeTo(300, 1e-9));
    });

    test('the zoom stays within 0 and 15, and the centre on the map', () {
      const camera = MapCamera();
      expect(
        camera.zoomedTo(40, anchor: const Offset(150, 200), view: view).zoom,
        15,
      );
      expect(
        camera.zoomedTo(-4, anchor: const Offset(150, 200), view: view).zoom,
        0,
      );
      expect(
        camera.zoomedTo(double.nan, anchor: Offset.zero, view: view).zoom,
        WebMercator.initialZoom,
      );
      // Dragged far to the left and up, the world stops with its edge at the centre of the view.
      final dragged = camera.zoomedTo(
        1,
        anchor: const Offset(150, 200),
        to: const Offset(-5000, -5000),
        view: view,
      );
      expect((dragged.x, dragged.y), (1.0, 1.0));
      final other = camera.zoomedTo(
        1,
        anchor: const Offset(150, 200),
        to: const Offset(5000, 5000),
        view: view,
      );
      expect((other.x, other.y), (0.0, 0.0));
      expect(
        MapCamera.at(zoom: 2, x: double.nan, y: 2),
        MapCamera.at(zoom: 2, x: 0.5, y: 1),
      );
    });

    test(
      '« + » and « − » go to the next whole level, and stop at the ends',
      () {
        expect(const MapCamera().zoomInTo, 2);
        expect(const MapCamera().zoomOutTo, 0);
        expect(MapCamera.at(zoom: 1.4, x: 0.5, y: 0.5).zoomInTo, 2);
        expect(MapCamera.at(zoom: 1.4, x: 0.5, y: 0.5).zoomOutTo, 1);
        // A zoom a hair off a level counts as that level.
        expect(MapCamera.at(zoom: 2.999, x: 0.5, y: 0.5).zoomInTo, 4);
        expect(MapCamera.at(zoom: 3.001, x: 0.5, y: 0.5).zoomOutTo, 2);
        expect(MapCamera.at(zoom: 14.999, x: 0.5, y: 0.5).zoomInTo, 15);
        expect(MapCamera.at(zoom: 15, x: 0.5, y: 0.5).zoomInTo, isNull);
        expect(MapCamera.at(zoom: 0.005, x: 0.5, y: 0.5).zoomOutTo, 0);
        expect(MapCamera.at(zoom: 0, x: 0.5, y: 0.5).zoomOutTo, isNull);
      },
    );

    test('the zoom that fits a box, as Leaflet\'s getBoundsZoom', () {
      // 10° of longitude is 7.11 points at zoom 0: 300 / 7.11 = 42.2, so 2^5 fits and 2^6 does not.
      expect(MapCamera.fitZoom(10 / 360, 0, view), 5);
      // The height decides when it is the tighter: 0.1 of the map is 25.6 points at zoom 0, 400 / 25.6 = 15.6.
      expect(MapCamera.fitZoom(0.001, 0.1, view), 3);
      // A box of one point fits at every zoom: the nearest.
      expect(MapCamera.fitZoom(0, 0, view), 15);
      // The whole world needs zoom 0, and a larger box no less.
      expect(MapCamera.fitZoom(1, 1, view), 0);
      expect(MapCamera.fitZoom(1, 1, const Size(20, 20)), 0);
      // Exactly 2^4: Leaflet rounds to the hundredth first, so it fits at 4.
      expect(MapCamera.fitZoom(300 / (256 * 16) * 1.000001, 0, view), 4);
    });
  });

  group('a tap on a group, as Leaflet.markercluster\'s zoomToBounds', () {
    test('zooms to where it parts when its orders fit only nearer', () async {
      // Two orders 10° apart part at level 4, and fit in the view up to zoom 5.
      final marks = MapMarks.of(
        await orders([located(1, 0, 0), located(2, 0, 10)]),
      );
      final group = marks.marksAt(1).single as MapGroup;
      final next = const MapCamera().zoomedOnGroup(
        group,
        splitLevel: marks.splitLevel(group, 1),
        view: view,
      );
      expect(next, MapCamera.at(zoom: 4, x: group.x, y: group.y));
    });

    test('fits the box of its orders when they part only beyond it', () async {
      // Two orders at one point and a third 0.5° away: the two stay grouped to level 13, the box fits up to zoom 9.
      final marks = MapMarks.of(
        await orders([
          located(1, 0, 0),
          located(2, 0, 0),
          located(3, 0, '0.5'),
        ]),
      );
      final group = marks.marksAt(7).single as MapGroup;
      final next = MapCamera.at(zoom: 7, x: 0.5, y: 0.5).zoomedOnGroup(
        group,
        splitLevel: marks.splitLevel(group, 7),
        view: view,
      );
      expect(next.zoom, 9);
      expect(next.x, closeTo((group.left + group.right) / 2, 1e-15));
      expect(next.y, 0.5);
    });

    test('zooms one level nearer when its box already fits', () async {
      final marks = MapMarks.of(
        await orders([
          located(1, 0, 0),
          located(2, 0, 0),
          located(3, 0, '0.5'),
        ]),
      );
      final group = marks.marksAt(7).single as MapGroup;
      // At zoom 9.3 the box fits already: one level nearer, centred on the group.
      final next = MapCamera.at(zoom: 9.3, x: 0.5, y: 0.5).zoomedOnGroup(
        group,
        splitLevel: marks.splitLevel(group, 9),
        view: view,
      );
      expect(next, MapCamera.at(zoom: 10, x: group.x, y: group.y));
    });
  });

  group('the layout of a view', () {
    test(
      'draws the marks in view, from north to south, and leaves out the others',
      () async {
        final marks = MapMarks.of(
          await orders([
            located(1, 0, 0),
            located(2, 10, 50),
            located(3, -10, -170),
          ]),
        );
        // At zoom 2 the view of 300 points shows about 105° of longitude around 0°.
        final layout = MapLayout.of(
          marks,
          MapCamera.at(zoom: 2, x: 0.5, y: 0.5),
          view,
        );
        expect(layout.level, 2);
        expect(
          [for (final (mark, _) in layout.drawn) (mark as MapPin).order.id],
          [2, 1],
        );
        expect(layout.drawn.last.$2, const Offset(150, 200));
      },
    );

    test(
      'of pins at one point, draws only the last, past the levels with groups',
      () async {
        final marks = MapMarks.of(
          await orders([
            // A book is read up to 1,000 orders: 999 at one point and one beside.
            for (var id = 1; id <= 999; id++) located(id, '48.8566', '2.3522'),
            located(1000, '48.8566', '2.3530'),
          ]),
        );
        final paris = WebMercator.project(48.8566, 2.3522);
        final at15 = MapLayout.of(
          marks,
          MapCamera.at(zoom: 15, x: paris?.x ?? 0, y: paris?.y ?? 0),
          view,
        );
        // 999 pins at one point and one 0.0008° east, 18 points away at zoom 15.
        expect(at15.drawn, hasLength(2));
        expect((at15.drawn.first.$1 as MapPin).order.id, 999);
        // Left of the point, out of reach of the pin 18 points east: the last of the 999.
        expect(at15.markAt(const Offset(130, 190)), at15.drawn.first.$1);
        // At zoom 13 they are one group of 1,000.
        final at13 = MapLayout.of(
          marks,
          MapCamera.at(zoom: 13, x: paris?.x ?? 0, y: paris?.y ?? 0),
          view,
        );
        expect(at13.drawn, hasLength(1));
        expect(at13.drawn.single.$1.count, 1000);
      },
    );

    test(
      'a tap reaches 48 points around a pin\'s head, or a group\'s disc, the last drawn first',
      () async {
        final marks = MapMarks.of(
          await orders([located(1, 0, 0), located(2, '-0.0001', 0)]),
        );
        final layout = MapLayout.of(
          marks,
          MapCamera.at(zoom: 15, x: 0.5, y: 0.5),
          view,
        );
        // Pin 2 lies a hair south of pin 1, so it is drawn over it, and a tap on both reaches it.
        final (top, at) = layout.drawn.last;
        expect((top as MapPin).order.id, 2);
        final rect = MapLayout.touchRectOf(top, at);
        expect(rect.size, const Size(48, 48));
        expect(rect.center, at.translate(0, -19));
        expect(layout.markAt(at.translate(0, -19)), top);
        expect(layout.pinAt(at.translate(0, -19)), top);
        expect(layout.markAt(at.translate(30, 0)), isNull);
        expect(layout.markAt(at.translate(0, 6)), isNull);
        // A group: around its centre; a long press on it shows no order.
        final grouped = MapLayout.of(marks, const MapCamera(), view);
        final (group, centre) = grouped.drawn.single;
        expect(group, isA<MapGroup>());
        expect(
          MapLayout.touchRectOf(group, centre),
          Rect.fromCenter(center: centre, width: 48, height: 48),
        );
        expect(grouped.markAt(centre.translate(23, 23)), group);
        expect(grouped.pinAt(centre), isNull);
        // For a screen reader, the part of it in the view; nothing for a mark out of it.
        expect(
          MapLayout.semanticsRectOf(group, const Offset(-10, 200), view),
          const Rect.fromLTRB(0, 176, 14, 224),
        );
        expect(
          MapLayout.semanticsRectOf(group, const Offset(-30, 200), view),
          isNull,
        );
      },
    );
  });
}
