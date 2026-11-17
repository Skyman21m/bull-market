import 'package:robosats/src/coordinator/json_fields.dart';

/// Whether every character of [text] is seen as it is written, and at least one is seen: what a maker may send as its payment method or description, which every robot that reads the order sees (#181, from the security review of #194).
///
/// [displayText] already refuses the controls, the line breaks, the bidirectional controls and the unpaired surrogates; this refuses besides what another user could not see or would see otherwise than the maker wrote it:
/// - a text with no character but spaces, joiners, variation selectors or combining marks, which shows as empty;
/// - any space but U+0020 (the no-break and the typographic spaces, the ideographic space, the Braille blank), which a reader cannot tell from it or from nothing;
/// - the invisible characters: the soft hyphen, the combining grapheme joiner, the Hangul fillers, the Khmer and Mongolian invisible signs, the zero width space, the word joiner and the invisible operators, the deprecated format characters, the byte order mark, the interlinear annotation characters, the Unicode tag block (which can carry a hidden text), and the other format characters (`Cf`) of Unicode 16;
/// - the private use characters and the noncharacters, which have no agreed glyph;
/// - a zero width joiner or non-joiner anywhere but alone between two characters that are seen, the first of which may carry its variation selector (as in a Persian word written with its zero width non-joiner, or an emoji sequence such as a rainbow flag, U+1F3F3 U+FE0F U+200D U+1F308);
/// - a variation selector anywhere but right after a character that is seen;
/// - a combining mark at the start, after a space or a joiner, or more than [maxCombiningMarks] in a row (a text piled up over its neighbours).
///
/// Letters of every script are kept, right-to-left ones included: their order on screen is the Unicode bidirectional algorithm's, which no control of the text can steer once the controls are refused.
/// Refused on purpose although legitimate somewhere: the flags of England, Scotland and Wales (sequences of the tag block, which can also carry a hidden text), Mongolian free variation selectors (U+180B to U+180F), and a joiner that ends a word (as in an old encoding of Malayalam chillu letters).
bool isShownAsWritten(String text) {
  if (displayText(text) != text) return false;
  var seen = false;
  var previous = _Kind.start;
  var combining = 0;
  for (final rune in text.runes) {
    final kind = _kindOf(rune);
    switch (kind) {
      case _Kind.refused:
        return false;
      case _Kind.space:
        if (previous == _Kind.joiner) return false;
      case _Kind.joiner:
        // After a character seen, or after the variation selector that follows one, as in the emoji sequences where U+FE0F comes before the joiner (a rainbow flag, a heart on fire).
        if (previous != _Kind.seen && previous != _Kind.selector) return false;
      case _Kind.selector:
        if (previous != _Kind.seen) return false;
      case _Kind.combining:
        if (previous == _Kind.start ||
            previous == _Kind.space ||
            previous == _Kind.joiner) {
          return false;
        }
        combining++;
        if (combining > maxCombiningMarks) return false;
      case _Kind.seen:
        seen = true;
      case _Kind.start:
        break;
    }
    if (kind != _Kind.combining && kind != _Kind.selector) combining = 0;
    previous = kind;
  }
  return seen && previous != _Kind.joiner;
}

/// The most combining marks [isShownAsWritten] lets follow one another: enough for a letter with two accents written apart (Vietnamese) or a keycap, not for a text piled up over its neighbours.
const int maxCombiningMarks = 3;

enum _Kind { start, seen, space, joiner, selector, combining, refused }

_Kind _kindOf(int rune) {
  if (rune == 0x20) return _Kind.space;
  if (rune == 0x200C || rune == 0x200D) return _Kind.joiner;
  if ((rune >= 0xFE00 && rune <= 0xFE0F) ||
      (rune >= 0xE0100 && rune <= 0xE01EF)) {
    return _Kind.selector;
  }
  if (_inRanges(rune, _refused)) return _Kind.refused;
  // The noncharacters U+FDD0 to U+FDEF and the last two code points of every plane.
  if ((rune >= 0xFDD0 && rune <= 0xFDEF) || (rune & 0xFFFE) == 0xFFFE) {
    return _Kind.refused;
  }
  if (_inRanges(rune, _combining)) return _Kind.combining;
  return _Kind.seen;
}

bool _inRanges(int rune, List<(int, int)> ranges) {
  for (final (low, high) in ranges) {
    if (rune >= low && rune <= high) return true;
  }
  return false;
}

/// The code points refused wherever they are, as ranges: the spaces but U+0020, the invisible characters, the format characters (`Cf`) and the private use areas.
const List<(int, int)> _refused = [
  // Spaces that are not U+0020.
  (0x00A0, 0x00A0),
  (0x1680, 0x1680),
  (0x2000, 0x200A),
  (0x202F, 0x202F),
  (0x205F, 0x205F),
  (0x3000, 0x3000),
  (0x2800, 0x2800),
  // Invisible letters and signs: the soft hyphen, the combining grapheme joiner, the Hangul fillers, the Khmer inherent vowels, the Mongolian free variation selectors and vowel separator.
  (0x00AD, 0x00AD),
  (0x034F, 0x034F),
  (0x115F, 0x1160),
  (0x17B4, 0x17B5),
  (0x180B, 0x180F),
  (0x3164, 0x3164),
  (0xFFA0, 0xFFA0),
  // Format characters (`Cf`): the Arabic number signs and end of ayah, the Syriac abbreviation mark, the Arabic pound and piastre marks and disputed end of ayah, the zero width space, the left-to-right and right-to-left marks and embeddings (also refused by `displayText`), the word joiner, the invisible operators and the deprecated format characters, the byte order mark, the interlinear annotation characters, the Kaithi number signs, the Egyptian hieroglyph format controls, the shorthand format controls, the musical symbol format controls, and the tag block.
  (0x0600, 0x0605),
  (0x061C, 0x061C),
  (0x06DD, 0x06DD),
  (0x070F, 0x070F),
  (0x0890, 0x0891),
  (0x08E2, 0x08E2),
  (0x200B, 0x200B),
  (0x200E, 0x200F),
  (0x202A, 0x202E),
  (0x2060, 0x206F),
  (0xFEFF, 0xFEFF),
  (0xFFF0, 0xFFFB),
  (0x110BD, 0x110BD),
  (0x110CD, 0x110CD),
  (0x13430, 0x1345F),
  (0x1BCA0, 0x1BCA3),
  (0x1D173, 0x1D17A),
  (0xE0000, 0xE007F),
  // Private use.
  (0xE000, 0xF8FF),
  (0xF0000, 0x10FFFF),
];

/// The combining marks of the general blocks: diacritical marks, their extended and supplement blocks, those for symbols and the half marks.
const List<(int, int)> _combining = [
  (0x0300, 0x036F),
  (0x1AB0, 0x1AFF),
  (0x1DC0, 0x1DFF),
  (0x20D0, 0x20FF),
  (0xFE20, 0xFE2F),
];
