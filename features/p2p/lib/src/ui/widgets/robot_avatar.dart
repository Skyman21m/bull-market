import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

/// A provisional robot avatar, drawn from a seed such as the hash id of a robot or the alias of a coordinator.
///
/// The same seed always gives the same robot, so a maker is recognisable from one screen to the next.
/// The real RoboSats avatars come with ticket #22; the colours here are those of the theme.
class RobotAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final String? semanticLabel;

  const RobotAvatar({
    super.key,
    required this.seed,
    this.size = 40,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final palette = [
      colors.info,
      colors.success,
      colors.warning,
      colors.tertiary,
      colors.bitcoinOrange,
      colors.primary,
      colors.secondaryFixedDim,
    ];
    final hash = _hash(seed);
    final body = palette[hash % palette.length];
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RobotPainter(
            background: Color.alphaBlend(
              palette[(hash >> 3) % palette.length].withValues(alpha: 0.22),
              colors.surface,
            ),
            body: body,
            features: colors.background,
            antenna: colors.bitcoinOrange,
            eyeOffset: 0.30 + ((hash >> 6) % 10) / 100,
            mouthWidth: 0.04 + ((hash >> 10) % 8) / 100,
          ),
        ),
      ),
    );
  }

  /// A small stable hash of [seed], the same on every run (unlike `String.hashCode`).
  static int _hash(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return hash;
  }
}

class _RobotPainter extends CustomPainter {
  final Color background;
  final Color body;
  final Color features;
  final Color antenna;
  final double eyeOffset;
  final double mouthWidth;

  const _RobotPainter({
    required this.background,
    required this.body,
    required this.features,
    required this.antenna,
    required this.eyeOffset,
    required this.mouthWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    canvas
      ..save()
      ..clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: s / 2)),
      )
      ..drawRect(Offset.zero & size, Paint()..color = background);
    final bodyPaint = Paint()..color = body;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0.24 * s, 0.30 * s, 0.52 * s, 0.46 * s),
          Radius.circular(0.06 * s),
        ),
        bodyPaint,
      )
      ..drawRect(
        Rect.fromLTWH(0.46 * s, 0.14 * s, 0.08 * s, 0.16 * s),
        bodyPaint,
      )
      ..drawCircle(
        Offset(0.5 * s, 0.12 * s),
        0.05 * s,
        Paint()..color = antenna,
      );
    final featurePaint = Paint()..color = features;
    canvas
      ..drawCircle(Offset(eyeOffset * s, 0.48 * s), 0.06 * s, featurePaint)
      ..drawCircle(
        Offset((1 - eyeOffset) * s, 0.48 * s),
        0.06 * s,
        featurePaint,
      )
      ..drawRect(
        Rect.fromLTWH(
          (0.5 - mouthWidth * 2) * s,
          0.62 * s,
          mouthWidth * 4 * s,
          0.05 * s,
        ),
        featurePaint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_RobotPainter old) =>
      old.background != background ||
      old.body != body ||
      old.features != features ||
      old.antenna != antenna ||
      old.eyeOffset != eyeOffset ||
      old.mouthWidth != mouthWidth;
}
