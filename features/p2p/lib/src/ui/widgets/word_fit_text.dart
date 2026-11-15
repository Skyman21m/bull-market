import 'package:flutter/widgets.dart';

/// A text that wraps at word boundaries only: when its longest word is wider than the room it has, as at three times the text size on a phone of 320 points, its text scale is lowered just enough for that word to fit, rather than breaking the word letter by letter.
class WordFitText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const WordFitText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
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
          for (final word in text.split(RegExp(r'\s+'))) {
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
            final ratio = constraints.maxWidth / widest;
            fitted = TextScaler.linear(scaler.scale(size) * ratio / size);
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
