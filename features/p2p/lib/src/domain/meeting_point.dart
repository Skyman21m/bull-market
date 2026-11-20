import 'package:robosats/robosats.dart';

/// The meeting point of a face-to-face order, as the official client makes it from the place the maker pins (#189, design note `docs/design/phase-3-making-an-order.md` § 2.4).
///
/// The reference moves the pinned place by up to 0.05° on each axis before it keeps it (`onSave`, `components/Dialogs/F2fMap.tsx`, commit ff1998c: `position[0] + Math.random() * 0.1 - 0.05`, then the same for the longitude), « To protect your privacy, the exact location you pin will be slightly randomized. », then keeps each figure to 6 significant digits (`handleAddLocation`, `MakerForm.tsx:494-501`: `parseFloat(pos[0].toPrecision(6))`): [randomized] does both, in that order, with [draw] in place of `Math.random`.
///
/// Two additions, each a deviation for the coordinator's sake, never a change of the spread: the point is held within ±90° and ±180° before it is kept, where the reference would send a longitude beyond 180° for a place pinned within 0.05° of the antimeridian; and a figure that 6 significant digits leave with more than 6 decimals (below 0.1° from the equator or the prime meridian) is kept to 6 decimals, the coordinator's `decimal_places` (`api/models/order.py:148-167`), which refuses more with an empty `400` where the reference sends it. Nothing here reads the device's position.
abstract final class MeetingPoint {
  /// The width of the spread on each axis, in degrees (`Math.random() * 0.1`), and its half (`- 0.05`): a draw of 0.5 leaves the place where it was pinned.
  static const double spread = 0.1;
  static const double half = 0.05;

  /// The significant digits each figure keeps (`toPrecision(6)`).
  static const int significantDigits = 6;

  /// The place pinned at [latitude] and [longitude], moved as the reference moves it by two draws of [draw], each from 0 included to 1 excluded (`Math.random()`), the latitude's first, then kept as the reference keeps it ([rounded]): the meeting point the order sends, or `null` for a place that is not a number.
  static OrderLocation? randomized(
    double latitude,
    double longitude,
    double Function() draw,
  ) {
    if (!latitude.isFinite || !longitude.isFinite) return null;
    final movedLatitude = latitude + draw() * spread - half;
    final movedLongitude = longitude + draw() * spread - half;
    return OrderLocation.tryCreate(
      rounded(movedLatitude.clamp(-90.0, 90.0)),
      rounded(movedLongitude.clamp(-180.0, 180.0)),
    );
  }

  /// [value] to [significantDigits] significant digits, as JavaScript's `toPrecision` writes it (a tie away from zero), then at most [MakeOrderRequest.locationDecimals] decimals.
  static double rounded(double value) {
    final significant = double.parse(
      value.toStringAsPrecision(significantDigits),
    );
    final fixed = double.parse(
      significant.toStringAsFixed(MakeOrderRequest.locationDecimals),
    );
    return fixed == 0 ? 0.0 : fixed;
  }

  /// Whether a payment method of the reference's names is face to face: its name holds « F2F » (`paymentArray[i].includes('F2F')`, `MakerForm.tsx:213`), as « Cash F2F ».
  static bool isFaceToFace(String method) => method.contains('F2F');

  /// The reference's face-to-face method, which a meeting point saved puts first among the methods (`handleAddLocation`, `MakerForm.tsx:502-511`, the method whose icon is `cash`, `components/PaymentMethods/MethodList.ts:36`).
  static const String cashMethod = 'Cash F2F';

  /// The methods once a meeting point is saved: [cashMethod] first, as the reference puts it, unless it is chosen already (the reference puts it again, a duplicate its `find(...) !== null` lets through; not here).
  static List<String> methodsWithPoint(List<String> methods) =>
      methods.contains(cashMethod)
      ? List.of(methods)
      : [cashMethod, ...methods];

  /// Whether the map opens by itself after the methods became [methods]: the last of them is face to face (`MakerForm.tsx:213-217`).
  static bool opensMap(List<String> methods) =>
      methods.isNotEmpty && isFaceToFace(methods.last);

  /// Whether a meeting point stays with [methods]: only while one of them is face to face (`latitude: includesCash ? maker.latitude : null`, `MakerForm.tsx:228-229`).
  static bool keptWith(List<String> methods) => methods.any(isFaceToFace);
}

/// The draws that move a meeting point pinned ([MeetingPoint.randomized]), from 0 included to 1 excluded: the system's secure source in the app (`Random.secure`, where the reference uses `Math.random()`: the same spread, from a source nobody can predict), a fixed one in the tests.
final class MeetingPointDraws {
  final double Function() next;

  const MeetingPointDraws(this.next);
}
