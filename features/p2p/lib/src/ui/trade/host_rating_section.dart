import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_watch.dart';
import '../../presentation/host_rating_cubit.dart';
import '../garage/robosats_links.dart' show simplexGroupUrl;
import '../widgets/coordinator_link_sheet.dart';
import '../widgets/word_fit_text.dart';

/// Builds « Rate your host » for [seen], the status shown, and [coordinator], the long alias of the trade's coordinator: the route gives it, over the page's [HostRatingCubit].
typedef HostRatingBuilder =
    Widget Function(BuildContext context, TradeSeen seen, String coordinator);

/// « Rate your host » of the official client (`TradeBox/Prompts/Successful.tsx:129-219`, commit ff1998c; #95), under « Rate your trade experience »: its title with the coordinator's name, five stars, and, once a star is tapped, the reference's thanks and its links.
///
/// The token is asked once the shown status offers the rating ([HostRatingCubit.show]); the stars are off until it is in hand, a line saying what they wait for, and stay off when it was not given, a line saying that no rating can be published: the reference leaves its stars on and drops a tap made without a token (declared deviation).
/// Each tap publishes the rating once ([HostRatingCubit.rate]), as the reference publishes each change of its stars; what the publication gave is shown nowhere, as in the reference, whose thanks follow the tap alone.
/// The reference's setting « api / nostr » does not exist here, and the stars are offered as with its default, « nostr »: its tooltip « You need to enable nostr to rate your coordinator. » is never shown.
/// The links of the thanks are shown for copy ([CoordinatorLinkSheet]), never opened, as everywhere in the P2P screens; their names are those of the reference's code (« SimpleX / Matrix / Github »), not of its translation, which puts « Telegram » on the SimpleX link and « Github » on the Matrix one.
class HostRatingSection extends StatefulWidget {
  final TradeSeen seen;

  /// The long alias of the trade's coordinator.
  final String coordinator;

  const HostRatingSection({
    super.key,
    required this.seen,
    required this.coordinator,
  });

  /// The RoboSats group on Matrix, which the reference links from its thanks.
  static const matrixUrl = 'https://matrix.to/#/#robosatsorg:matrix.org';

  /// The issues of the RoboSats repository, which the reference links from its thanks.
  static const githubUrl = 'https://github.com/RoboSats/robosats/issues';

  @override
  State<HostRatingSection> createState() => _HostRatingSectionState();
}

class _HostRatingSectionState extends State<HostRatingSection> {
  /// The star last tapped, kept by the section as the reference's `Rating` keeps its own.
  int? _stars;

  late final List<TapGestureRecognizer> _links = [
    for (final (name, url) in _linkTargets)
      TapGestureRecognizer()
        ..onTap = () => CoordinatorLinkSheet.show(
          context,
          title: name(P2pLocalizations.of(context)),
          value: url,
        ),
  ];

  static final List<(String Function(P2pLocalizations l10n), String)>
  _linkTargets = [
    ((l10n) => l10n.p2pEndImproveSimplex, simplexGroupUrl),
    ((l10n) => l10n.p2pEndImproveMatrix, HostRatingSection.matrixUrl),
    ((l10n) => l10n.p2pEndImproveGithub, HostRatingSection.githubUrl),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(context.read<HostRatingCubit>().show(widget.seen));
  }

  @override
  void didUpdateWidget(HostRatingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seen != widget.seen) {
      unawaited(context.read<HostRatingCubit>().show(widget.seen));
    }
  }

  @override
  void dispose() {
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  void _rate(int stars) {
    final rating = HostRating.of(stars);
    if (rating == null) return;
    setState(() => _stars = stars);
    unawaited(context.read<HostRatingCubit>().rate(widget.seen, rating));
  }

  /// « Let us know how the platform could improve (SimpleX / Matrix / Github) »: the translation's sentence, its punctuation included, written with a mark at the place of each name, then each mark replaced by its link.
  List<InlineSpan> _improveSpans(P2pLocalizations l10n, Color linkColor) {
    const marks = ['\u0000', '\u0001', '\u0002'];
    final sentence = l10n.p2pEndImprove(marks[0], marks[1], marks[2]);
    final spans = <InlineSpan>[];
    var start = 0;
    for (var i = 0; i < sentence.length; i++) {
      final index = marks.indexOf(sentence[i]);
      if (index < 0) continue;
      if (i > start) spans.add(TextSpan(text: sentence.substring(start, i)));
      spans.add(
        TextSpan(
          text: _linkTargets[index].$1(l10n),
          recognizer: _links[index],
          style: TextStyle(
            color: linkColor,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      start = i + 1;
    }
    if (start < sentence.length) {
      spans.add(TextSpan(text: sentence.substring(start)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final body = Theme.of(context).textTheme.bodyMedium;
    final state = context.watch<HostRatingCubit>().state;
    final offered =
        state is HostRatingReady && ChatStepAction.rate.offeredAt(widget.seen);
    final stars = _stars;
    return Column(
      key: const ValueKey('trade-host-rating'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: BullSpacing.xs,
          children: [
            WordFitText(
              l10n.p2pEndRateHost,
              textAlign: TextAlign.center,
              style: body?.copyWith(color: colors.text),
            ),
            WordFitText(
              widget.coordinator,
              textAlign: TextAlign.center,
              style: body?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = HostRating.min; star <= HostRating.max; star++)
              Semantics(
                selected: _stars == star,
                child: IconButton(
                  key: ValueKey('trade-host-star-$star'),
                  tooltip: l10n.p2pEndRateStar('$star'),
                  onPressed: offered ? () => _rate(star) : null,
                  icon: Icon(
                    star <= (stars ?? 0) ? Icons.star : Icons.star_border,
                    size: 32,
                    color: offered ? colors.warning : colors.textMuted,
                  ),
                ),
              ),
          ],
        ),
        switch (state) {
          HostRatingAsking() => _Live(
            l10n.p2pEndRateHostAsking(widget.coordinator),
            color: colors.textMuted,
          ),
          HostRatingUnavailable() => _Live(
            l10n.p2pEndRateHostUnavailable(widget.coordinator),
            color: colors.textMuted,
          ),
          HostRatingIdle() || HostRatingReady() => const SizedBox.shrink(),
        },
        if (stars != null) ...[
          const Gap(BullSpacing.xs),
          if (stars == HostRating.max) ...[
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BullSpacing.xs,
              children: [
                WordFitText(
                  l10n.p2pEndHostLovesYou(widget.coordinator),
                  textAlign: TextAlign.center,
                  style: body?.copyWith(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(Icons.favorite, color: colors.error),
                ),
              ],
            ),
            WordFitText(
              l10n.p2pEndTellAFriend,
              textAlign: TextAlign.center,
              style: body?.copyWith(color: colors.text),
            ),
          ] else ...[
            WordFitText(
              l10n.p2pEndThanksForUsing,
              textAlign: TextAlign.center,
              style: body?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text.rich(
              key: const ValueKey('trade-host-improve'),
              TextSpan(children: _improveSpans(l10n, colors.primary)),
              textAlign: TextAlign.center,
              style: body?.copyWith(color: colors.text),
            ),
          ],
        ],
      ],
    );
  }
}

/// A line read out as it changes.
class _Live extends StatelessWidget {
  final String text;
  final Color color;

  const _Live(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: WordFitText(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    ),
  );
}
