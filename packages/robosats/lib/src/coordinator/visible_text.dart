import 'package:robosats/src/coordinator/json_fields.dart';

/// Whether every character of [text] is seen as it is written, and at least one is seen: what a maker may send as its payment method or description, which every robot that reads the order sees (#181, from the security reviews of #194 and #181).
///
/// [displayText] already refuses the controls, the line breaks, the bidirectional controls and the unpaired surrogates. This refuses besides, exactly:
/// - a text in which no character is seen (only spaces, joiners, variation selectors and combining marks);
/// - any space but U+0020: U+00A0, U+1680, U+2000 to U+200A, U+202F, U+205F, U+3000, and the Braille blank U+2800;
/// - these invisible characters: the soft hyphen U+00AD, the combining grapheme joiner U+034F, the Hangul fillers U+115F, U+1160, U+3164, U+FFA0, the Khmer inherent vowels U+17B4 and U+17B5, the Mongolian free variation selectors and vowel separator U+180B to U+180F, the Khitan filler U+16FE4, and the object replacement character U+FFFC;
/// - the format characters (`Cf`) of Unicode 16: U+0600 to U+0605, U+061C, U+06DD, U+070F, U+0890, U+0891, U+08E2, U+200B, U+200E, U+200F, U+202A to U+202E, U+2060 to U+206F, U+FEFF, U+FFF0 to U+FFFB, U+110BD, U+110CD, U+13430 to U+1345F, U+1BCA0 to U+1BCA3, U+1D173 to U+1D17A, and the tag block U+E0000 to U+E007F (which can carry a hidden text);
/// - the private use areas (U+E000 to U+F8FF, U+F0000 to U+10FFFF), the noncharacters (U+FDD0 to U+FDEF and the last two code points of every plane), and the planes 4 to 13 (U+40000 to U+DFFFF), which Unicode 16 leaves wholly unassigned; other unassigned code points, scattered between assigned ones, are not known without the whole Unicode table, which this package does not carry, and are kept;
/// - a zero width joiner or non-joiner (U+200C, U+200D) that is not alone right after a character seen (or after the variation selector or the combining marks that follow one) and right before a character seen, or, inside a cluster of an Indic script (Devanagari to Sinhala, U+0900 to U+0DFF), right after a letter or a mark of that script and right before its virama ([_virama], as in the Bengali ra-phala « র‍্য »: letter, joiner, virama, letter); and one whose character seen before and character seen after are both letters or digits of Latin, Greek or Cyrillic, scripts in which a joiner joins nothing ([_noJoining]);
/// - a variation selector (U+FE00 to U+FE0F, U+E0100 to U+E01EF) that is not right after a character seen;
/// - a combining mark ([_combining]: the general diacritical blocks and the marks, spacing or not, of the Cyrillic, Hebrew, Arabic, Syriac, Thaana, N'Ko, Indic, Sinhala, Thai, Lao, Tibetan, Myanmar and Khmer blocks and of Japanese kana) at the start, after a space or a joiner, or more than [maxCombiningMarks] after one character seen.
///
/// Letters of every script are kept, right-to-left ones included: their order on screen is the Unicode bidirectional algorithm's, which no control of the text can steer once the controls are refused. Look-alike letters of other scripts and full-width or mathematical letters are kept too: they are seen as they are written.
/// Refused on purpose although legitimate somewhere: the flags of England, Scotland and Wales (sequences of the tag block), Mongolian free variation selectors, and a joiner that ends a word (as in an old encoding of Malayalam chillu letters).
/// Kept although they show nothing, without trying to close everything (second security review of #181, R9): a mark of a script not in [_combining], taken as a character seen, so neither its place nor its number is checked; and a joiner between a Latin letter and a punctuation sign, a symbol or an emoji, which [_noJoining] does not name.
bool isShownAsWritten(String text) {
  if (displayText(text) != text) return false;
  final runes = text.runes.toList(growable: false);
  var seen = false;
  var previous = _Kind.start;
  var combining = 0;
  int? base;
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    final kind = _kindOf(rune);
    switch (kind) {
      case _Kind.refused:
        return false;
      case _Kind.space:
        if (previous == _Kind.joiner) return false;
        base = null;
      case _Kind.joiner:
        // After a character seen, its variation selector or its combining marks (an emoji sequence where U+FE0F comes before the joiner, a virama and a joiner in an Indic script); then a character seen, which the joiner's own case checks ahead, or the virama of the Indic script of the letter or mark right before.
        if (previous != _Kind.seen &&
            previous != _Kind.selector &&
            previous != _Kind.combining) {
          return false;
        }
        final next = i + 1 < runes.length ? runes[i + 1] : null;
        if (next == null) return false;
        if (_kindOf(next) != _Kind.seen) {
          if (!_virama(next) || !_sameIndicBlock(runes[i - 1], next)) {
            return false;
          }
        }
        final before = base;
        if (before != null && _noJoining(before) && _noJoining(next)) {
          return false;
        }
      case _Kind.selector:
        if (previous != _Kind.seen) return false;
      case _Kind.combining:
        // After a joiner, only the virama its own case let through.
        if (previous == _Kind.start || previous == _Kind.space) return false;
        combining++;
        if (combining > maxCombiningMarks) return false;
      case _Kind.seen:
        seen = true;
        base = rune;
      case _Kind.start:
        break;
    }
    if (kind != _Kind.combining && kind != _Kind.selector) combining = 0;
    previous = kind;
  }
  return seen && previous != _Kind.joiner;
}

/// The most combining marks [isShownAsWritten] lets follow one character seen, whatever the script: six. Pointed and cantillated Hebrew needs five on one letter (a shin with its shin dot, its dagesh, its vowel, a meteg and a cantillation mark, second security review of #181, R9), and six leaves one more for a letter that carries a second accent; other real writing needs fewer (a Tibetan stack of subjoined letters and its vowel, an Indic consonant with its nukta, vowel sign and nasal sign, a Vietnamese vowel with two accents written apart). Not the dozens of a text piled up over its neighbours.
const int maxCombiningMarks = 6;

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

/// Whether [rune] is the virama of an Indic script, Devanagari to Sinhala (the Sinhala al-lakuna U+0DCA).
bool _virama(int rune) => const {
  0x094D,
  0x09CD,
  0x0A4D,
  0x0ACD,
  0x0B4D,
  0x0BCD,
  0x0C4D,
  0x0CCD,
  0x0D4D,
  0x0DCA,
}.contains(rune);

/// Whether [rune] and [virama] are of the same Indic block (each is 128 code points, from Devanagari at U+0900 to Sinhala at U+0D80).
bool _sameIndicBlock(int rune, int virama) =>
    rune >= 0x0900 && rune <= 0x0DFF && rune >> 7 == virama >> 7;

/// Whether [rune] is a letter or a digit of Latin, Greek or Cyrillic (with their extensions), in which a zero width joiner or non-joiner changes nothing on screen.
bool _noJoining(int rune) => _inRanges(rune, _noJoiningRanges);

const List<(int, int)> _noJoiningRanges = [
  (0x30, 0x39),
  (0x41, 0x5A),
  (0x61, 0x7A),
  (0xC0, 0xD6),
  (0xD8, 0xF6),
  (0xF8, 0x24F),
  (0x250, 0x2AF),
  (0x370, 0x3FF),
  (0x400, 0x52F),
  (0x1C80, 0x1C8F),
  (0x1D00, 0x1DBF),
  (0x1E00, 0x1FFF),
  (0x2C60, 0x2C7F),
  (0x2DE0, 0x2DFF),
  (0xA640, 0xA69F),
  (0xA720, 0xA7FF),
  (0xAB30, 0xAB6F),
  (0xFF10, 0xFF19),
  (0xFF21, 0xFF3A),
  (0xFF41, 0xFF5A),
];

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
  (0x16FE4, 0x16FE4),
  (0xFFFC, 0xFFFC),
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
  // Private use, and the planes Unicode 16 leaves wholly unassigned.
  (0xE000, 0xF8FF),
  (0xF0000, 0x10FFFF),
  (0x40000, 0xDFFFF),
];

/// The combining marks [isShownAsWritten] counts, as ranges: the general diacritical blocks, and the marks (`Mn`, `Mc`, `Me`) of the scripts most used, after Unicode 16; a mark outside them is taken as a character seen.
const List<(int, int)> _combining = [
  // Combining diacritical marks, their extended and supplement blocks, those for symbols and the half marks.
  (0x0300, 0x036F),
  (0x1AB0, 0x1AFF),
  (0x1DC0, 0x1DFF),
  (0x20D0, 0x20FF),
  (0xFE20, 0xFE2F),
  // Cyrillic.
  (0x0483, 0x0489),
  // Hebrew.
  (0x0591, 0x05BD),
  (0x05BF, 0x05BF),
  (0x05C1, 0x05C2),
  (0x05C4, 0x05C5),
  (0x05C7, 0x05C7),
  // Arabic.
  (0x0610, 0x061A),
  (0x064B, 0x065F),
  (0x0670, 0x0670),
  (0x06D6, 0x06DC),
  (0x06DF, 0x06E4),
  (0x06E7, 0x06E8),
  (0x06EA, 0x06ED),
  (0x08CA, 0x08E1),
  (0x08E3, 0x08FF),
  // Syriac, Thaana, N'Ko.
  (0x0711, 0x0711),
  (0x0730, 0x074A),
  (0x07A6, 0x07B0),
  (0x07EB, 0x07F3),
  // Devanagari to Malayalam, and Sinhala.
  (0x0900, 0x0903),
  (0x093A, 0x093C),
  (0x093E, 0x094F),
  (0x0951, 0x0957),
  (0x0962, 0x0963),
  (0x0981, 0x0983),
  (0x09BC, 0x09BC),
  (0x09BE, 0x09CD),
  (0x09D7, 0x09D7),
  (0x09E2, 0x09E3),
  (0x0A01, 0x0A03),
  (0x0A3C, 0x0A51),
  (0x0A70, 0x0A71),
  (0x0A75, 0x0A75),
  (0x0A81, 0x0A83),
  (0x0ABC, 0x0ABC),
  (0x0ABE, 0x0ACD),
  (0x0AE2, 0x0AE3),
  (0x0B01, 0x0B03),
  (0x0B3C, 0x0B3C),
  (0x0B3E, 0x0B57),
  (0x0B62, 0x0B63),
  (0x0B82, 0x0B82),
  (0x0BBE, 0x0BCD),
  (0x0BD7, 0x0BD7),
  (0x0C00, 0x0C04),
  (0x0C3C, 0x0C3C),
  (0x0C3E, 0x0C56),
  (0x0C62, 0x0C63),
  (0x0C81, 0x0C83),
  (0x0CBC, 0x0CBC),
  (0x0CBE, 0x0CD6),
  (0x0CE2, 0x0CE3),
  (0x0D00, 0x0D03),
  (0x0D3B, 0x0D3C),
  (0x0D3E, 0x0D4D),
  (0x0D57, 0x0D57),
  (0x0D62, 0x0D63),
  (0x0D81, 0x0D83),
  (0x0DCA, 0x0DDF),
  (0x0DF2, 0x0DF3),
  // Thai, Lao, Tibetan, Myanmar, Khmer.
  (0x0E31, 0x0E31),
  (0x0E34, 0x0E3A),
  (0x0E47, 0x0E4E),
  (0x0EB1, 0x0EB1),
  (0x0EB4, 0x0EBC),
  (0x0EC8, 0x0ECE),
  (0x0F18, 0x0F19),
  (0x0F35, 0x0F35),
  (0x0F37, 0x0F37),
  (0x0F39, 0x0F39),
  (0x0F3E, 0x0F3F),
  (0x0F71, 0x0F84),
  (0x0F86, 0x0F87),
  (0x0F8D, 0x0FBC),
  (0x0FC6, 0x0FC6),
  (0x102B, 0x103E),
  (0x1056, 0x1059),
  (0x105E, 0x1060),
  (0x1062, 0x1064),
  (0x1067, 0x106D),
  (0x1071, 0x1074),
  (0x1082, 0x108D),
  (0x108F, 0x108F),
  (0x109A, 0x109D),
  (0x17B6, 0x17D3),
  (0x17DD, 0x17DD),
  // Japanese kana's voiced and semi-voiced marks.
  (0x3099, 0x309A),
];
