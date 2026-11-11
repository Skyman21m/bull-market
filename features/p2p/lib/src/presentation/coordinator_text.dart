/// Text that a coordinator chose, shown by the P2P screens: its entry in the federation list (description, motto, policies, contacts) and anything else it wrote.
///
/// The package cleans and bounds what a coordinator sends over the network, but not the federation list it embeds, so the screens apply the same rule to that list before they show it.
/// It is still untrusted: show it as plain text, never as markup, never open it as a link, and never log it.
abstract final class CoordinatorText {
  /// The ellipsis that ends a text cut at its bound.
  static const ellipsis = '…';

  /// The bound of a name, such as the long alias of a coordinator.
  static const name = 64;

  /// The bound of one line, such as a motto, a policy title or a contact.
  static const line = 512;

  /// The bound of a paragraph, such as the description or a policy.
  static const paragraph = 4096;

  /// [text] made safe to show on screen, cut after [maxCodePoints] shown code points with an ellipsis when more would follow.
  ///
  /// As the package does for the free text of a coordinator: C0 and C1 control characters and DEL are removed, except tab, line feed, vertical tab, form feed, carriage return and next line, which become a space like the line and paragraph separators.
  /// Unicode bidirectional controls (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069) and unpaired surrogates are removed.
  /// Everything else, accented letters and emoji included, is kept.
  static String of(String text, {required int maxCodePoints}) {
    final buffer = StringBuffer();
    var kept = 0;
    for (final rune in text.runes) {
      final shown = _shown(rune);
      if (shown == null) continue;
      if (kept == maxCodePoints) {
        buffer.write(ellipsis);
        break;
      }
      buffer.writeCharCode(shown);
      kept++;
    }
    return buffer.toString();
  }

  /// The code point shown for [rune]: a space for a line break or a tab, `null` for a character that is removed.
  static int? _shown(int rune) {
    if ((rune >= 0x09 && rune <= 0x0D) ||
        rune == 0x85 ||
        rune == 0x2028 ||
        rune == 0x2029) {
      return 0x20;
    }
    if (rune < 0x20 ||
        (rune >= 0x7F && rune <= 0x9F) ||
        rune == 0x061C ||
        rune == 0x200E ||
        rune == 0x200F ||
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2066 && rune <= 0x2069) ||
        (rune >= 0xD800 && rune <= 0xDFFF)) {
      return null;
    }
    return rune;
  }
}
