import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_payout.dart';
import '../../domain/trade/trade_payout_outcome.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_cubit.dart';
import '../../presentation/payout_l10n.dart';
import '../widgets/coordinator_link_sheet.dart';
import '../widgets/order_detail_row.dart';
import '../widgets/trade_button.dart';
import 'bond_panel.dart';

/// What the trade screen gives the payout panel of the status it shows.
@immutable
final class PayoutPanelRequest {
  final TradeRecord record;

  /// The status shown, with the order it was read from: the panel's cubit decides from it what can be checked and sent (only from a status marked stored, `SubmitPayoutUsecase.ask`).
  final TradeSeen seen;

  /// The long alias of the trade's coordinator, for the texts.
  final String coordinator;

  /// The screen's clock, for the countdown of a failed payout's next attempt.
  final DateTime now;

  /// Whether a cancel of the trade runs: « Submit » is off meanwhile, as « Cancel » is while a payout is given.
  final bool cancelling;

  const PayoutPanelRequest({
    required this.record,
    required this.seen,
    required this.coordinator,
    required this.now,
    this.cancelling = false,
  });
}

/// Builds the payout panel of [request]: the route gives it, with the panel's cubit.
typedef PayoutPanelBuilder =
    Widget Function(BuildContext context, PayoutPanelRequest request);

/// What the wallet's slot of a tab is given: the trade, what the coordinator asks, the tab, and [use], which puts a text in the tab's field, where it is checked as a pasted one.
@immutable
final class PayoutWalletRequest {
  final TradeRecord record;
  final PayoutAsk ask;
  final PayoutKind kind;
  final ValueChanged<String> use;

  const PayoutWalletRequest({
    required this.record,
    required this.ask,
    required this.kind,
    required this.use,
  });
}

/// Fills the slot of « Use a new address of this wallet » and « Create an invoice in this wallet » (#90, the wallet's port), or returns `null`, and the slot draws nothing.
typedef PayoutWalletBuilder =
    Widget? Function(BuildContext context, PayoutWalletRequest request);

/// Calls [onTold] once a payout given told something ([PayoutPanelState.toldBetween]): the route puts it around the trade screen, so that it hears it whichever tab is shown, and asks the trade's watch to read at once.
class PayoutTold extends StatelessWidget {
  final VoidCallback onTold;
  final Widget child;

  const PayoutTold({super.key, required this.onTold, required this.child});

  @override
  Widget build(BuildContext context) =>
      BlocListener<PayoutCubit, PayoutPanelState>(
        listenWhen: PayoutPanelState.toldBetween,
        listener: (context, state) => onTold(),
        child: child,
      );
}

/// The official client's payout prompt (`TradeBox/Prompts/Payout.tsx`, `Forms/LightningPayout.tsx`, `Forms/OnchainPayout.tsx`, and at 15 `Prompts/RoutingFailed.tsx`, commit ff1998c) in the wallet's look (#91).
///
/// At 6 and 8: the tabs « Lightning » and « Onchain », « Onchain » disabled when the coordinator offers no swap (with the reason it gave, which the reference does not show) or for an order in bitcoin. « Lightning »: « Advanced options » and its « Routing Budget », « Submit invoice for {{amountSats}} Sats » with the amount `SubmitPayoutUsecase.ask` gives and its copy, the field « Payout Lightning Invoice » with « Paste », what the check read of it (amount, expiry, network, the warnings) or why it cannot be given, and « Submit ». « Onchain »: the swap's text, its fees and « Final amount you will receive », the fields « Bitcoin Address » and « Mining Fee », the address checked, and « Submit ».
/// At 15, a failed payout: the reason and the next attempt, or, once the invoice expired, the reference's text and the Lightning tab alone.
/// Everything typed or chosen lives in the cubit ([PayoutForm]): a panel built again (another tab of the trade, a line added above it) shows exactly what is checked, and the figures of what « Submit » gives are the check's own.
/// « Submit » gives the cubit the payout shown, once; while it is given, each wait says what it waits for, and after 30 s that it still waits; what it gave is said under « Submit », a refusal of the coordinator under the field, as the reference's helper text.
/// The robot's key is held while the panel is shown with the app in the foreground and its tab visible, and let go otherwise.
/// [wallet] fills the slot of the wallet's address and invoice (#90): `null` today, and the slot draws nothing.
class PayoutPanel extends StatefulWidget {
  final PayoutPanelRequest request;
  final PayoutWalletBuilder? wallet;

  const PayoutPanel({super.key, required this.request, this.wallet});

  /// The keys of the fields, for the tests.
  static const invoiceField = ValueKey('payout-invoice');
  static const addressField = ValueKey('payout-address');
  static const feeField = ValueKey('payout-mining-fee');
  static const budgetField = ValueKey('payout-routing-budget');

  @override
  State<PayoutPanel> createState() => _PayoutPanelState();
}

class _PayoutPanelState extends State<PayoutPanel> with WidgetsBindingObserver {
  /// The fields' texts, kept equal to the cubit's form ([_sync]): the cubit is their only source.
  final _invoice = TextEditingController();
  final _address = TextEditingController();
  final _fee = TextEditingController();
  final _budget = TextEditingController();

  /// Whether the app is in the foreground and the panel's tab of the shell is shown.
  bool _foreground = true;
  bool _tickerEnabled = true;

  bool _copied = false;

  late final PayoutCubit _cubit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cubit = context.read<PayoutCubit>();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    _cubit.show(widget.request.seen);
  }

  @override
  void didUpdateWidget(PayoutPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request.seen, widget.request.seen)) {
      _cubit.show(widget.request.seen);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _keepKey();
    _sync(_cubit.state);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _foreground = false;
      case AppLifecycleState.resumed:
        _foreground = true;
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        return;
    }
    _keepKey();
  }

  /// The key held while the panel is shown, the app in the foreground and the tab visible; let go otherwise.
  void _keepKey() {
    if (_foreground && _tickerEnabled) {
      _cubit.hold();
    } else {
      _cubit.release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.release();
    _invoice.dispose();
    _address.dispose();
    _fee.dispose();
    _budget.dispose();
    super.dispose();
  }

  /// The mining fee's text: the coordinator's suggestion taken once, as it sent it, or what the user typed ([PayoutForm.fee]).
  String _feeText(PayoutPanelState state) => state.form.fee ?? '';

  /// Each field's text made the form's: a text the user did not type there (pasted, the `lightning:` prefix taken off, a budget refused, a panel built again) replaces it, the cursor at the start of an invoice or an address, as the reference puts it after a paste (`Forms/LightningPayout.tsx:321-330`), at the end of a number.
  void _sync(PayoutPanelState state) {
    void set(TextEditingController field, String text, {required bool start}) {
      if (field.text == text) return;
      field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start ? 0 : text.length),
      );
    }

    final form = state.form;
    set(_invoice, form.invoice, start: true);
    set(_address, form.address, start: true);
    set(_budget, form.budgetText, start: false);
    set(_fee, _feeText(state), start: false);
  }

  /// [change] made to the cubit's form, then the fields made the form's (a change refused leaves the form as it was).
  void _edit(void Function() change) {
    change();
    if (mounted) _sync(_cubit.state);
  }

  /// Reads the clipboard once, on the user's tap, into the field of [kind].
  Future<void> _paste(PayoutKind kind) async {
    final ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } on Exception {
      return;
    }
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    _edit(
      () => switch (kind) {
        PayoutKind.lightning => _cubit.editInvoice(text),
        PayoutKind.onchain => _cubit.editAddress(text),
      },
    );
  }

  /// Copies the amount asked, as the reference's copy beside « Submit invoice for … » does (`Forms/LightningPayout.tsx:565-576`).
  Future<void> _copyAmount(Sats asked) async {
    try {
      await Clipboard.setData(ClipboardData(text: '${asked.value}'));
    } on Exception {
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final request = widget.request;
    return BlocConsumer<PayoutCubit, PayoutPanelState>(
      listenWhen: (before, after) =>
          !identical(before.form, after.form) ||
          !identical(before.ask, after.ask),
      listener: (context, state) => _sync(state),
      builder: (context, state) {
        final status = (state.seen ?? request.seen).status;
        // 15 before the invoice expired: the coordinator retries; nothing to give yet.
        if (status case RoutingFailed(invoiceExpired: false)) {
          return _RetryView(
            status: status,
            now: request.now,
            coordinator: request.coordinator,
          );
        }
        final newInvoice =
            status is RoutingFailed || (state.shownAsk?.isNewInvoice ?? false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (status case RoutingFailed(:final reason)) ...[
              _Text(l10n.p2pPayoutInvoiceExpiredSubmitNew),
              if (reason != null) ...[
                const Gap(BullSpacing.sm),
                _FailureReason(
                  reason.toText(context, coordinator: request.coordinator),
                ),
              ],
              const Gap(BullSpacing.md),
            ],
            // Under a payout received or that may have been, its form and what it told stay, whatever a later read says is asked (review of #132).
            switch ((state.shownAsk, state.ask)) {
              (final ask?, _) => _form(context, state, ask, newInvoice),
              (null, Err(:final failure)) => _Text(
                failure.toText(context, coordinator: request.coordinator),
                muted: true,
              ),
              (null, _) => const SizedBox.shrink(),
            },
          ],
        );
      },
    );
  }

  Widget _form(
    BuildContext context,
    PayoutPanelState state,
    PayoutAsk ask,
    bool newInvoice,
  ) {
    final l10n = P2pLocalizations.of(context);
    final onchain = ask.onchain;
    // A tab whose option the coordinator withdrew falls back to Lightning.
    final kind = onchain == null ? PayoutKind.lightning : state.form.kind;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!newInvoice) ...[
          BullSegmented(
            items: {l10n.p2pPayoutTabLightning, l10n.p2pPayoutTabOnchain},
            initialValue: kind == PayoutKind.lightning
                ? l10n.p2pPayoutTabLightning
                : l10n.p2pPayoutTabOnchain,
            disabledItems: {if (onchain == null) l10n.p2pPayoutTabOnchain},
            onSelected: (item) => _cubit.selectKind(
              item == l10n.p2pPayoutTabOnchain
                  ? PayoutKind.onchain
                  : PayoutKind.lightning,
            ),
          ),
          if (onchain == null) ...[
            const Gap(BullSpacing.xs),
            _Text(
              ask.isSwapOrder
                  ? l10n.p2pPayoutOnchainSwapOrder
                  : ask.onchainRefusal.toText(
                      context,
                      coordinator: widget.request.coordinator,
                    ),
              muted: true,
              small: true,
            ),
          ],
          const Gap(BullSpacing.md),
        ],
        ?widget.wallet?.call(
          context,
          PayoutWalletRequest(
            record: widget.request.record,
            ask: ask,
            kind: kind,
            use: (text) => _edit(
              () => switch (kind) {
                PayoutKind.lightning => _cubit.editInvoice(text),
                PayoutKind.onchain => _cubit.editAddress(text),
              },
            ),
          ),
        ),
        switch ((kind, onchain)) {
          (PayoutKind.onchain, final onchain?) => _onchain(
            context,
            state,
            onchain,
          ),
          _ => _lightning(context, state, ask),
        },
      ],
    );
  }

  Widget _lightning(
    BuildContext context,
    PayoutPanelState state,
    PayoutAsk ask,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final formats = P2pFormats.of(context);
    final form = state.form;
    final editable = state.phase is PayoutEditing && !state.outcomeTold;
    final asked = ask.invoiceSatsFor(form.budget);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The switch named by its text for a screen reader.
        MergeSemantics(
          child: Row(
            children: [
              Expanded(child: _Text(l10n.p2pPayoutAdvancedOptions)),
              BullSwitch(
                value: form.advanced,
                onChanged: editable
                    ? (on) => _edit(() => _cubit.setAdvanced(on))
                    : null,
              ),
            ],
          ),
        ),
        if (form.advanced) ...[
          const Gap(BullSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Field(
                  label: l10n.p2pPayoutRoutingBudget,
                  field: BullInputText(
                    uiKey: PayoutPanel.budgetField,
                    controller: _budget,
                    value: form.budgetText,
                    onChanged: (text) => _edit(() => _cubit.editBudget(text)),
                    disabled: !editable,
                    digitsOnly: true,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
              ),
              TextButton(
                onPressed: asked == null || !editable
                    ? null
                    : () => _edit(_cubit.switchBudgetUnit),
                child: Text(
                  form.budgetInSats ? l10n.p2pSatsUnit : l10n.p2pPayoutUnitPpm,
                  style: TextStyle(color: colors.primary),
                ),
              ),
            ],
          ),
          // The reference's helper text, in red under the field (`Forms/LightningPayout.tsx:389-390`).
          if (form.budget.ppm > 10000)
            _Text(
              l10n.p2pPayoutBudgetTooHigh,
              color: colors.error,
              small: true,
            ),
        ],
        const Gap(BullSpacing.md),
        if (asked != null)
          Row(
            children: [
              Expanded(
                child: _Text(
                  l10n.p2pPayoutSubmitInvoiceFor(
                    formats.sats(asked.value.toInt()),
                  ),
                  center: true,
                ),
              ),
              IconButton(
                tooltip: _copied
                    ? l10n.p2pCommonCopied
                    : l10n.p2pPayoutCopyAmount,
                onPressed: () => _copyAmount(asked),
                icon: Icon(
                  _copied ? Icons.check : Icons.content_copy,
                  size: 20,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        if (_copied) _Text(l10n.p2pCommonCopied, center: true, live: true),
        const Gap(BullSpacing.sm),
        _Field(
          label: l10n.p2pPayoutInvoiceField,
          onPaste: editable ? () => _paste(PayoutKind.lightning) : null,
          field: BullInputText(
            uiKey: PayoutPanel.invoiceField,
            controller: _invoice,
            value: form.invoice,
            onChanged: (text) => _edit(() => _cubit.editInvoice(text)),
            disabled: !editable,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        ..._refused(context, state, PayoutKind.lightning),
        ..._check(context, state, PayoutKind.lightning),
        const Gap(BullSpacing.md),
        _submit(context, state, PayoutKind.lightning),
        ..._outcome(context, state, PayoutKind.lightning),
        // The reference's wallets button under the Lightning form (`Forms/LightningPayout.tsx:658-660`), its link shown for copy as in the bond panel.
        const Gap(BullSpacing.sm),
        TradeButton(
          label: l10n.p2pTradeCompatibleWallets,
          icon: Icons.account_balance_wallet_outlined,
          outlined: true,
          onPressed: () => CoordinatorLinkSheet.show(
            context,
            title: l10n.p2pTradeCompatibleWallets,
            value: BondPanel.compatibleWallets,
          ),
        ),
      ],
    );
  }

  Widget _onchain(
    BuildContext context,
    PayoutPanelState state,
    OnchainAsk onchain,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final formats = P2pFormats.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final form = state.form;
    final editable = state.phase is PayoutEditing && !state.outcomeTold;
    // What « Submit » gives, once the address is checked: its own figures; before, the reference's preview from the rate of the form (`Forms/OnchainPayout.tsx:66-101`), the same rate the check uses.
    final checked = switch (state.address) {
      Ok(value: final CheckedPayoutAddress payout) => payout,
      _ => null,
    };
    final rate = checked?.rate ?? state.rate;
    final swapFee = checked?.swapFeeSats ?? onchain.swapFeeSats;
    final swapPercent = checked?.swapFeePercent ?? onchain.swapFeePercent;
    final miningFee =
        checked?.miningFeeSats ??
        (rate == null ? null : onchain.miningFeeSatsFor(rate));
    final sent =
        checked?.sentSats ?? (rate == null ? null : onchain.sentSatsFor(rate));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Text(l10n.p2pPayoutOnchainIntro),
        const Gap(BullSpacing.sm),
        BullDetailsTable(
          items: [
            OrderDetailRow(
              l10n.p2pPayoutSwapFee,
              l10n.p2pPayoutSwapFeeValue(
                formats.sats(swapFee),
                number.format(swapPercent),
              ),
            ),
            if (rate != null && miningFee != null)
              OrderDetailRow(
                l10n.p2pPayoutMiningFee,
                l10n.p2pPayoutMiningFeeValue(
                  formats.sats(miningFee),
                  number.format(rate.satPerVbyte),
                ),
              ),
            if (sent != null)
              OrderDetailRow(
                l10n.p2pPayoutFinalAmount,
                l10n.p2pAmountSats(formats.sats(sent)),
              ),
          ],
        ),
        const Gap(BullSpacing.md),
        _Field(
          label: l10n.p2pPayoutAddressField,
          onPaste: editable ? () => _paste(PayoutKind.onchain) : null,
          field: BullInputText(
            uiKey: PayoutPanel.addressField,
            controller: _address,
            value: form.address,
            onChanged: (text) => _edit(() => _cubit.editAddress(text)),
            disabled: !editable,
            maxLines: 2,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        ..._refused(context, state, PayoutKind.onchain),
        const Gap(BullSpacing.sm),
        _Field(
          label: l10n.p2pPayoutMiningFeeField,
          field: BullInputText(
            uiKey: PayoutPanel.feeField,
            controller: _fee,
            value: _feeText(state),
            onChanged: (text) => _edit(() => _cubit.editFee(text)),
            disabled: !editable,
            onlyNumbers: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        if (state.rate == null)
          _Text(l10n.p2pPayoutInvalid, color: colors.error, small: true),
        ..._check(context, state, PayoutKind.onchain),
        const Gap(BullSpacing.md),
        _submit(context, state, PayoutKind.onchain),
        ..._outcome(context, state, PayoutKind.onchain),
      ],
    );
  }

  /// The coordinator's refusal of the last payout of [kind]'s tab, in red under its field, as the reference's helper text (`Forms/LightningPayout.tsx:602-619`, `Forms/OnchainPayout.tsx:114-118`).
  List<Widget> _refused(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
  ) => switch (state.phase) {
    PayoutEditing(notice: final PayoutNoticeNotTaken notice)
        when notice.kind == kind && notice.byCoordinator =>
      [
        const Gap(BullSpacing.xs),
        _Text(
          notice.toText(context, coordinator: widget.request.coordinator),
          color: context.bull.error,
          small: true,
          live: true,
        ),
      ],
    _ => const [],
  };

  /// What the check of [kind]'s text gave: why it cannot be given, or what « Submit » gives: for an invoice what was read of it (amount, expiry, network), for an address the address checked and its network, and the warnings.
  List<Widget> _check(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final formats = P2pFormats.of(context);
    final coordinator = widget.request.coordinator;
    String network(RobosatsNetwork network) => switch (network) {
      RobosatsNetwork.mainnet => l10n.p2pTradeNetworkMainnet,
      RobosatsNetwork.testnet => l10n.p2pTradeNetworkTestnet,
    };
    return switch (state.checkOf(kind)) {
      null => const [],
      Err(:final failure) => [
        const Gap(BullSpacing.xs),
        _Text(
          failure.toText(context, coordinator: coordinator),
          color: colors.error,
          live: true,
        ),
      ],
      Ok(value: final payout) => [
        const Gap(BullSpacing.sm),
        BullDetailsTable(
          items: switch (payout) {
            CheckedPayoutInvoice(:final amount, :final expiresAt) => [
              OrderDetailRow(
                l10n.p2pBookColumnAmount,
                l10n.p2pAmountSats(formats.sats(amount.value.toInt())),
              ),
              OrderDetailRow(
                l10n.p2pTradeInvoiceExpires,
                '${payoutExpiryDate(context, expiresAt)} '
                '${payoutExpiryTime(context, expiresAt)}',
              ),
              OrderDetailRow(
                l10n.p2pTradeInvoiceNetwork,
                network(payout.network),
              ),
            ],
            CheckedPayoutAddress(:final text) => [
              OrderDetailRow(l10n.p2pPayoutAddressField, text),
              OrderDetailRow(
                l10n.p2pTradeInvoiceNetwork,
                network(payout.network),
              ),
            ],
          },
        ),
        for (final warning in payout.warnings) ...[
          const Gap(BullSpacing.xs),
          _Text(
            warning.toText(context, coordinator: coordinator, payout: payout),
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ],
    };
  }

  Widget _submit(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
  ) {
    final l10n = P2pLocalizations.of(context);
    final sending = switch (state.phase) {
      PayoutSending(kind: final sent) => sent == kind,
      PayoutEditing() => false,
    };
    final cancelling = widget.request.cancelling;
    // The payout this frame shows: the tap gives it, and the cubit sends it only if it is still the one offered (no frame between what is drawn and what is sent).
    final payout = state.submittable(kind);
    final button = TradeButton(
      label: l10n.p2pPayoutSubmit,
      busy: sending,
      onPressed: cancelling || payout == null
          ? null
          : () => unawaited(_cubit.submit(kind, shown: payout)),
    );
    return cancelling
        ? Tooltip(message: l10n.p2pPayoutSubmitWhileCancelling, child: button)
        : button;
  }

  /// Under « Submit »: what a payout being given waits for, and what the last one of [kind]'s tab gave (a refusal of the coordinator aside, said under the field).
  List<Widget> _outcome(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final coordinator = widget.request.coordinator;
    return switch (state.phase) {
      PayoutSending(kind: final sent, :final step, :final waitedLong)
          when sent == kind =>
        [
          const Gap(BullSpacing.sm),
          _Text(
            step.toText(context, coordinator: coordinator),
            center: true,
            live: true,
          ),
          const Gap(BullSpacing.xs),
          LinearProgressIndicator(
            color: colors.primary,
            semanticsLabel: step.toText(context, coordinator: coordinator),
          ),
          if (waitedLong) ...[
            const Gap(BullSpacing.xs),
            _Text(
              l10n.p2pRobotStillWaiting(coordinator),
              center: true,
              muted: true,
              live: true,
            ),
          ],
        ],
      PayoutEditing(notice: PayoutNoticeNotTaken(byCoordinator: true)) =>
        const [],
      PayoutEditing(:final notice?) when notice.kind == kind => [
        const Gap(BullSpacing.sm),
        _Text(
          notice.toText(context, coordinator: coordinator),
          center: true,
          live: true,
          color: switch (notice) {
            PayoutNoticeGiven() => colors.success,
            PayoutNoticeUnknown() || PayoutNoticeAskedAgain() => colors.warning,
            PayoutNoticeNotSent(refusal: PayoutChangedSinceShown()) =>
              colors.warning,
            PayoutNoticeNotTaken() || PayoutNoticeNotSent() => colors.error,
          },
        ),
      ],
      _ => const [],
    };
  }
}

/// A field with its label above it, merged with it for a screen reader, which reads the label as the field's name; « Paste » beside the label, so that it keeps a node of its own.
class _Field extends StatelessWidget {
  final String label;
  final Widget field;
  final VoidCallback? onPaste;

  const _Field({required this.label, required this.field, this.onPaste});

  /// The side of « Paste ».
  static const double _pasteSize = 40;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final onPaste = this.onPaste;
    final named = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // With « Paste », the label's line is as tall as the button beside it, so that the button stays above the field.
          _Label(
            label,
            end: onPaste == null ? 0 : _pasteSize,
            minHeight: onPaste == null ? 0 : _pasteSize,
          ),
          field,
        ],
      ),
    );
    if (onPaste == null) return named;
    return Stack(
      children: [
        named,
        PositionedDirectional(
          top: 0,
          end: 0,
          child: IconButton(
            tooltip: l10n.p2pCommonPaste,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: _pasteSize,
              height: _pasteSize,
            ),
            onPressed: onPaste,
            icon: Icon(Icons.content_paste, size: 20, color: colors.primary),
          ),
        ),
      ],
    );
  }
}

/// 15 before the invoice expired: the reason, the reference's text, and the next attempt's countdown (`Prompts/RoutingFailed.tsx:120-152`).
class _RetryView extends StatelessWidget {
  final RoutingFailed status;
  final DateTime now;
  final String coordinator;

  const _RetryView({
    required this.status,
    required this.now,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final reason = status.reason;
    final next = status.nextAttempt;
    final left = next?.difference(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reason != null) ...[
          _FailureReason(reason.toText(context, coordinator: coordinator)),
          const Gap(BullSpacing.sm),
        ],
        _Text(l10n.p2pPayoutWillRetry),
        const Gap(BullSpacing.md),
        _Text(l10n.p2pPayoutNextAttempt, center: true, bold: true),
        const Gap(BullSpacing.xs),
        if (left == null || left <= Duration.zero) ...[
          _Text(l10n.p2pPayoutRetrying, center: true),
          const Gap(BullSpacing.xs),
          Center(child: CircularProgressIndicator(color: colors.primary)),
        ] else
          _Text(
            l10n.p2pPayoutCountdown(
              left.inMinutes.toString().padLeft(2, '0'),
              (left.inSeconds % 60).toString().padLeft(2, '0'),
            ),
            center: true,
          ),
      ],
    );
  }
}

/// « Failure reason: » and the reason, in a box (`Prompts/RoutingFailed.tsx:22-43`).
class _FailureReason extends StatelessWidget {
  final String reason;

  const _FailureReason(this.reason);

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return Container(
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.textMuted),
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Text(l10n.p2pPayoutFailureReason, center: true, bold: true),
          _Text(reason, center: true),
        ],
      ),
    );
  }
}

/// The label above a field; [end] leaves room for a button beside it, [minHeight] makes its line as tall as that button.
class _Label extends StatelessWidget {
  final String text;
  final double end;
  final double minHeight;

  const _Label(this.text, {this.end = 0, this.minHeight = 0});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(bottom: BullSpacing.xs, end: end),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: context.bull.textMuted),
        ),
      ),
    ),
  );
}

/// A line of the panel; [live] read out when it appears.
class _Text extends StatelessWidget {
  final String text;
  final Color? color;
  final bool muted;
  final bool center;
  final bool bold;
  final bool small;
  final bool live;
  final IconData? icon;

  const _Text(
    this.text, {
    this.color,
    this.muted = false,
    this.center = false,
    this.bold = false,
    this.small = false,
    this.live = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final theme = Theme.of(context).textTheme;
    final style = (small ? theme.bodySmall : theme.bodyMedium)?.copyWith(
      color: color ?? (muted ? colors.textMuted : colors.onSurface),
      fontWeight: bold ? FontWeight.w700 : null,
    );
    final icon = this.icon;
    final line = Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: style,
    );
    return Semantics(
      container: live,
      liveRegion: live,
      child: icon == null
          ? line
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: style?.color),
                const Gap(BullSpacing.xs),
                Expanded(child: line),
              ],
            ),
    );
  }
}
