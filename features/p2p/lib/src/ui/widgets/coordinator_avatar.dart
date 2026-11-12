import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import 'coordinator_images.dart';
import 'coordinator_mark.dart';

/// The avatar of a coordinator: the image the official client shows for it, in a disc, as its avatar component draws a coordinator (`components/RobotAvatar/index.tsx` at commit ff1998c), with a thin ring in the theme's outline colour.
///
/// The image is an asset bundled with the feature, found in [coordinatorImages] by the coordinator's short alias.
/// It is asked at the size it is drawn, in device pixels (`cacheWidth`, `cacheHeight`), so the 200-pixel file of a 16-point badge is decoded at 48 pixels on a screen of density 3; Flutter's `ResizeImage` never enlarges, so a larger size decodes at the file's own 200 pixels.
/// It is never read from the network or from what a coordinator sends.
/// A coordinator without a row in that table, or whose image cannot be loaded or decoded, is drawn with its [CoordinatorMark], so the place is never blank; while the image is decoded, a plain disc stands in.
/// The avatar itself says nothing to a screen reader: on the order page and in the coordinator dialog the name is written beside it, and as the badge of a maker in the book, `MakerAvatar` gives it the name.
class CoordinatorAvatar extends StatelessWidget {
  final Coordinator coordinator;
  final double size;

  /// The package the image assets belong to.
  static const package = 'p2p';

  const CoordinatorAvatar({
    super.key,
    required this.coordinator,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CoordinatorMark(coordinator: coordinator, size: size);
    final image = coordinatorImages[coordinator.shortAlias];
    if (image == null) return mark;
    final colors = context.bull;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          image.asset,
          package: package,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: pixels,
          cacheHeight: pixels,
          excludeFromSemantics: true,
          frameBuilder: (context, child, _, _) => Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              shape: BoxShape.circle,
            ),
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: ClipOval(child: child),
          ),
          errorBuilder: (_, _, _) => mark,
        ),
      ),
    );
  }
}
