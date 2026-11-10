import 'package:robosats/robosats.dart';

/// The low-bond warning of the official client's book (`components/BookTable/index.tsx`).
extension BondWarning on BondSize {
  /// The bond the official client calls the default: below it, a bond is low.
  static const double defaultPercent = 3;

  /// Whether the maker set a bond below [defaultPercent], which the book shows in orange with a warning.
  bool get isLow => percent > 0 && percent < defaultPercent;

  /// How strongly to mark a low bond, from 0 (at the default) towards 1 (no bond): the official client makes the text bolder with it.
  double get warningIntensity => isLow ? 1 - percent / defaultPercent : 0;
}
