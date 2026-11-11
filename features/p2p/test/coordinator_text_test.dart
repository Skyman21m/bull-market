import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/presentation/coordinator_text.dart';
import 'package:robosats/robosats.dart' show displayText;

void main() {
  String clean(String text, [int max = 100]) =>
      CoordinatorText.of(text, maxCodePoints: max);

  test('keeps letters, accents, emoji and markup as text', () {
    expect(clean('Liberté ⚡🔥'), 'Liberté ⚡🔥');
    expect(
      clean('<b>bold</b> <a href="x">link</a>'),
      '<b>bold</b> <a href="x">link</a>',
    );
    expect(clean(''), '');
  });

  test('line breaks and tabs become spaces', () {
    expect(clean('a\nb\tc\rd\u0085e\u2028f\u2029g'), 'a b c d e f g');
  });

  test('control and bidirectional characters are removed', () {
    expect(clean('a\u0000b\u0007c\u007fd\u009be'), 'abcde');
    expect(clean('\u202Egnp.exe'), 'gnp.exe');
    expect(clean('a\u061Cb\u200Ec\u200Fd\u202Ae\u2066f\u2069g'), 'abcdefg');
    expect(clean('a\uD800b'), 'ab');
  });

  test('a long text is cut at its bound with an ellipsis', () {
    expect(clean('abcdef', 3), 'abc…');
    expect(clean('abc', 3), 'abc');
    // Removed characters do not count, and do not call for an ellipsis.
    expect(clean('abc\u0000\u202E', 3), 'abc');
    expect(clean('a\u202Ebcd', 3), 'abc…');
    // Code points are counted, not UTF-16 units.
    expect(clean('🔥🔥🔥🔥', 2), '🔥🔥…');
    expect(
      clean('x' * 100000, CoordinatorText.paragraph).runes.length,
      CoordinatorText.paragraph + 1,
    );
  });

  test('invisible format characters are removed', () {
    String invisible(List<int> codes) => String.fromCharCodes(codes);
    // Soft hyphen, zero width space, word joiner, byte order mark, interlinear annotations, a tag character.
    for (final code in [
      0x00AD,
      0x200B,
      0x2060,
      0xFEFF,
      0xFFF9,
      0xFFFA,
      0xFFFB,
      0xE0001,
      // A tag code point that is not assigned, outside the category `Cf`.
      0xE0002,
      0xE0041,
      0xE007F,
    ]) {
      expect(
        clean('a${invisible([code])}b'),
        'ab',
        reason: code.toRadixString(16),
      );
      expect(
        CoordinatorText.value('a${invisible([code])}b'),
        'ab',
        reason: code.toRadixString(16),
      );
    }
  });

  test(
    'prose keeps the joiners that scripts and emoji need, a copied value does not',
    () {
      // A family emoji is three emoji joined by U+200D; Persian writes U+200C inside words.
      final family = String.fromCharCodes([
        0x1F468,
        0x200D,
        0x1F469,
        0x200D,
        0x1F467,
      ]);
      final persian = String.fromCharCodes([
        0x0645,
        0x06CC,
        0x200C,
        0x0634,
        0x0648,
        0x062F,
      ]);
      expect(clean(family), family);
      expect(clean(persian), persian);
      expect(
        CoordinatorText.value('temple${String.fromCharCode(0x200D)}ofsats'),
        'templeofsats',
      );
      expect(
        CoordinatorText.value('temple${String.fromCharCode(0x200C)}ofsats'),
        'templeofsats',
      );
    },
  );

  test('a copied value is bounded to one line by default', () {
    expect(
      CoordinatorText.value('x' * 1000).runes.length,
      CoordinatorText.line + 1,
    );
  });

  test('the cleaning is the one of the package', () {
    // `CoordinatorText` adds the format characters and the bound to `displayText`, it does not repeat it.
    final text = 'a\nb\u0000c\u202Ed';
    expect(clean(text), displayText(text));
  });
}
