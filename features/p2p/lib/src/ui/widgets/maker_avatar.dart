import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../presentation/coordinator_text.dart';
import 'coordinator_avatar.dart';
import 'robot_avatar.dart';

/// The robot of the maker of [order], badged at its bottom left with the avatar of the coordinator that hosts the order.
///
/// The official client badges a maker so in its book and in the tooltip of its depth chart (`coordinatorShortAlias` of `components/RobotAvatar/index.tsx` at commit ff1998c), only for a coordinator of the federation, as here.
/// Two choices are deliberate: the badge is two fifths of the robot where the official client's is about a quarter, so that it reads on a phone, and it is not mirrored, where the official client's badge inherits the mirroring of its robot, by all appearances unintended.
/// The badge lies over the robot's corner and takes no room of its own, so the row around it keeps its layout.
/// With [namesCoordinator], the badge tells a screen reader the coordinator's name, as the official client's image has it for its `alt`: in the book, where the name is written nowhere else; elsewhere, the name is written beside it.
class MakerAvatar extends StatelessWidget {
  final PublicOrder order;
  final double size;
  final bool namesCoordinator;

  /// The size of the badge, as a share of the size of the robot.
  static const badgeShare = 0.4;

  /// How far the badge passes the robot's left and bottom edges, as a share of the size of the robot.
  static const badgeOffset = 0.08;

  const MakerAvatar({
    super.key,
    required this.order,
    this.size = 40,
    this.namesCoordinator = true,
  });

  @override
  Widget build(BuildContext context) {
    final coordinator = order.coordinator;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          RobotAvatar(seed: order.maker.hex, size: size),
          if (coordinator.federated)
            Positioned(
              left: -size * badgeOffset,
              bottom: -size * badgeOffset,
              child: Semantics(
                label: namesCoordinator
                    ? CoordinatorText.of(
                        coordinator.longAlias,
                        maxCodePoints: CoordinatorText.name,
                      )
                    : null,
                child: CoordinatorAvatar(
                  coordinator: coordinator,
                  size: size * badgeShare,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
