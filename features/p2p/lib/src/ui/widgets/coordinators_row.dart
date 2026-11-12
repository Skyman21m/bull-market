import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/book_state.dart';
import '../../presentation/coordinator_text.dart';
import 'coordinator_avatar.dart';

/// Where one coordinator of the row stands, as the row draws it.
enum CoordinatorRowState {
  /// Its book has arrived: its image is lit.
  answered,

  /// Its book is being requested, or it is about to be asked again: its image is dimmed, with a clock.
  awaited,

  /// It gave no book after its last attempt: its image is grey and dimmed, with the offline mark.
  offline;

  /// How the row draws [status].
  static CoordinatorRowState of(CoordinatorBookStatus status) =>
      switch (status) {
        CoordinatorBookLoaded() => answered,
        CoordinatorBookLoading() => awaited,
        CoordinatorBookFailed() => offline,
      };
}

/// The coordinators of the book above its offers: the image of each, in the order of the federation, lit once its book has arrived, and a line under them.
///
/// Troc's own, asked for by the owner (#73): the official client shows no state per coordinator above its book, only a bar while any loads.
/// It stays once the offers are shown, so that the user always sees who is there, who is still awaited and who is offline, whatever the « hosted by » filter.
/// The line says how many coordinators answered while any is awaited, how many are offline with « Retry » once none is, and how many answered, all of them, once all did; it keeps the room of its largest form, so nothing moves when it changes.
/// A tap on an image calls [onOpenCoordinator], which opens the coordinator's dialog.
/// One animation at most: the awaited images pulse together on one controller, which runs only while one is awaited and never with reduced motion; the clock of an awaited image is its sign either way.
/// Each image is one node for a screen reader, its name and its state, not announced when the state changes.
class CoordinatorsRow extends StatefulWidget {
  /// The size of a coordinator's image.
  static const imageSize = 32.0;

  /// The size of the place a tap reaches around each image.
  static const tapSize = 48.0;

  /// The opacity of a dimmed image that does not pulse.
  static const dimmed = 0.38;

  /// How long one pulse of the awaited images takes, out and back.
  static const pulse = Duration(milliseconds: 1600);

  final BookState state;
  final ValueChanged<Coordinator> onOpenCoordinator;
  final VoidCallback onRetry;

  const CoordinatorsRow({
    super.key,
    required this.state,
    required this.onOpenCoordinator,
    required this.onRetry,
  });

  @override
  State<CoordinatorsRow> createState() => _CoordinatorsRowState();
}

class _CoordinatorsRowState extends State<CoordinatorsRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: CoordinatorsRow.pulse ~/ 2,
    // Reduced motion is read from the context below: the controller does not run then at all.
    animationBehavior: AnimationBehavior.preserve,
  );

  late final Animation<double> _opacity = _pulse.drive(
    Tween(begin: 0.25, end: 0.6),
  );

  /// Whether reduced motion is asked for.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(CoordinatorsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Runs the pulse while an image is awaited and motion is allowed, and stops it otherwise.
  void _sync() {
    final run = !_still && widget.state.loadingCoordinators.isNotEmpty;
    if (run && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!run && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.coordinators.isEmpty) return const SizedBox.shrink();
    final opacity = _still
        ? const AlwaysStoppedAnimation(CoordinatorsRow.dimmed)
        : _opacity;
    return Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // Each image is centred in its place, so that its edge lines up with the text of the book.
            padding: const EdgeInsets.symmetric(
              horizontal:
                  BullSpacing.md -
                  (CoordinatorsRow.tapSize - CoordinatorsRow.imageSize) / 2,
            ),
            child: Wrap(
              children: [
                for (final MapEntry(key: coordinator, value: status)
                    in state.coordinators.entries)
                  CoordinatorRowPlace(
                    coordinator: coordinator,
                    state: CoordinatorRowState.of(status),
                    opacity: opacity,
                    onTap: () => widget.onOpenCoordinator(coordinator),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BullSpacing.md),
            child: CoordinatorsLine(state: state, onRetry: widget.onRetry),
          ),
        ],
      ),
    );
  }
}

/// One coordinator of [CoordinatorsRow]: its image in a place a tap reaches, and the sign of its state.
class CoordinatorRowPlace extends StatelessWidget {
  final Coordinator coordinator;
  final CoordinatorRowState state;
  final Animation<double> opacity;
  final VoidCallback onTap;

  /// Grey from the luminance of each colour: an offline image keeps its shapes, not its colours.
  static const _grey = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  const CoordinatorRowPlace({
    super.key,
    required this.coordinator,
    required this.state,
    required this.opacity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final name = CoordinatorText.of(
      coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    final image = CoordinatorAvatar(
      coordinator: coordinator,
      size: CoordinatorsRow.imageSize,
    );
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: switch (state) {
        CoordinatorRowState.answered => l10n.p2pBookCoordinatorAnswered(name),
        CoordinatorRowState.awaited => l10n.p2pBookCoordinatorAwaited(name),
        CoordinatorRowState.offline => l10n.p2pBookCoordinatorOffline(name),
      },
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: CoordinatorsRow.tapSize / 2,
        child: SizedBox.square(
          dimension: CoordinatorsRow.tapSize,
          child: Center(
            child: SizedBox.square(
              dimension: CoordinatorsRow.imageSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  switch (state) {
                    CoordinatorRowState.answered => image,
                    CoordinatorRowState.awaited => FadeTransition(
                      opacity: opacity,
                      child: image,
                    ),
                    CoordinatorRowState.offline => Opacity(
                      opacity: CoordinatorsRow.dimmed,
                      child: ColorFiltered(colorFilter: _grey, child: image),
                    ),
                  },
                  if (state != CoordinatorRowState.answered)
                    PositionedDirectional(
                      end: -_Sign.overhang,
                      bottom: -_Sign.overhang,
                      child: switch (state) {
                        CoordinatorRowState.offline => _Sign(
                          icon: Icons.cloud_off,
                          color: colors.warning,
                        ),
                        _ => _Sign(
                          icon: BullIcons.schedule,
                          color: colors.textMuted,
                        ),
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small mark at the corner of an image that is not lit: a clock while awaited, the offline mark once offline.
class _Sign extends StatelessWidget {
  static const size = 16.0;

  /// How far the mark goes past the corner of the image.
  static const overhang = 3.0;

  final IconData icon;
  final Color color;

  const _Sign({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.surface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.outlineVariant),
      ),
      alignment: Alignment.center,
      child: BullIcon(icon, size: size - 5, color: color),
    );
  }
}

/// The line under the images: how many coordinators answered while any is awaited or once all did, and how many are offline, with « Retry », once none is awaited and some gave no book.
///
/// It keeps the room of the largest of its forms, laid out unseen behind it with the counts of the whole federation, as the Tor wait keeps the room of its percentage: nothing below it moves when it changes, at any text size.
/// Its counts are drawn with figures of one width, so that a new count does not shift the words after it.
class CoordinatorsLine extends StatelessWidget {
  final BookState state;
  final VoidCallback onRetry;

  const CoordinatorsLine({
    super.key,
    required this.state,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final total = state.coordinators.length;
    final offline = state.failedCoordinators.length;
    final shown = state.loadingCoordinators.isEmpty && offline > 0
        ? _Line.offline(count: offline, onRetry: onRetry)
        : _Line.answered(answered: state.answeredCount, total: total);
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        for (final form in [
          _Line.answered(answered: total, total: total),
          _Line.offline(count: total, onRetry: onRetry),
        ])
          Visibility(
            visible: false,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: form,
          ),
        shown,
      ],
    );
  }
}

/// One form of [CoordinatorsLine].
class _Line extends StatelessWidget {
  final int count;
  final int? total;
  final VoidCallback? onRetry;

  const _Line.answered({required int answered, required int this.total})
    : count = answered,
      onRetry = null;

  const _Line.offline({required this.count, required VoidCallback this.onRetry})
    : total = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final total = this.total;
    final onRetry = this.onRetry;
    final style = text.labelMedium?.copyWith(
      color: onRetry == null ? colors.textMuted : colors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (total != null) {
      return Text(l10n.p2pBookCoordinatorsAnswered(count, total), style: style);
    }
    // « Retry » goes under the words when they leave it no room beside them, at a large text size.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BullIcon(Icons.cloud_off, size: 16, color: colors.warning),
            const Gap(BullSpacing.xs),
            Flexible(
              child: Text(l10n.p2pBookCoordinatorsOffline(count), style: style),
            ),
          ],
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            l10n.p2pCommonRetry,
            style: text.labelLarge?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
