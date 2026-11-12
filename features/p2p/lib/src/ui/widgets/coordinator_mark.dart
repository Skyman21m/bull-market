import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import 'seed_hash.dart';

/// The mark of a coordinator: its initials in a framed rounded square, so that a coordinator never reads as one more robot, whose avatar is round.
///
/// The official client shows the image each coordinator gave RoboSats (`frontend/static/federation/avatars/` at commit ff1998c).
/// Troc does not bundle those images while their licence is not established (#57): this mark stands in for them, for every coordinator.
/// The initials are the capital letters A to Z of the long alias, at most two, or else the first character of the short alias, upper-cased.
/// The colour of the frame and of the background is a theme colour chosen by the short alias, and the initials take the colour of the text.
/// So a coordinator has the same mark on every screen and at every run, and nothing a coordinator sends changes it.
/// The mark is decorative: the name of the coordinator is always written beside it.
class CoordinatorMark extends StatelessWidget {
  final Coordinator coordinator;
  final double size;

  const CoordinatorMark({super.key, required this.coordinator, this.size = 40});

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
    final color = palette[seedHash(coordinator.shortAlias) % palette.length];
    final frame = math.max(1.5, size * 0.045);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: 0.28),
            colors.surface,
          ),
          border: Border.all(color: color, width: frame),
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        // One letter or two keep the same size; only a very wide pair shrinks to fit.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initialsOf(coordinator),
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: colors.text,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  /// The letters the mark of [coordinator] shows: the first two capital letters A to Z of its long alias, or else the first character of its short alias, upper-cased.
  ///
  /// Only these letters are taken from the alias, so no direction mark, joiner or combining character of a coordinator's text reaches the mark.
  static String initialsOf(Coordinator coordinator) {
    final capitals = RegExp('[A-Z]')
        .allMatches(coordinator.longAlias)
        .take(2)
        .map((match) => match[0] ?? '')
        .join();
    if (capitals.isNotEmpty) return capitals;
    final alias = coordinator.shortAlias;
    return alias.isEmpty ? '' : alias.substring(0, 1).toUpperCase();
  }
}
