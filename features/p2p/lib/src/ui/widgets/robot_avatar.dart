import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'seed_hash.dart';

/// A provisional robot avatar, drawn from a seed such as the hash id of a robot or the alias of a coordinator.
///
/// The same seed always gives the same robot, so a maker is recognisable from one screen to the next.
/// Robots differ by colour, head, eyes, antennas and mouth, all chosen from the seed; the colours are those of the theme.
/// The real RoboSats avatars come with ticket #22.
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
      colors.tertiary,
      colors.primary,
      colors.bitcoinOrange,
      colors.secondary,
      colors.onSurfaceVariant,
    ];
    final hash = seedHash(seed);
    final body = hash % palette.length;
    // The background never takes the colour of the body.
    final background =
        (body + 1 + (hash >> 3) % (palette.length - 1)) % palette.length;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RobotPainter(
            background: Color.alphaBlend(
              palette[background].withValues(alpha: 0.28),
              colors.surface,
            ),
            body: palette[body],
            features: colors.background,
            antenna: colors.bitcoinOrange,
            roundHead: (hash >> 6) & 1 == 1,
            squareEyes: (hash >> 7) & 1 == 1,
            twoAntennas: (hash >> 8) & 1 == 1,
            grilleMouth: (hash >> 9) & 1 == 1,
            eyeOffset: 0.32 + ((hash >> 10) % 6) / 100,
          ),
        ),
      ),
    );
  }
}

class _RobotPainter extends CustomPainter {
  final Color background;
  final Color body;
  final Color features;
  final Color antenna;
  final bool roundHead;
  final bool squareEyes;
  final bool twoAntennas;
  final bool grilleMouth;
  final double eyeOffset;

  const _RobotPainter({
    required this.background,
    required this.body,
    required this.features,
    required this.antenna,
    required this.roundHead,
    required this.squareEyes,
    required this.twoAntennas,
    required this.grilleMouth,
    required this.eyeOffset,
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
    final antennaPaint = Paint()..color = antenna;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.24 * s, 0.30 * s, 0.52 * s, 0.46 * s),
        Radius.circular((roundHead ? 0.18 : 0.04) * s),
      ),
      bodyPaint,
    );
    for (final x in twoAntennas ? [0.34, 0.62] : [0.46]) {
      canvas
        ..drawRect(
          Rect.fromLTWH(x * s, 0.16 * s, 0.06 * s, 0.14 * s),
          bodyPaint,
        )
        ..drawCircle(Offset((x + 0.03) * s, 0.14 * s), 0.05 * s, antennaPaint);
    }
    final featurePaint = Paint()..color = features;
    for (final x in [eyeOffset, 1 - eyeOffset]) {
      if (squareEyes) {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x * s, 0.48 * s),
            width: 0.11 * s,
            height: 0.11 * s,
          ),
          featurePaint,
        );
      } else {
        canvas.drawCircle(Offset(x * s, 0.48 * s), 0.06 * s, featurePaint);
      }
    }
    if (grilleMouth) {
      for (final x in [0.38, 0.47, 0.56]) {
        canvas.drawRect(
          Rect.fromLTWH(x * s, 0.60 * s, 0.06 * s, 0.08 * s),
          featurePaint,
        );
      }
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0.36 * s, 0.62 * s, 0.28 * s, 0.05 * s),
        featurePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RobotPainter old) =>
      old.background != background ||
      old.body != body ||
      old.features != features ||
      old.antenna != antenna ||
      old.roundHead != roundHead ||
      old.squareEyes != squareEyes ||
      old.twoAntennas != twoAntennas ||
      old.grilleMouth != grilleMouth ||
      old.eyeOffset != eyeOffset;
}
