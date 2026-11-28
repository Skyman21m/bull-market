import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'moved_tap_guard.dart';
import 'trade_button.dart';
import 'word_fit_text.dart';

/// The body of a dialog of the official client in the wallet's look: its title, its text, then its two buttons, the one that goes back first and the one that goes on second, as the reference lays them out from left to right (`DialogActions`).
///
/// The button that goes on is the filled one, unless [backFirst]: then the one that goes back is filled and the other outlined, as a dialog whose going on loses something (« Go back » / « Confirm Cancel » at 6 and 7, `TradeBox/Dialogs/ConfirmCancel.tsx`, where « Go back » has the focus).
///
/// The buttons are stacked, each the dialog's width, so that a long French label at three times the text size wraps instead of overflowing on a phone of 320 points; the whole body scrolls.
class TradeDialogBody extends StatelessWidget {
  final String title;
  final String text;
  final String backLabel;
  final VoidCallback onBack;
  final String goLabel;

  /// The reference's warning under its text, in the warning colour and bold (« ⚠️ This action cannot be undone! », `TradeBox/Dialogs/ConfirmFiatSent.tsx`), and the reference's text after it; `null` for a dialog without them.
  final String? warning;
  final String? afterWarning;

  /// The reference's list under [afterWarning], one line per item with its bullet (`Dialogs/ConfirmFiatReceived.tsx`: `Box component='ul'`); empty for a dialog without one.
  final List<String> bullets;

  /// A line of the app under the reference's text, when there is something the user should know before going on (a payment of the bond on its way); `null` otherwise.
  final String? note;

  /// Lines of the app under [note] (#182: the owner's payment rule on the buyer's side, the gap from the creation's rate), each in the colour of its [TradeDialogTone]; empty for a dialog without them.
  final List<TradeDialogLine> lines;

  /// Lines of the app said first, under the title, each in the colour of its [TradeDialogTone]: the alerts the screen shows behind the dialog (security review of #219, C2); empty for a dialog without them.
  final List<TradeDialogLine> alerts;

  /// The reference's field under everything said, above the buttons (« Back it up! » of « Store your garage key », #318); `null` for a dialog without one.
  final Widget? field;

  /// What the button that goes on does; `null` while it waits (« Wait ({{time}}) », `TradeBox/Dialogs/ConfirmUndoFiatSent.tsx`).
  final VoidCallback? onGo;

  /// Whether the button that goes back is the emphasized, filled one.
  final bool backFirst;

  /// Whether a tap on the button that goes on is ignored for a moment just after it was shown or the layout moved it ([MovedTapGuard]): for a dialog whose [lines] or [alerts] follow a state while it is open, so that a line that comes or goes can bring that button under a tap aimed at the one that goes back (« Confirm … sent », #283), for the seller's « Confirm … received », which releases the escrow (#293), and for the dialogs whose button that goes on a second tap on the button that opened them can reach as they open, with a large text or on a small screen: « Confirm Cancel » at 6 and 7, which loses the bond, « Confirm cancellation », « Ask for Cancel » or « Accept Cancelation », and « Renew anyway » (#298); and for « Agree and open dispute », which settles the escrow and both bonds at once, though no second tap was seen reaching it (#301).
  final bool guardsGo;

  /// What a screen reader reads of the button that goes on, when it differs from its label (« Wait 42 seconds »), and whether its changes are announced (« Confirm » once a wait ends).
  final String? goSemanticLabel;
  final bool goLive;

  /// What a screen reader reads of the title and of the warning, when they differ from them (a text that starts with an emoji, whose name it would read first); `null` for the text itself.
  final String? semanticTitle;
  final String? semanticWarning;

  const TradeDialogBody({
    super.key,
    required this.title,
    required this.text,
    required this.backLabel,
    required this.onBack,
    required this.goLabel,
    required this.onGo,
    this.backFirst = false,
    this.guardsGo = false,
    this.goSemanticLabel,
    this.goLive = false,
    this.semanticTitle,
    this.semanticWarning,
    this.warning,
    this.afterWarning,
    this.bullets = const [],
    this.note,
    this.lines = const [],
    this.alerts = const [],
    this.field,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            label: semanticTitle,
            excludeSemantics: semanticTitle != null,
            child: WordFitText(
              title,
              style: styles.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          for (final line in alerts) ...[
            const Gap(BullSpacing.sm),
            _lineText(context, line),
          ],
          const Gap(BullSpacing.md),
          WordFitText(
            text,
            style: styles.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          if (warning case final warning?) ...[
            const Gap(BullSpacing.md),
            Semantics(
              container: true,
              label: semanticWarning,
              excludeSemantics: semanticWarning != null,
              child: WordFitText(
                warning,
                style: styles.bodyMedium?.copyWith(
                  color: colors.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          if (afterWarning case final after?) ...[
            const Gap(BullSpacing.md),
            WordFitText(
              after,
              style: styles.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ],
          for (final bullet in bullets) ...[
            const Gap(BullSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The list's bullet, which a screen reader does not read.
                ExcludeSemantics(
                  child: Text(
                    '•',
                    style: styles.bodyMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
                const Gap(BullSpacing.sm),
                Expanded(
                  child: WordFitText(
                    bullet,
                    style: styles.bodyMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ],
          if (note case final note?) ...[
            const Gap(BullSpacing.sm),
            WordFitText(
              note,
              style: styles.bodyMedium?.copyWith(color: colors.text),
            ),
          ],
          for (final line in lines) ...[
            const Gap(BullSpacing.sm),
            _lineText(context, line),
          ],
          if (field case final field?) ...[const Gap(BullSpacing.md), field],
          const Gap(BullSpacing.lg),
          TradeButton(
            label: backLabel,
            onPressed: onBack,
            outlined: !backFirst,
          ),
          const Gap(BullSpacing.sm),
          Semantics(
            liveRegion: goLive,
            child: guardsGo
                ? MovedTapGuard(
                    builder: (context, guard) => TradeButton(
                      label: goLabel,
                      onPressed: guard(onGo),
                      outlined: backFirst,
                      semanticLabel: goSemanticLabel,
                    ),
                  )
                : TradeButton(
                    label: goLabel,
                    onPressed: onGo,
                    outlined: backFirst,
                    semanticLabel: goSemanticLabel,
                  ),
          ),
        ],
      ),
    );
  }

  /// [line] in the colour of its tone, bold unless plain.
  static Widget _lineText(BuildContext context, TradeDialogLine line) {
    final colors = context.bull;
    return WordFitText(
      line.text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: switch (line.tone) {
          TradeDialogTone.plain => colors.text,
          TradeDialogTone.warning ||
          TradeDialogTone.warningLine => colors.warning,
          TradeDialogTone.alert || TradeDialogTone.alertFigures => colors.error,
        },
        fontWeight: switch (line.tone) {
          TradeDialogTone.warning || TradeDialogTone.alert => FontWeight.bold,
          TradeDialogTone.plain ||
          TradeDialogTone.alertFigures ||
          TradeDialogTone.warningLine => null,
        },
      ),
    );
  }
}

/// How a line of the app in a dialog is drawn: in the text colour, in the warning colour (a gap against the user, a check that could not be made), or in the error colour (the red warning of the owner's rule).
enum TradeDialogTone {
  plain,
  warning,
  alert,

  /// The second line of a red alert, its two figures (the owner's two-line alerts, validated on 2026-11-24, #250): the alert's colour, not bold.
  alertFigures,

  /// A line under an orange alert, its second line or its explanation where no detail holds it (#237): the warning colour, not bold.
  warningLine,
}

/// A line of the app in a dialog, and its tone.
typedef TradeDialogLine = ({String text, TradeDialogTone tone});

/// Lines a dialog builds from the state of the moment it opens ([of], with the dialog's own context), and builds again at each event of [changes] while it is open: never the lines of a build before (security review of #208, C1); [alerts], built the same way, are said first, under the title (security review of #219, C2).
@immutable
final class LiveDialogLines {
  final List<TradeDialogLine> Function(BuildContext context) of;
  final List<TradeDialogLine> Function(BuildContext context)? alerts;
  final Stream<Object?> changes;

  const LiveDialogLines({required this.of, required this.changes, this.alerts});
}
