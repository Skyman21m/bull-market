import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/meeting_point.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:robosats/robosats.dart';

/// The meeting point of a face-to-face order (#189): the reference's randomization and rounding (`F2fMap.tsx` `onSave`, `MakerForm.tsx:494-513`, commit ff1998c), with a source of draws the test gives, at its bounds; the face-to-face methods; the place a tap reaches on the map.
void main() {
  /// Draws that give [values] in turn.
  double Function() draws(List<double> values) {
    var i = 0;
    return () => values[i++];
  }

  group('randomized as the reference', () {
    test('each axis moved by a draw × 0.1 − 0.05, the latitude first', () {
      final point =
          MeetingPoint.randomized(48.8566, 2.3522, draws([0.75, 0.25])) ??
          fail('point');
      // 48.8566 + 0.075 − 0.05 and 2.3522 + 0.025 − 0.05, to 6 significant digits.
      expect(point.latitude, 48.8816);
      expect(point.longitude, 2.3272);
    });

    test('a draw of 0.5 leaves the place, 0 and almost 1 are its bounds', () {
      expect(
        MeetingPoint.randomized(48.8566, 2.3522, draws([0.5, 0.5])),
        OrderLocation.tryCreate(48.8566, 2.3522),
      );
      final low = MeetingPoint.randomized(10, 20, draws([0, 0])) ?? fail('low');
      expect(low.latitude, 9.95);
      expect(low.longitude, 19.95);
      const almostOne = 0.9999999999999999;
      final high =
          MeetingPoint.randomized(10, 20, draws([almostOne, almostOne])) ??
          fail('high');
      expect(high.latitude, 10.05);
      expect(high.longitude, 20.05);
      // Never farther than 0.05° from the place, whatever the draw, but for the rounding to 6 significant digits (half a unit of the last digit kept: 0.0005 at 151°).
      for (final draw in [0.0, 0.1, 0.33, 0.5, 0.66, 0.9, almostOne]) {
        final point =
            MeetingPoint.randomized(-33.8688, 151.2093, draws([draw, draw])) ??
            fail('$draw');
        expect(
          (point.latitude - -33.8688).abs(),
          lessThanOrEqualTo(0.05 + 0.0005 + 1e-9),
        );
        expect(
          (point.longitude - 151.2093).abs(),
          lessThanOrEqualTo(0.05 + 0.0005 + 1e-9),
        );
      }
    });

    test('the floating point of the reference, in its order', () {
      // `position[0] + Math.random() * 0.1 - 0.05`: (p + r × 0.1) − 0.05.
      const p = 45.123456789;
      const r = 0.123456789;
      final point =
          MeetingPoint.randomized(p, p, draws([r, r])) ?? fail('point');
      expect(
        point.latitude,
        double.parse((p + r * 0.1 - 0.05).toStringAsPrecision(6)),
      );
    });

    test('held within ±90° and ±180° before it is kept (a deviation)', () {
      final edge =
          MeetingPoint.randomized(89.99, 179.99, draws([0.9, 0.9])) ??
          fail('edge');
      expect(edge.latitude, 90);
      expect(edge.longitude, 180);
      final other =
          MeetingPoint.randomized(-89.99, -179.99, draws([0.1, 0.1])) ??
          fail('other');
      expect(other.latitude, -90);
      expect(other.longitude, -180);
    });

    test('no place that is not a number', () {
      expect(MeetingPoint.randomized(double.nan, 0, draws([0.5, 0.5])), isNull);
      expect(
        MeetingPoint.randomized(0, double.infinity, draws([0.5, 0.5])),
        isNull,
      );
    });
  });

  group('rounded as the reference', () {
    test('6 significant digits, as `toPrecision(6)`', () {
      expect(MeetingPoint.rounded(48.85661234), 48.8566);
      expect(MeetingPoint.rounded(2.35221234), 2.35221);
      expect(MeetingPoint.rounded(-122.4194155), -122.419);
      expect(MeetingPoint.rounded(179.9999999), 180);
      expect(MeetingPoint.rounded(1.5), 1.5);
      // A tie goes away from zero, as JavaScript's `toPrecision` picks the larger figure.
      expect(MeetingPoint.rounded(10.03125), 10.0313);
      expect(MeetingPoint.rounded(-10.03125), -10.0313);
    });

    test('at most 6 decimals, the coordinator\'s, below 0.1° (a deviation)', () {
      // `toPrecision(6)` gives 0.0512345, which the coordinator refuses with an empty `400`.
      expect(MeetingPoint.rounded(0.0512345), 0.051235);
      expect(MeetingPoint.rounded(-0.00000049), 0);
      expect(MeetingPoint.rounded(-0.00000049).isNegative, isFalse);
      expect(MeetingPoint.rounded(0.0000015), 0.000002);
      for (final value in [0.0512345, 0.0012345678, 0.099999999]) {
        final kept = MeetingPoint.rounded(value);
        final location = OrderLocation.tryCreate(kept, kept);
        expect(
          location == null
              ? null
              : MakeOrderRequest.locationDecimals >= _decimals(kept),
          isTrue,
          reason: '$value',
        );
      }
    });
  });

  group('the face-to-face methods (`MakerForm.tsx:206-232`)', () {
    test('a method is face to face when its name holds « F2F »', () {
      expect(MeetingPoint.isFaceToFace('Cash F2F'), isTrue);
      expect(MeetingPoint.isFaceToFace('Meet F2F in Paris'), isTrue);
      expect(MeetingPoint.isFaceToFace('Cash'), isFalse);
      expect(MeetingPoint.isFaceToFace('f2f'), isFalse);
    });

    test('the map opens when the last method is face to face', () {
      expect(MeetingPoint.opensMap(['Revolut', 'Cash F2F']), isTrue);
      expect(MeetingPoint.opensMap(['Cash F2F', 'Revolut']), isFalse);
      expect(MeetingPoint.opensMap(const []), isFalse);
    });

    test('the point stays only with a face-to-face method', () {
      expect(MeetingPoint.keptWith(['Cash F2F', 'Revolut']), isTrue);
      expect(MeetingPoint.keptWith(['Revolut']), isFalse);
      expect(MeetingPoint.keptWith(const []), isFalse);
    });

    test('a point saved puts « Cash F2F » first, once', () {
      expect(MeetingPoint.methodsWithPoint(['Revolut']), [
        'Cash F2F',
        'Revolut',
      ]);
      expect(MeetingPoint.methodsWithPoint(const []), ['Cash F2F']);
      expect(MeetingPoint.methodsWithPoint(['Revolut', 'Cash F2F']), [
        'Revolut',
        'Cash F2F',
      ]);
    });
  });

  group('the place a tap reaches (`WebMercator.unproject`)', () {
    test('the inverse of the projection', () {
      for (final (lat, lon) in [
        (0.0, 0.0),
        (48.8566, 2.3522),
        (-33.8688, 151.2093),
        (85.0, -179.0),
      ]) {
        final point = WebMercator.project(lat, lon) ?? fail('$lat');
        final place = WebMercator.unproject(point);
        expect(place.latitude, closeTo(lat, 1e-9));
        expect(place.longitude, closeTo(lon, 1e-9));
      }
    });

    test('a tap beside the world gives a place on its edge', () {
      final left = WebMercator.unproject((x: -0.3, y: 1.4));
      expect(left.longitude, -180);
      expect(left.latitude, closeTo(-WebMercator.maxLatitude, 1e-9));
      final right = WebMercator.unproject((x: 1.2, y: -0.5));
      expect(right.longitude, 180);
      expect(right.latitude, closeTo(WebMercator.maxLatitude, 1e-9));
      final nan = WebMercator.unproject((x: double.nan, y: double.nan));
      expect(nan.latitude, closeTo(0, 1e-9));
      expect(nan.longitude, 0);
    });
  });
}

int _decimals(double value) {
  final text = value.toString();
  final point = text.indexOf('.');
  if (text.contains('e')) return 99;
  return point < 0 ? 0 : text.length - point - 1;
}
