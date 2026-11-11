import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../widgets/coordinator_link_sheet.dart';
import '../widgets/garage_key_clipboard.dart';
import '../widgets/garage_key_field.dart';
import '../widgets/garage_key_view.dart';
import '../widgets/robot_avatar.dart';
import 'account_navigator.dart';
import 'delete_garage_key_dialog.dart';

/// The address of the RoboSats documentation, which the official client opens from the third step.
const learnRoboSatsUrl = 'https://learn.robosats.org';

/// The public RoboSats support group on SimpleX, which the official client opens from the third step (`GarageKeyOnboarding.tsx` at commit ff1998c).
const simplexGroupUrl =
    r'https://simplex.chat/contact/#/?v=1-2&smp=smp%3A%2F%2F0YuTwO05YJWS8rkjn9eLJDjQhFKvIYd8d4xG8X1blIU%3D%40smp8.simplex.im%2FyEX_vdhWew_FkovCQC3mRYRWZB1j_cBq%23%2F%3Fv%3D1-2%26dh%3DMCowBQYDK2VuAyEAnrf9Jw3Ajdp4EQw71kqA64VgsIIzw8YNn68WjF09jFY%253D%26srv%3Dbeccx4yfxxbvyhqypaavemqurytl6hozr47wfc7uuecacjqdvwpw2xid.onion&data=%7B%22type%22%3A%22group%22%2C%22groupLinkId%22%3A%22hWnMVPnJl-KT3-virDk0JA%3D%3D%22%7D';

/// The three steps of the Garage Key wizard of the official client (`basic/GaragePage/GarageKeyOnboarding.tsx` at commit ff1998c), one below the other, the title of the step shown in full and the others greyed.
///
/// 1. The Garage Key: « Generate Garage Key » draws it in the vault, which stores it at once, and it is shown right after for backup, with the official client's alert, without asking the user to authenticate again.
/// The official client keeps a generated key in memory until « Continue », so pasting over it or « Generate new » replace it silently; here the key is stored as soon as it is drawn, so the field where a key is pasted comes before it is generated, and « Generate new » asks « Delete Garage Key? » first.
/// 2. The robot of the key, derived on the device, and the robot navigator; the official client also asks the coordinators about it, which Troc does not do yet.
/// 3. Browse or create: « Search » shows the offers, « Create » is disabled, and the help links are shown for copy, never opened.
class GarageWizard extends StatefulWidget {
  /// The step shown, from 1 to 3.
  final int step;

  final GarageState state;
  final GarageKeyClipboard clipboard;
  final ValueChanged<int> onStep;
  final VoidCallback onSearch;
  final VoidCallback onSeeProfile;

  const GarageWizard({
    super.key,
    required this.step,
    required this.state,
    required this.clipboard,
    required this.onStep,
    required this.onSearch,
    required this.onSeeProfile,
  });

  @override
  State<GarageWizard> createState() => _GarageWizardState();
}

class _GarageWizardState extends State<GarageWizard> {
  /// The key the user pastes in step 1, dropped with the wizard.
  final _pasted = TextEditingController();

  /// The link to the support group, inside the help sentence of step 3.
  late final _simplexLink = TapGestureRecognizer()
    ..onTap = () => CoordinatorLinkSheet.show(
      context,
      title: P2pLocalizations.of(context).p2pGarageOnboardingHelpLink,
      value: simplexGroupUrl,
    );

  @override
  void dispose() {
    _pasted.dispose();
    _simplexLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final state = widget.state;
    // Steps 2 and 3 need a key; without one the wizard is on its first step, and the first step shows a key only when it waits to be shown for backup.
    final step = switch (state) {
      GarageWithKey(showForBackup: true) => widget.step,
      GarageWithKey() => widget.step < 2 ? 2 : widget.step,
      _ => 1,
    };
    final titles = [
      l10n.p2pGarageOnboardingStep1Title,
      l10n.p2pGarageOnboardingStep2Title,
      l10n.p2pGarageOnboardingStep3Title,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, title) in titles.indexed) ...[
            _StepTitle(title: title, active: step == index + 1),
            if (step == index + 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: BullSpacing.sm),
                child: switch (step) {
                  1 => _keyStep(context, state),
                  2 => _robotStep(context, state),
                  _ => _browseStep(context),
                },
              ),
            const Gap(BullSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _keyStep(BuildContext context, GarageState state) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    final working = state is GarageWorking;
    final intro = Text(
      l10n.p2pGarageOnboardingStep1Text,
      style: text.bodyMedium?.copyWith(color: colors.text),
    );
    if (state case GarageWithKey(:final key, :final failure)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          intro,
          const Gap(BullSpacing.md),
          _StoreItAlert(
            title: l10n.p2pGarageOnboardingStoreItTitle,
            text: l10n.p2pGarageOnboardingStoreItText,
          ),
          const Gap(BullSpacing.md),
          GarageKeyView(garageKey: key.key, clipboard: widget.clipboard),
          const Gap(BullSpacing.xs),
          Text(
            l10n.p2pGarageKeyHelper,
            style: text.labelMedium?.copyWith(color: colors.textMuted),
          ),
          if (failure != null) _FailureLine(failure.toTranslated(context)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                if (await DeleteGarageKeyDialog.show(context)) {
                  await cubit.replace();
                }
              },
              icon: Icon(Icons.casino, color: colors.primary),
              label: Text(
                l10n.p2pGarageOnboardingGenerateNew,
                style: text.labelLarge?.copyWith(color: colors.primary),
              ),
            ),
          ),
          const Gap(BullSpacing.sm),
          BullButton.big(
            label: l10n.p2pCommonContinue,
            iconData: Icons.check,
            iconFirst: true,
            onPressed: () {
              cubit.acknowledgeBackup();
              widget.onStep(2);
            },
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ],
      );
    }
    final failure = switch (state) {
      GarageWithoutKey(:final failure?) => failure,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        intro,
        const Gap(BullSpacing.md),
        if (working)
          Center(child: CircularProgressIndicator(color: colors.primary))
        else
          BullButton.big(
            label: l10n.p2pGarageOnboardingGenerateKey,
            iconData: Icons.key,
            iconFirst: true,
            onPressed: cubit.generate,
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        if (failure != null) _FailureLine(failure.toTranslated(context)),
        const Gap(BullSpacing.lg),
        Text(
          l10n.p2pGarageOnboardingPasteExisting,
          style: text.bodyMedium?.copyWith(color: colors.text),
        ),
        const Gap(BullSpacing.sm),
        GarageKeyField(
          controller: _pasted,
          label: l10n.p2pGarageKeyLabel,
          helper: l10n.p2pGarageKeyHelper,
          enabled: !working,
        ),
        const Gap(BullSpacing.md),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _pasted,
          builder: (context, value, _) => BullButton.big(
            label: l10n.p2pCommonContinue,
            iconData: Icons.check,
            iconFirst: true,
            disabled:
                working ||
                value.text.isEmpty ||
                garageKeyTextError(value.text, l10n) != null,
            onPressed: () => _importPasted(cubit),
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ),
      ],
    );
  }

  /// Stores the pasted key, then moves on to the robot, as « Continue » does in the official client.
  Future<void> _importPasted(GarageCubit cubit) async {
    await cubit.import(_pasted.text);
    if (!mounted || cubit.state is! GarageWithKey) return;
    _pasted.clear();
    widget.onStep(2);
  }

  Widget _robotStep(BuildContext context, GarageState state) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    if (state is! GarageWithKey) return const SizedBox.shrink();
    final robot = state.robot;
    return Column(
      children: [
        Text(
          l10n.p2pGarageTradingAvatar,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.text),
        ),
        const Gap(BullSpacing.sm),
        RobotAvatar(
          seed: robot.hashId,
          size: 160,
          semanticLabel: l10n.p2pGarageTradingAvatar,
        ),
        const Gap(BullSpacing.sm),
        Text(
          l10n.p2pGarageHiMyNameIs,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.text),
        ),
        RobotNickname(nickname: robot.nickname),
        AccountNavigator(
          index: robot.index,
          onPrevious: cubit.previous,
          onNext: cubit.next,
        ),
        if (state.failure case final failure?)
          _FailureLine(failure.toTranslated(context)),
        const Gap(BullSpacing.sm),
        BullButton.big(
          label: l10n.p2pCommonContinue,
          iconData: Icons.check,
          iconFirst: true,
          onPressed: () => widget.onStep(3),
          bgColor: colors.primary,
          textColor: colors.onPrimary,
        ),
      ],
    );
  }

  Widget _browseStep(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final words = text.bodyMedium?.copyWith(color: colors.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.p2pGarageOnboardingStep3Text, style: words),
        const Gap(BullSpacing.md),
        Row(
          children: [
            Expanded(
              child: BullButton.big(
                label: l10n.p2pCommonSearch,
                iconData: Icons.search,
                iconFirst: true,
                onPressed: widget.onSearch,
                bgColor: colors.primary,
                textColor: colors.onPrimary,
              ),
            ),
            const Gap(BullSpacing.sm),
            Expanded(
              child: BullButton.big(
                label: l10n.p2pNavCreate,
                iconData: Icons.add_box,
                iconFirst: true,
                onPressed: () {},
                disabled: true,
                bgColor: colors.secondary,
                textColor: colors.onSecondary,
              ),
            ),
          ],
        ),
        const Gap(BullSpacing.md),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${l10n.p2pGarageOnboardingHelpIntro} '),
              TextSpan(
                text: l10n.p2pGarageOnboardingHelpLink,
                recognizer: _simplexLink,
                style: TextStyle(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
              TextSpan(text: ', ${l10n.p2pGarageOnboardingHelpOutro}'),
            ],
          ),
          style: words,
        ),
        const Gap(BullSpacing.sm),
        BullButton.big(
          label: l10n.p2pGarageLearnRoboSats,
          iconData: Icons.school,
          iconFirst: true,
          onPressed: () => CoordinatorLinkSheet.show(
            context,
            title: l10n.p2pGarageLearnRoboSats,
            value: learnRoboSatsUrl,
          ),
          outlined: true,
          bgColor: colors.transparent,
          textColor: colors.text,
          borderColor: colors.outline,
        ),
        const Gap(BullSpacing.sm),
        Center(
          child: TextButton(
            onPressed: widget.onSeeProfile,
            child: Text(
              l10n.p2pGarageSeeProfile,
              style: text.labelLarge?.copyWith(color: colors.text),
            ),
          ),
        ),
      ],
    );
  }
}

/// The title of a step: in full when it is the step shown, greyed otherwise.
class _StepTitle extends StatelessWidget {
  final String title;
  final bool active;

  const _StepTitle({required this.title, required this.active});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
        color: active ? colors.text : colors.textMuted,
      ),
    );
  }
}

/// « Store it somewhere safe! » and why, the alert the official client shows with a new key.
class _StoreItAlert extends StatelessWidget {
  final String title;
  final String text;

  const _StoreItAlert({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Container(
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        border: Border.all(color: colors.info),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.info),
          const Gap(BullSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: style?.copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// The nickname of a robot in bold between two bolts, as the official client draws it.
class RobotNickname extends StatelessWidget {
  final String nickname;

  const RobotNickname({super.key, required this.nickname});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(Icons.bolt, color: colors.bitcoinOrange)),
        Flexible(
          child: Text(
            nickname,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ExcludeSemantics(child: Icon(Icons.bolt, color: colors.bitcoinOrange)),
      ],
    );
  }
}

/// A failure of the last action, in red, under what it concerns.
class _FailureLine extends StatelessWidget {
  final String message;

  const _FailureLine(this.message);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: BullSpacing.sm),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.bull.error),
    ),
  );
}
