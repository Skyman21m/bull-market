import 'package:flutter/widgets.dart';

/// A text that wraps at word boundaries only: when its longest word is wider than the room it has, as at three times the text size on a phone of 320 points, its text scale is lowered just enough for that word to fit, rather than breaking the word letter by letter.
///
/// A word is what lies between breaking spaces (space, tab, line feed): a group joined by a non-breaking space (U+00A0, U+202F: an amount's groups, a word and its guillemets) is one word, measured whole, since the line cannot break inside it.
/// The scale is never lowered under the text's own size (a scale of 1, or the user's when smaller): the shrink only takes back part of an enlargement, so that one long word never makes the whole paragraph smaller than it is for someone who did not enlarge the text; a word still too wide at that size breaks as any text does.
class WordFitText extends StatelessWidget {
  /// The spaces a line may break at: not `\s`, which in Dart holds the non-breaking spaces too.
  static final _breakingSpaces = RegExp(r'[ \t\n]+');

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const WordFitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final merged = DefaultTextStyle.of(context).style.merge(style);
    return LayoutBuilder(
      builder: (context, constraints) {
        var fitted = scaler;
        if (constraints.maxWidth.isFinite) {
          var widest = 0.0;
          for (final word in text.split(_breakingSpaces)) {
            if (word.isEmpty) continue;
            final painter = TextPainter(
              text: TextSpan(text: word, style: merged),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (painter.width > widest) widest = painter.width;
            painter.dispose();
          }
          if (widest > constraints.maxWidth) {
            final size = merged.fontSize ?? 14;
            // A little under the room, for the rounding of glyphs at another scale.
            final ratio = constraints.maxWidth * 0.97 / widest;
            final scale = scaler.scale(size) / size;
            final floor = scale < 1 ? scale : 1.0;
            final shrunk = scale * ratio;
            fitted = TextScaler.linear(shrunk < floor ? floor : shrunk);
          }
        }
        return Text(
          text,
          textAlign: textAlign,
          style: style,
          textScaler: fitted,
        );
      },
    );
  }
}
