import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/coordinator_size_limit.dart';
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_formats.dart';
import 'widgets/coordinator_link_sheet.dart';
import 'widgets/robot_avatar.dart';

/// The details of a coordinator, in the order of the official client's dialog (`components/Dialogs/Coordinator.tsx` at commit ff1998c): name, avatar, motto, contacts, notice, badges, description, date, web app, then its policies, summary and statistics once it answers.
///
/// It shows two things the official client reads elsewhere differently:
/// - no rating: the official client reads the ratings of a coordinator from Nostr relays, which Troc does not reach;
/// - no client version beside the coordinator version: Troc is not a RoboSats client release.
/// Every link is shown in full and copied, never opened, and every text of the coordinator is plain text.
class CoordinatorDetailsDialog extends StatefulWidget {
  const CoordinatorDetailsDialog({super.key});

  /// Opens the dialog over the current page, with the cubit [create] builds, which asks the coordinator for its info if needed.
  static Future<void> show(
    BuildContext context,
    CoordinatorDetailsCubit Function() create,
  ) => BullDialog.show<void>(
    context: context,
    padding: EdgeInsets.zero,
    builder: (_) => BlocProvider(
      create: (_) => create()..load(),
      child: const CoordinatorDetailsDialog(),
    ),
  );

  @override
  State<CoordinatorDetailsDialog> createState() =>
      _CoordinatorDetailsDialogState();
}

/// The sections that open and close below the details, one at a time as in the official client.
enum _Section { policies, summary, stats }

class _CoordinatorDetailsDialogState extends State<CoordinatorDetailsDialog> {
  _Section? _expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<CoordinatorDetailsCubit>().state;
    final coordinator = state.coordinator;
    final info = switch (state.info) {
      CoordinatorInfoLoaded(:final info) => info,
      _ => null,
    };
    final origin = coordinator.origins(state.network).onion;
    final onion = origin == null ? null : CoordinatorText.value(origin);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            CoordinatorText.of(
              coordinator.longAlias,
              maxCodePoints: CoordinatorText.name,
            ),
            textAlign: TextAlign.center,
            style: text.displaySmall?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.sm),
          Center(child: RobotAvatar(seed: coordinator.shortAlias, size: 96)),
          const Gap(BullSpacing.xs),
          Text(
            CoordinatorText.of(
              coordinator.motto,
              maxCodePoints: CoordinatorText.line,
            ),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: colors.text,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Gap(BullSpacing.xs),
          CoordinatorContacts(contact: coordinator.contact),
          if (info != null && info.noticeSeverity != NoticeSeverity.none) ...[
            const Gap(BullSpacing.sm),
            CoordinatorNotice(info: info),
          ],
          const Gap(BullSpacing.md),
          CoordinatorBadgesRow(
            badges: coordinator.badges,
            sizeLimit: state.sizeLimit,
          ),
          const Gap(BullSpacing.sm),
          CoordinatorDetailRow(
            icon: Icons.description,
            value: CoordinatorText.of(
              coordinator.description,
              maxCodePoints: CoordinatorText.paragraph,
            ),
            caption: l10n.p2pCoordinatorDescription,
          ),
          CoordinatorDetailRow(
            icon: Icons.flag,
            value: MaterialLocalizations.of(
              context,
            ).formatCompactDate(coordinator.establishedOn),
            caption: l10n.p2pCoordinatorEstablished,
          ),
          if (onion != null)
            CoordinatorDetailRow(
              icon: Icons.web,
              value: onion,
              caption: l10n.p2pCoordinatorHostedWebApp,
              onTap: () => CoordinatorLinkSheet.show(
                context,
                title: l10n.p2pCoordinatorHostedWebApp,
                value: onion,
              ),
            ),
          const Gap(BullSpacing.sm),
          ...switch (state.info) {
            CoordinatorInfoLoading() => [
              Center(child: CircularProgressIndicator(color: colors.primary)),
            ],
            CoordinatorInfoLoaded(:final info) => [
              _section(
                _Section.policies,
                l10n.p2pCoordinatorPolicies,
                CoordinatorPolicies(policies: coordinator.policies),
              ),
              _section(
                _Section.summary,
                l10n.p2pCoordinatorSummary,
                CoordinatorSummary(
                  info: info,
                  badges: coordinator.badges,
                  sizeLimit: state.sizeLimit,
                ),
              ),
              _section(
                _Section.stats,
                l10n.p2pCoordinatorStatsForNerds,
                CoordinatorStats(info: info),
              ),
            ],
            CoordinatorInfoFailed() => [
              Text(
                l10n.p2pCoordinatorOffline,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(color: colors.error),
              ),
              // Not in the official client, which reads the info again with the whole federation: Troc asks here.
              Center(
                child: TextButton(
                  onPressed: context.read<CoordinatorDetailsCubit>().retry,
                  child: Text(
                    l10n.p2pCommonRetry,
                    style: text.labelLarge?.copyWith(color: colors.primary),
                  ),
                ),
              ),
            ],
          },
        ],
      ),
    );
  }

  Widget _section(_Section section, String title, Widget child) =>
      CoordinatorSection(
        title: title,
        expanded: _expanded == section,
        onToggle: () =>
            setState(() => _expanded = _expanded == section ? null : section),
        child: child,
      );
}

/// A section of the dialog that opens on a tap of its title.
class CoordinatorSection extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const CoordinatorSection({
    super.key,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: BullSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(BullSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: text.bodyLarge?.copyWith(color: colors.text),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BullSpacing.md,
                0,
                BullSpacing.md,
                BullSpacing.md,
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// One line of the dialog: an icon, a value, and a caption under it, as the official client's list items.
class CoordinatorDetailRow extends StatelessWidget {
  final IconData? icon;

  /// The value as plain text, unless [valueWidget] is given.
  final String value;
  final Widget? valueWidget;
  final String? caption;
  final Color? valueColor;

  /// Shows the link of the row in full, when it has one.
  final VoidCallback? onTap;

  const CoordinatorDetailRow({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.valueColor,
    this.onTap,
  }) : valueWidget = null;

  /// A row whose value is [valueWidget], such as the two fees side by side.
  const CoordinatorDetailRow.custom({
    super.key,
    required this.icon,
    required Widget this.valueWidget,
    this.caption,
  }) : value = '',
       valueColor = null,
       onTap = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final onTap = this.onTap;
    final caption = this.caption;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: icon == null
                ? null
                : Icon(icon, size: 22, color: colors.textMuted),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                valueWidget ??
                    Text(
                      value,
                      style: text.bodyLarge?.copyWith(
                        color:
                            valueColor ??
                            (onTap == null ? colors.text : colors.primary),
                      ),
                    ),
                if (caption != null)
                  Text(
                    caption,
                    style: text.labelMedium?.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// The contacts of the operator, in the order of the official client: Nostr, PGP, email, Telegram, X, Reddit, website, Matrix, Simplex.
///
/// Each one shows, on a tap, the value or the link the official client would open, to copy.
class CoordinatorContacts extends StatelessWidget {
  final CoordinatorContact contact;

  const CoordinatorContacts({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    // What is shown is what is copied: a contact without any visible character is left out.
    String? clean(String? value) => switch (value) {
      final value? => switch (CoordinatorText.value(value)) {
        final clean when clean.trim().isNotEmpty => clean,
        _ => null,
      },
      null => null,
    };
    final nostr = clean(contact.nostr);
    final fingerprint = clean(contact.fingerprint);
    final email = clean(contact.email);
    final telegram = clean(contact.telegram);
    final twitter = clean(contact.twitter);
    final reddit = clean(contact.reddit);
    final website = clean(contact.website);
    final matrix = clean(contact.matrix);
    final simplex = clean(contact.simplex);
    final entries = <(IconData, String, String)>[
      if (nostr != null) (Icons.hub_outlined, l10n.p2pCoordinatorNostr, nostr),
      if (clean(contact.pgp) != null && fingerprint != null)
        (
          Icons.key,
          l10n.p2pCoordinatorPgpFingerprint,
          groupFingerprint(fingerprint),
        ),
      if (email != null) (Icons.email, l10n.p2pCoordinatorSendEmail, email),
      if (telegram != null)
        (Icons.telegram, l10n.p2pCoordinatorTelegram, 'https://t.me/$telegram'),
      if (twitter != null)
        (Icons.alternate_email, l10n.p2pCoordinatorX, 'https://x.com/$twitter'),
      if (reddit != null)
        (Icons.reddit, l10n.p2pCoordinatorReddit, 'https://reddit.com/$reddit'),
      if (website != null)
        (Icons.language, l10n.p2pCoordinatorWebsite, website),
      if (matrix != null) (Icons.tag, l10n.p2pCoordinatorMatrix, matrix),
      if (simplex != null)
        (Icons.chat_bubble_outline, l10n.p2pCoordinatorSimplex, simplex),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, label, value) in entries)
          IconButton(
            tooltip: label,
            icon: Icon(icon, color: colors.text),
            onPressed: () =>
                CoordinatorLinkSheet.show(context, title: label, value: value),
          ),
      ],
    );
  }

  /// An OpenPGP fingerprint in groups of four characters, as the official client writes it; characters are code points, so a group never splits one.
  static String groupFingerprint(String fingerprint) {
    final runes = fingerprint.runes.toList();
    return [
      for (var i = 0; i < runes.length; i += 4)
        String.fromCharCodes(runes.skip(i).take(4)),
    ].join(' ');
  }
}

/// The notice of the coordinator, coloured by its severity: its text may contain HTML, which is shown as it is written.
class CoordinatorNotice extends StatelessWidget {
  final CoordinatorInfo info;

  const CoordinatorNotice({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final accent = switch (info.noticeSeverity) {
      NoticeSeverity.success => colors.success,
      NoticeSeverity.warning => colors.warning,
      NoticeSeverity.error => colors.error,
      NoticeSeverity.info || NoticeSeverity.none => colors.info,
    };
    return Container(
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.p2pCoordinatorNotice,
            style: text.bodyLarge?.copyWith(color: accent),
          ),
          if (info.noticeMessage.isNotEmpty) ...[
            const Gap(BullSpacing.xxs),
            Text(
              CoordinatorText.of(
                info.noticeMessage,
                maxCodePoints: CoordinatorText.notice,
              ),
              style: text.bodyMedium?.copyWith(color: colors.text),
            ),
          ],
        ],
      ),
    );
  }
}

/// The four badges of the official client, lit or greyed out, each with its explanation on a tap.
class CoordinatorBadgesRow extends StatelessWidget {
  final CoordinatorBadges badges;
  final CoordinatorSizeLimit sizeLimit;

  const CoordinatorBadgesRow({
    super.key,
    required this.badges,
    required this.sizeLimit,
  });

  /// The share of its proceeds from which a coordinator lights the badge of the development fund.
  static const devFundThreshold = 20;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final devFund = formats.number(badges.donatesToDevFund.toDouble());
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CoordinatorBadge(
          icon: Icons.workspace_premium,
          lit: badges.isFounder,
          explanation: badges.isFounder
              ? l10n.p2pCoordinatorBadgeFounder
              : l10n.p2pCoordinatorBadgeNotFounder,
        ),
        CoordinatorBadge(
          icon: Icons.volunteer_activism,
          lit: badges.donatesToDevFund >= devFundThreshold,
          explanation: l10n.p2pCoordinatorBadgeDevFund(devFund),
        ),
        CoordinatorBadge(
          icon: Icons.shield,
          lit: badges.hasGoodOpSec,
          explanation: badges.hasGoodOpSec
              ? l10n.p2pCoordinatorBadgeGoodOpsec
              : l10n.p2pCoordinatorBadgeOpsecCouldImprove,
        ),
        CoordinatorBadge(
          icon: Icons.trending_up,
          lit: sizeLimit.isLarge,
          explanation: sizeLimit.isLarge
              ? l10n.p2pCoordinatorBadgeLargeLimits
              : l10n.p2pCoordinatorBadgeNoLargeLimits,
        ),
      ],
    );
  }
}

/// One badge: lit in the primary colour, or greyed out.
class CoordinatorBadge extends StatelessWidget {
  final IconData icon;
  final bool lit;
  final String explanation;

  const CoordinatorBadge({
    super.key,
    required this.icon,
    required this.lit,
    required this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Tooltip(
      message: explanation,
      triggerMode: TooltipTriggerMode.tap,
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.xs),
        child: Icon(
          icon,
          size: 40,
          color: lit ? colors.primary : colors.outline,
        ),
      ),
    );
  }
}

/// The policies of the coordinator, numbered, title and text as the federation list writes them.
class CoordinatorPolicies extends StatelessWidget {
  final Map<String, String> policies;

  const CoordinatorPolicies({super.key, required this.policies});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, MapEntry(:key, :value)) in policies.entries.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BullSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${index + 1}',
                    style: text.bodyLarge?.copyWith(color: colors.textMuted),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CoordinatorText.of(
                          key,
                          maxCodePoints: CoordinatorText.line,
                        ),
                        style: text.bodyLarge?.copyWith(color: colors.text),
                      ),
                      Text(
                        CoordinatorText.of(
                          value,
                          maxCodePoints: CoordinatorText.paragraph,
                        ),
                        style: text.bodyMedium?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// « Summary »: the limits, fees, on-chain payouts, donation, book and premium of the coordinator, in the order of the official client.
class CoordinatorSummary extends StatelessWidget {
  final CoordinatorInfo info;
  final CoordinatorBadges badges;
  final CoordinatorSizeLimit sizeLimit;

  const CoordinatorSummary({
    super.key,
    required this.info,
    required this.badges,
    required this.sizeLimit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String sats(double sats) => l10n.p2pAmountSats(formats.satsAmount(sats));
    Widget fee(String value, String caption) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.bodyLarge?.copyWith(color: colors.text)),
          Text(
            caption,
            style: text.labelMedium?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
    final swapRate = info.currentSwapFeeRate;
    final divider = Divider(height: 1, color: colors.outlineVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoordinatorDetailRow(
          icon: Icons.circle,
          value: sats(sizeLimit.maxOrderSize(info)),
          caption: l10n.p2pCoordinatorMaxOrderSize,
        ),
        divider,
        CoordinatorDetailRow.custom(
          icon: Icons.percent,
          valueWidget: Row(
            children: [
              fee(formats.fee(info.makerFee), l10n.p2pOrderFeeMakerTooltip),
              fee(formats.fee(info.takerFee), l10n.p2pOrderFeeTakerTooltip),
            ],
          ),
        ),
        divider,
        if (!info.swapEnabled)
          CoordinatorDetailRow(
            icon: Icons.link,
            value: l10n.p2pOrderOnchainDisabled,
            valueColor: colors.error,
            caption: l10n.p2pCoordinatorOnchainStatus,
          )
        else ...[
          CoordinatorDetailRow(
            icon: Icons.link,
            // A coordinator that does not say its fee leaves it unknown: the official client would print 0.
            value: swapRate == null ? '-' : formats.swapFeeRate(swapRate),
            caption: l10n.p2pCoordinatorCurrentOnchainFee,
          ),
          CoordinatorDetailRow(
            icon: null,
            value: sats(sizeLimit.maxSwapSize(info)),
            caption: l10n.p2pCoordinatorMaxSwapSize,
          ),
        ],
        divider,
        CoordinatorDetailRow(
          icon: Icons.volunteer_activism,
          value: l10n.p2pCoordinatorDevFundPercent(
            formats.number(badges.donatesToDevFund.toDouble()),
          ),
          caption: l10n.p2pCoordinatorDevFundZaps,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.inventory,
          value: formats.count(info.numPublicBuyOrders),
          caption: l10n.p2pCoordinatorPublicBuyOrders,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.sell,
          value: formats.count(info.numPublicSellOrders),
          caption: l10n.p2pCoordinatorPublicSellOrders,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.book,
          value: sats(info.bookLiquidity.value.toDouble()),
          caption: l10n.p2pCoordinatorBookLiquidity,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.smart_toy,
          value: formats.count(info.activeRobotsToday),
          caption: l10n.p2pCoordinatorActiveRobotsToday,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.price_change,
          value: formats.nonKycPremium(info.lastDayNonKycBtcPremium),
          caption: l10n.p2pCoordinatorNonKycPremium,
        ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.api,
          value: CoordinatorText.of(
            info.marketPriceApis ?? '',
            maxCodePoints: CoordinatorText.paragraph,
          ),
          caption: l10n.p2pCoordinatorPriceSources,
        ),
      ],
    );
  }
}

/// « Stats for Nerds »: the versions, Lightning node, commit and volumes of the coordinator.
///
/// The node and the commit are links in the official client (1ML or Amboss, GitHub): here they show the link in full, to copy.
/// The commit is a link only when it is a commit id, so that the text of a coordinator cannot make it point elsewhere on GitHub.
class CoordinatorStats extends StatelessWidget {
  final CoordinatorInfo info;

  const CoordinatorStats({super.key, required this.info});

  /// How many characters of the node key and of the commit the official client shows before its ellipsis.
  static const shownPrefix = 12;

  /// A Git commit id, abbreviated or full, in lowercase hexadecimal.
  static final RegExp commitId = RegExp(r'^[0-9a-f]{7,40}$');

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final divider = Divider(height: 1, color: colors.outlineVariant);
    String? line(String? text) => text == null
        ? null
        : CoordinatorText.of(text, maxCodePoints: CoordinatorText.line);
    final lnd = line(info.lndVersion);
    final cln = line(info.clnVersion);
    final commit = switch (info.robosatsRunningCommitHash) {
      final hash? => CoordinatorText.value(hash).trim(),
      null => null,
    };
    final testnet = info.network == RobosatsNetwork.testnet;
    // The node id is 66 hexadecimal characters, checked when the info is read.
    final nodeLink = testnet
        ? 'https://1ml.com/testnet/node/${info.nodeId}'
        : 'https://amboss.space/node/${info.nodeId}';
    final nodeAlias = line(info.nodeAlias) ?? '';
    final nodeCaption = testnet
        ? l10n.p2pCoordinatorLnNodeAlias(nodeAlias)
        : nodeAlias;
    Widget volume(double btc) => Row(
      children: [
        Flexible(
          child: Text(
            formats.btc(btc),
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
        ),
        Icon(Icons.currency_bitcoin, size: 16, color: colors.textMuted),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoordinatorDetailRow(
          icon: Icons.smart_toy_outlined,
          value: l10n.p2pCoordinatorVersionValue(
            l10n.p2pCoordinatorVersionCoordinator,
            '${info.version}',
          ),
          caption: l10n.p2pCoordinatorRoboSatsVersion,
        ),
        divider,
        if (lnd != null)
          CoordinatorDetailRow(
            icon: Icons.bolt,
            value: lnd,
            caption: l10n.p2pCoordinatorLndVersion,
          ),
        if (cln != null && cln.isNotEmpty)
          CoordinatorDetailRow(
            icon: Icons.bolt,
            value: cln,
            caption: l10n.p2pCoordinatorClnVersion,
          ),
        divider,
        CoordinatorDetailRow(
          icon: Icons.dns,
          value: testnet
              ? l10n.p2pCoordinatorNode1ml(_prefix(info.nodeId))
              : l10n.p2pCoordinatorNodeAmboss(_prefix(info.nodeId)),
          caption: nodeCaption,
          onTap: () => CoordinatorLinkSheet.show(
            context,
            title: l10n.p2pCoordinatorLnNode,
            value: nodeLink,
          ),
        ),
        if (commit != null && commit.isNotEmpty) ...[
          divider,
          CoordinatorDetailRow(
            icon: Icons.code,
            value: l10n.p2pCoordinatorCommitShort(_prefix(commit)),
            caption: l10n.p2pCoordinatorCommitHash,
            onTap: commitId.hasMatch(commit)
                ? () => CoordinatorLinkSheet.show(
                    context,
                    title: l10n.p2pCoordinatorCommitHash,
                    value: 'https://github.com/Robosats/robosats/tree/$commit',
                  )
                : null,
          ),
        ],
        divider,
        CoordinatorDetailRow.custom(
          icon: Icons.equalizer,
          valueWidget: volume(info.lastDayVolume),
          caption: l10n.p2pCoordinatorVolume24h,
        ),
        divider,
        CoordinatorDetailRow.custom(
          icon: Icons.equalizer,
          valueWidget: volume(info.lifetimeVolume),
          caption: l10n.p2pCoordinatorVolumeLifetime,
        ),
      ],
    );
  }

  /// The first [shownPrefix] code points of [value], or all of it when shorter.
  static String _prefix(String value) =>
      String.fromCharCodes(value.runes.take(shownPrefix));
}
