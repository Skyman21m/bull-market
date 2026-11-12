import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/p2p_shuffle.dart';

/// Short phrases under the bar of the Tor wait, one at a time, a new one every [period], next to a small gear that turns.
///
/// They are Troc's own texts, asked for by the owner (#68): the official client shows none while Tor starts.
/// They come in the order [shuffle] gives when the widget is built, and the wait builds it only while Tor starts, so each wait, a new entry in the tab or « Retry », draws a new order.
/// The cost is one timer, which changes the phrase and rebuilds this widget only, and one animation controller, which turns the gear and fades each phrase in and out; both end with the widget, when Tor is ready or has failed or the screen leaves.
/// With reduced motion, the gear stands still and the phrase changes without a fade.
/// The phrases are decoration: they stay out of the semantics tree, so that a screen reader does not read a new one every 2 seconds.
class TorWaitPhrases extends StatefulWidget {
  /// How long each phrase is shown.
  static const period = Duration(seconds: 2);

  final P2pShuffle shuffle;

  const TorWaitPhrases({super.key, required this.shuffle});

  /// The phrases, in the order of the list the owner approved.
  static List<String> phrasesOf(P2pLocalizations l10n) => [
    l10n.p2pTorWaitPhrase1,
    l10n.p2pTorWaitPhrase2,
    l10n.p2pTorWaitPhrase3,
    l10n.p2pTorWaitPhrase4,
    l10n.p2pTorWaitPhrase5,
    l10n.p2pTorWaitPhrase6,
    l10n.p2pTorWaitPhrase7,
    l10n.p2pTorWaitPhrase8,
    l10n.p2pTorWaitPhrase9,
    l10n.p2pTorWaitPhrase10,
    l10n.p2pTorWaitPhrase11,
    l10n.p2pTorWaitPhrase12,
  ];

  /// How many phrases there are.
  static const count = 12;

  @override
  State<TorWaitPhrases> createState() => _TorWaitPhrasesState();
}

class _TorWaitPhrasesState extends State<TorWaitPhrases>
    with SingleTickerProviderStateMixin {
  /// One turn of the gear and one fade in and out for each phrase.
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: TorWaitPhrases.period,
    // Reduced motion is read from the context below: a controller that the platform's setting sped up would no longer keep step with the timer.
    animationBehavior: AnimationBehavior.preserve,
  );

  /// In over the first 300 milliseconds of a phrase, out over its last 300.
  late final Animation<double> _fade = _motion.drive(
    TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 15),
    ]),
  );

  late final List<int> _order;
  late final Timer _timer;
  int _step = 0;

  /// Whether reduced motion is asked for; `null` until the context is read.
  bool? _still;

  /// Whether the gear turns and the phrase fades: from the start, or from the next phrase once motion is allowed again, so that the fade keeps step with the timer.
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _order = widget.shuffle.positions(TorWaitPhrases.count);
    _timer = Timer.periodic(TorWaitPhrases.period, (_) => _next());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still == _still) return;
    final first = _still == null;
    _still = still;
    if (still) {
      _moving = false;
      _motion
        ..stop()
        ..value = 0;
    } else if (first) {
      _moving = true;
      _motion.forward(from: 0);
    }
  }

  void _next() => setState(() {
    _step++;
    if (_still == false) {
      _moving = true;
      _motion.forward(from: 0);
    }
  });

  @override
  void dispose() {
    _timer.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final phrases = TorWaitPhrases.phrasesOf(P2pLocalizations.of(context));
    return ExcludeSemantics(
      child: Stack(
        alignment: Alignment.center,
        children: [
          const _Footprint(),
          _PhraseLine(
            text: phrases[_order[_step % _order.length]],
            opacity: _moving ? _fade : kAlwaysCompleteAnimation,
            gear: RotationTransition(
              turns: _motion,
              child: BullIcon(
                Icons.settings,
                size: _PhraseLine.gearSize,
                color: colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every phrase laid out as the one shown, and none painted: the phrases take the room of the largest, so nothing on the screen moves when one changes.
///
/// It depends only on the texts and the theme, so a change of phrase does not rebuild it.
class _Footprint extends StatelessWidget {
  const _Footprint();

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      for (final phrase in TorWaitPhrases.phrasesOf(
        P2pLocalizations.of(context),
      ))
        Visibility(
          visible: false,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: _PhraseLine(
            text: phrase,
            opacity: kAlwaysCompleteAnimation,
            gear: const SizedBox.square(dimension: _PhraseLine.gearSize),
          ),
        ),
    ],
  );
}

/// The gear, then the phrase, which wraps on as many lines as it needs.
class _PhraseLine extends StatelessWidget {
  static const gearSize = 16.0;

  final String text;
  final Animation<double> opacity;
  final Widget gear;

  const _PhraseLine({
    required this.text,
    required this.opacity,
    required this.gear,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      gear,
      const Gap(BullSpacing.xs),
      Flexible(
        child: FadeTransition(
          opacity: opacity,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.bull.textMuted),
          ),
        ),
      ),
    ],
  );
}
