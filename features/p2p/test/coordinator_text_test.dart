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

  test('the code points drawn as nothing are removed', () {
    // Soft hyphen, combining grapheme joiner, Hangul fillers, Khmer inherent vowel, Mongolian variation selector, zero width space, word joiner, byte order mark, variation selectors, tag characters (one unassigned).
    for (final code in [
      0x00AD,
      0x034F,
      0x115F,
      0x17B4,
      0x180B,
      0x200B,
      0x2060,
      0x3164,
      0xFE0F,
      0xFEFF,
      0xFFA0,
      // The interlinear annotation characters, which Unicode does not count as default ignorable.
      0xFFF9,
      0xFFFA,
      0xFFFB,
      0xE0001,
      0xE0002,
      0xE0041,
      0xE007F,
      0xE0100,
    ]) {
      final text = 'a${String.fromCharCode(code)}b';
      expect(clean(text), 'ab', reason: code.toRadixString(16));
      expect(
        CoordinatorText.copyable(text),
        'ab',
        reason: code.toRadixString(16),
      );
    }
  });

  test('a visible character of the category Cf is kept', () {
    // The Arabic number sign is drawn: it is not default ignorable.
    final text = String.fromCharCodes([0x0600, 0x0661, 0x0662]);
    expect(clean(text), text);
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
      for (final joiner in [0x200C, 0x200D]) {
        expect(
          CoordinatorText.copyable(
            'temple${String.fromCharCode(joiner)}ofsats',
          ),
          'templeofsats',
        );
      }
    },
  );

  test('a value is offered for copy only as printable ASCII, never cut', () {
    expect(
      CoordinatorText.copyable('https://templeofsats.org'),
      'https://templeofsats.org',
    );
    // The example of the review: a Hangul filler between « site » and « .org » is drawn as nothing, so it is removed before anything is shown or copied.
    expect(
      CoordinatorText.copyable('site${String.fromCharCode(0x3164)}.org'),
      'site.org',
    );
    // What stays visible but is not ASCII is shown and not copied: a Cyrillic letter that looks Latin, a no-break or ideographic space, a braille blank, an emoji.
    for (final code in [0x0456, 0x00A0, 0x3000, 0x2800, 0x1F525]) {
      expect(
        CoordinatorText.copyable('s${String.fromCharCode(code)}te.org'),
        isNull,
        reason: code.toRadixString(16),
      );
    }
    expect(CoordinatorText.copyable(''), isNull);
    expect(CoordinatorText.copyable(String.fromCharCode(0x200B)), isNull);
    // At most the bound of the embedded list, and never cut.
    expect(
      CoordinatorText.copyable('x' * CoordinatorText.copyBound),
      'x' * CoordinatorText.copyBound,
    );
    expect(
      CoordinatorText.copyable('x' * (CoordinatorText.copyBound + 1)),
      isNull,
    );
    // A line break, cleaned into a space, is printable.
    expect(CoordinatorText.copyable('a\nb'), 'a b');
  });

  test('the cleaning is the one of the package', () {
    // `CoordinatorText` adds the format characters and the bound to `displayText`, it does not repeat it.
    final text = 'a\nb\u0000c\u202Ed';
    expect(clean(text), displayText(text));
  });
}
