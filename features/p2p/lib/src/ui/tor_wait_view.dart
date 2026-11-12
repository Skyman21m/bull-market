import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_shuffle.dart';
import '../domain/tor_wait.dart';
import '../presentation/p2p_formats.dart';
import 'widgets/tor_wait_phrases.dart';

/// The wait for Tor inside the P2P tab, in the three steps of the official Android client: initializing, connecting, connected.
///
/// Below the steps, a bar runs while Tor starts, so that the wait reads as work in progress, as the official Android client's spinner turns until Tor is ready (`activity_main.xml` at commit ff1998c).
/// Once Tor reports how far it has got, the bar is filled to that share and the [percent] stands next to it: the official Android client reads Tor's bootstrap percentage (`TorKmpManager.kt`) but shows none, and the owner asked for it (#68).
/// The room of the percentage is kept for the whole wait, so nothing moves when it comes.
/// With reduced motion, the run of the bar stops once a percentage is shown: the fill and the number carry the progress.
/// Under the bar, short phrases change every 2 seconds ([TorWaitPhrases], Troc's own texts, also asked for by the owner).
/// Neither the percentage nor the phrases show once Tor is ready or has failed.
/// The wallet stays usable meanwhile: only this tab waits.
class TorWaitView extends StatelessWidget {
  final TorWait tor;

  /// How far Tor has got in starting, as `TorWait.percentAfter` gives it; shown only while Tor connects, and `null` shows none.
  final int? percent;

  /// The order of the phrases, drawn anew at each wait.
  final P2pShuffle shuffle;

  final VoidCallback onRetry;

  const TorWaitView({
    super.key,
    required this.tor,
    this.percent,
    required this.shuffle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final failed = tor == TorWait.failed;
    final waiting = tor == TorWait.initializing || tor == TorWait.connecting;
    final percent = tor == TorWait.connecting ? this.percent : null;
    final formats = P2pFormats.of(context);
    final percentStyle = text.labelLarge?.copyWith(
      color: colors.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Tor fails while it connects: the failure shows on that step.
    final reached = switch (tor) {
      TorWait.initializing => 0,
      TorWait.connecting || TorWait.failed => 1,
      TorWait.ready => 3,
    };
    final steps = [
      l10n.p2pTorInitializing,
      l10n.p2pTorConnecting,
      l10n.p2pTorConnected,
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BullSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              failed ? l10n.p2pTorConnectionError : l10n.p2pTorConnecting,
              textAlign: TextAlign.center,
              style: text.displaySmall?.copyWith(
                color: failed ? colors.error : colors.text,
              ),
            ),
            const Gap(BullSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BullSpacing.md,
                vertical: BullSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(BullRadius.xxs),
              ),
              child: Column(
                children: [
                  for (final (index, label) in steps.indexed)
                    _TorStep(
                      label: label,
                      step: index < reached
                          ? _StepState.done
                          : index == reached
                          ? (failed ? _StepState.failed : _StepState.now)
                          : _StepState.pending,
                    ),
                ],
              ),
            ),
            const Gap(BullSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _TorBar(
                    // With reduced motion, the fill and the number carry the progress once Tor reports a share, and the run stops; before that, it runs, as decided in #62.
                    running:
                        waiting &&
                        !(MediaQuery.disableAnimationsOf(context) &&
                            percent != null),
                    percent: percent,
                  ),
                ),
                const Gap(BullSpacing.xs),
                // The room of the widest percentage is kept for the whole wait, so that neither the bar nor the screen moves when a percentage comes, goes or gains a digit.
                Stack(
                  alignment: AlignmentDirectional.centerEnd,
                  children: [
                    Visibility(
                      visible: false,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: Text(
                        formats.torProgress(TorWait.maxPercent),
                        style: percentStyle,
                      ),
                    ),
                    if (percent != null)
                      Text(formats.torProgress(percent), style: percentStyle),
                  ],
                ),
              ],
            ),
            if (waiting) ...[
              const Gap(BullSpacing.sm),
              TorWaitPhrases(shuffle: shuffle),
            ],
            const Gap(BullSpacing.sm),
            Text(
              l10n.p2pTorWaitingLine,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
            if (failed) ...[
              const Gap(BullSpacing.lg),
              BullButton.big(
                label: l10n.p2pCommonRetry,
                onPressed: onRetry,
                bgColor: colors.primary,
                textColor: colors.onPrimary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bar under the steps.
///
/// It runs while [running], as the official Android client's spinner turns until Tor is ready, and fades out when it stops.
/// With a [percent], the part done is filled and the run goes on over the whole bar: dimmed where the start is not done yet, so that it does not read as done, and in a lighter tint over the fill, so that the bar never stands still while Tor is not ready, even at 0 % or during the seconds `bull_tor` holds readiness at a full share.
class _TorBar extends StatelessWidget {
  static const height = 4.0;

  /// The run that goes on for the whole wait: keeping it when a percentage comes or goes keeps its pace and its fade.
  static const _runKey = ValueKey('run');

  final bool running;
  final int? percent;

  const _TorBar({required this.running, required this.percent});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final percent = this.percent;
    BullFadingLinearProgress run(Color color, Color track, {Key? key}) =>
        BullFadingLinearProgress(
          key: key,
          trigger: running,
          height: height,
          foregroundColor: color,
          backgroundColor: track,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              if (percent != null) ColoredBox(color: colors.surfaceContainer),
              percent == null
                  ? run(colors.primary, colors.surfaceContainer, key: _runKey)
                  : run(
                      colors.primary.withValues(alpha: 0.4),
                      colors.transparent,
                      key: _runKey,
                    ),
              if (percent != null)
                AnimatedFractionallySizedBox(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: percent / 100,
                  child: ColoredBox(
                    color: colors.primary,
                    // The run laid out over the whole bar, and cut to the part done.
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: AlignmentDirectional.centerStart,
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth,
                        child: run(
                          Color.alphaBlend(
                            colors.onPrimary.withValues(alpha: 0.45),
                            colors.primary,
                          ),
                          colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _StepState { done, now, failed, pending }

class _TorStep extends StatelessWidget {
  final String label;
  final _StepState step;

  const _TorStep({required this.label, required this.step});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final color = switch (step) {
      _StepState.done => colors.text,
      _StepState.now => colors.warning,
      _StepState.failed => colors.error,
      _StepState.pending => colors.textMuted,
    };
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.sm),
      child: Row(
        children: [
          if (step == _StepState.now) _Blinking(child: dot) else dot,
          const Gap(BullSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades its child in and out, the mark of the step Tor is on; still when the platform asks for reduced motion.
class _Blinking extends StatefulWidget {
  final Widget child;

  const _Blinking({required this.child});

  @override
  State<_Blinking> createState() => _BlinkingState();
}

class _BlinkingState extends State<_Blinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 1, end: 0.2).animate(_controller),
    child: widget.child,
  );
}
