import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/presentation/coordinator_text.dart';

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
}
