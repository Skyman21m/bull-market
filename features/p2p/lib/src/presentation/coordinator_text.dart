import 'package:robosats/robosats.dart';

/// Text that a coordinator chose, as the P2P screens show it: the names of the coordinators, and everything the coordinator dialog shows, whether it comes from the federation list or from the coordinator's answers.
///
/// It is cleaned by the rule of the package, `displayText`, then cleared of the default ignorable code points and of the interlinear annotation characters, which are drawn as nothing, then bounded.
/// A value is offered for copy only when, so cleaned, it is printable ASCII, not cut, and without spaces at either end: what is copied is then exactly what is read.
/// It is still untrusted: show it as plain text, never as markup, never open it as a link, and never log it.
abstract final class CoordinatorText {
  /// The ellipsis that ends a text cut at its bound.
  static const ellipsis = '…';

  /// The bound of a name, such as the long alias of a coordinator.
  static const name = 64;

  /// The bound of one line, such as a motto, a policy title, a contact or a version.
  static const line = 512;

  /// The bound of a paragraph, such as the description or a policy.
  static const paragraph = 4096;

  /// The bound of the notice of a coordinator, the one the package reads it with.
  static const notice = 16384;

  /// The longest value offered for copy, the bound `embedded_data_test.dart` of the package sets on the text of the federation list.
  static const copyBound = 1000;

  /// What prose keeps of the default ignorable code points: the zero width non-joiner and joiner, which Persian, the Indic scripts and emoji sequences need, and the variation selectors 15 and 16, which choose the text or emoji form of a symbol.
  static const _keptInProse = {0x200C, 0x200D, 0xFE0E, 0xFE0F};

  /// The code points a text renders as nothing (Unicode `Default_Ignorable_Code_Point`): soft hyphen, zero width space, word joiner, byte order mark, variation selectors, Hangul fillers, tag characters…
  static final RegExp _ignorable = RegExp(
    r'\p{Default_Ignorable_Code_Point}',
    unicode: true,
  );

  /// Prose, [text] made safe to show and cut after [maxCodePoints] code points with an ellipsis when more would follow.
  ///
  /// The package rule removes the control characters, the bidirectional controls and the unpaired surrogates, and turns line breaks into spaces.
  /// Every default ignorable code point is removed too, except the joiners that some scripts and emoji need and the two variation selectors that keep an emoji in its form, and so are the interlinear annotation characters (U+FFF9 to U+FFFB), which Unicode leaves out of that set although they are drawn as nothing.
  static String of(String text, {required int maxCodePoints}) {
    final clean = _clean(text, inProse: true);
    final runes = clean.runes;
    if (runes.length <= maxCodePoints) return clean;
    return '${String.fromCharCodes(runes.take(maxCodePoints))}$ellipsis';
  }

  /// [text] as it may be copied, or `null` when it may not.
  ///
  /// Cleaned as [of] and with no default ignorable code point at all, it must be printable ASCII (U+0020 to U+007E), not empty, at most [copyBound] characters, which is never cut, and neither start nor end with a space, which the reader cannot see.
  /// Anything else, such as a letter of another alphabet that looks like a Latin one, or a value of spaces only, is shown with [of] and not offered for copy.
  static String? copyable(String text) {
    final clean = _clean(text, inProse: false);
    if (clean.isEmpty || clean.length > copyBound) return null;
    if (clean.startsWith(' ') || clean.endsWith(' ')) return null;
    for (final unit in clean.codeUnits) {
      if (unit < 0x20 || unit > 0x7E) return null;
    }
    return clean;
  }

  static String _clean(String text, {required bool inProse}) {
    final shown = StringBuffer();
    for (final rune in displayText(text).runes) {
      if (inProse && _keptInProse.contains(rune)) {
        shown.writeCharCode(rune);
        continue;
      }
      if (rune >= 0xFFF9 && rune <= 0xFFFB) continue;
      final character = String.fromCharCode(rune);
      if (_ignorable.hasMatch(character)) continue;
      shown.write(character);
    }
    return shown.toString();
  }
}
