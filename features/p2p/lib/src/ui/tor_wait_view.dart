import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/tor_wait.dart';

/// The wait for Tor inside the P2P tab, in the three steps of the official Android client: initializing, connecting, connected.
///
/// The wallet stays usable meanwhile: only this tab waits.
class TorWaitView extends StatelessWidget {
  final TorWait tor;
  final VoidCallback onRetry;

  const TorWaitView({super.key, required this.tor, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final failed = tor == TorWait.failed;
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
            ClipRRect(
              borderRadius: BorderRadius.circular(BullRadius.xxs),
              child: LinearProgressIndicator(
                value: reached / steps.length,
                minHeight: 4,
                color: colors.primary,
                backgroundColor: colors.surfaceContainer,
              ),
            ),
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
