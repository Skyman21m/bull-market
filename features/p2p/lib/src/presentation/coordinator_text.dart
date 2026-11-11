import 'package:robosats/robosats.dart';

/// Text that a coordinator chose, as the P2P screens show it: the names of the coordinators, and everything the coordinator dialog shows, whether it comes from the federation list or from the coordinator's answers.
///
/// It is cleaned by the rule of the package, `displayText`, then cleared of the invisible format characters, then bounded.
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

  /// The zero width non-joiner and joiner, which Persian, the Indic scripts and emoji sequences need in prose.
  static const _joiners = {0x200C, 0x200D};

  /// The invisible format characters: the Unicode category `Cf` (soft hyphen, zero width space, word joiner, byte order mark, interlinear annotations…).
  static final RegExp _format = RegExp(r'\p{Cf}', unicode: true);

  /// Prose, [text] made safe to show and cut after [maxCodePoints] code points with an ellipsis when more would follow.
  ///
  /// The package rule removes the control characters, the bidirectional controls and the unpaired surrogates, and turns line breaks into spaces.
  /// Every invisible format character is removed too, and the tag characters (U+E0000 to U+E007F), except the joiners that some scripts and emoji need.
  static String of(String text, {required int maxCodePoints}) =>
      _bound(_clean(text, keepJoiners: true), maxCodePoints);

  /// A value the user copies, such as a link, a contact or a fingerprint: as [of], with no format character at all, so that what is copied is what is read.
  static String value(String text, {int maxCodePoints = line}) =>
      _bound(_clean(text, keepJoiners: false), maxCodePoints);

  static String _clean(String text, {required bool keepJoiners}) {
    final shown = StringBuffer();
    for (final rune in displayText(text).runes) {
      if (rune >= 0xE0000 && rune <= 0xE007F) continue;
      if (keepJoiners && _joiners.contains(rune)) {
        shown.writeCharCode(rune);
        continue;
      }
      final character = String.fromCharCode(rune);
      if (_format.hasMatch(character)) continue;
      shown.write(character);
    }
    return shown.toString();
  }

  static String _bound(String text, int maxCodePoints) {
    final runes = text.runes;
    if (runes.length <= maxCodePoints) return text;
    return '${String.fromCharCodes(runes.take(maxCodePoints))}$ellipsis';
  }
}
