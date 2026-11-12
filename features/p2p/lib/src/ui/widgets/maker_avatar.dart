import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import 'coordinator_avatar.dart';
import 'robot_avatar.dart';

/// The robot of the maker of [order], badged at its bottom left with the avatar of the coordinator that hosts the order.
///
/// The official client badges a maker so in its book and in the tooltip of its depth chart (`coordinatorShortAlias` of `components/RobotAvatar/index.tsx` at commit ff1998c), with a badge of about a quarter of the robot; here it is two fifths, so that it reads on a phone.
/// The badge lies over the robot's corner and takes no room of its own, so the row around it keeps its layout.
class MakerAvatar extends StatelessWidget {
  final PublicOrder order;
  final double size;

  /// The size of the badge, as a share of the size of the robot.
  static const badgeShare = 0.4;

  const MakerAvatar({super.key, required this.order, this.size = 40});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        RobotAvatar(seed: order.maker.hex, size: size),
        Positioned(
          left: -size * 0.08,
          bottom: -size * 0.08,
          child: CoordinatorAvatar(
            coordinator: order.coordinator,
            size: size * badgeShare,
          ),
        ),
      ],
    ),
  );
}
