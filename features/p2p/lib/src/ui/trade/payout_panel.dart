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
import '../widgets/order_detail_row.dart';
import '../widgets/trade_button.dart';

/// What the trade screen gives the payout panel of the status it shows.
@immutable
final class PayoutPanelRequest {
  final TradeRecord record;

  /// The status shown, with the order it was read from.
  final TradeSeen seen;

  /// Whether [seen] is marked stored (`TradeSeen.stored`): otherwise nothing can be checked or sent from it.
  final bool stored;

  /// The long alias of the trade's coordinator, for the texts.
  final String coordinator;

  /// The screen's clock, for the countdown of a failed payout's next attempt.
  final DateTime now;

  const PayoutPanelRequest({
    required this.record,
    required this.seen,
    required this.stored,
    required this.coordinator,
    required this.now,
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

/// The official client's payout prompt (`TradeBox/Prompts/Payout.tsx`, `Forms/LightningPayout.tsx`, `Forms/OnchainPayout.tsx`, and at 15 `Prompts/RoutingFailed.tsx`, commit ff1998c) in the wallet's look (#91).
///
/// At 6 and 8: the tabs « Lightning » and « Onchain », « Onchain » disabled when the coordinator offers no swap (with the reason it gave, which the reference does not show) or for an order in bitcoin. « Lightning »: « Advanced options » and its « Routing Budget », « Submit invoice for {{amountSats}} Sats » with the amount `SubmitPayoutUsecase.ask` gives and its copy, the field « Payout Lightning Invoice » with « Paste », what the check read of it (amount, expiry, network, the warnings) or why it cannot be given, and « Submit ». « Onchain »: the swap's text, its fees and « Final amount you will receive », the fields « Bitcoin Address » and « Mining Fee », and « Submit ».
/// At 15, a failed payout: the reason and the next attempt, or, once the invoice expired, the reference's text and the Lightning tab alone.
/// « Submit » gives the cubit the payout shown, once; while it is given, each wait says what it waits for, and after 30 s that it still waits; what it gave is said under « Submit », and the trade's screen is asked to read the order again.
/// The robot's key is held while the panel is shown with the app in the foreground and its tab visible, and let go otherwise.
/// [wallet] fills the slot of the wallet's address and invoice (#90): `null` today, and the slot draws nothing.
class PayoutPanel extends StatefulWidget {
  final PayoutPanelRequest request;
  final PayoutWalletBuilder? wallet;

  /// Asks the trade's watch to read now, once a payout given told something.
  final VoidCallback onTold;

  const PayoutPanel({
    super.key,
    required this.request,
    required this.onTold,
    this.wallet,
  });

  /// How long a payout may be given before the panel says it still waits, as the take does.
  static const stillWaitingAfter = Duration(seconds: 30);

  @override
  State<PayoutPanel> createState() => _PayoutPanelState();
}

class _PayoutPanelState extends State<PayoutPanel> with WidgetsBindingObserver {
  PayoutKind _kind = PayoutKind.lightning;
  String _invoice = '';
  String _address = '';

  /// The mining fee rate typed, the coordinator's suggestion until the user changes it (`Forms/OnchainPayout.tsx:48-50`).
  String? _fee;

  bool _advanced = false;
  bool _budgetInSats = false;
  String _budgetText = '${RoutingBudgetPpm.referenceDefault.ppm}';
  RoutingBudgetPpm _budget = RoutingBudgetPpm.referenceDefault;

  /// Whether the app is in the foreground and the panel's tab of the shell is shown.
  bool _foreground = true;
  bool _tickerEnabled = true;

  Timer? _stillWaiting;
  bool _waitedLong = false;
  bool _copied = false;

  /// Whether a payout was being given at the last state: its end is when it told something.
  bool _wasSending = false;

  /// The coordinator's suggested rate as text, the mining fee's value until the user types one.
  String? _suggestedFee;

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
    _stillWaiting?.cancel();
    _cubit.release();
    super.dispose();
  }

  void _onState(BuildContext context, PayoutPanelState state) {
    final sending = state.phase is PayoutSending;
    if (sending && _stillWaiting == null) {
      _stillWaiting = Timer(PayoutPanel.stillWaitingAfter, () {
        if (mounted) setState(() => _waitedLong = true);
      });
    }
    if (!sending) {
      _stillWaiting?.cancel();
      _stillWaiting = null;
      _waitedLong = false;
    }
    // Once a payout given told something, the trade's watch reads at once, so that what follows is shown as soon as the coordinator tells it.
    if (_wasSending && !sending) {
      if (state.phase case PayoutEditing(:final notice?)
          when notice is! PayoutNoticeNotSent ||
              notice.refusal is PayoutNoLongerValid) {
        widget.onTold();
      }
    }
    _wasSending = sending;
  }

  /// The mining fee typed, or the coordinator's suggestion until one is typed.
  String get _feeText => _fee ?? _suggestedFee ?? '';

  void _setInvoice(String text) {
    setState(() => _invoice = text);
    _cubit.checkInvoice(text, _budget);
  }

  void _setAddress(String text) {
    setState(() => _address = text);
    _cubit.checkAddress(text, _rateOf(_feeText));
  }

  void _setFee(String text) {
    setState(() => _fee = text);
    _cubit.checkAddress(_address, _rateOf(text));
  }

  static MiningFeeRate? _rateOf(String? text) {
    final value = double.tryParse((text ?? '').trim().replaceAll(',', '.'));
    return value == null ? null : MiningFeeRate.of(value);
  }

  /// The budget typed, in ppm or in sats of [buyerSats], taken only while it is under 99,999 ppm, as the reference takes it (`Forms/LightningPayout.tsx:289-307`).
  void _setBudget(String text, Sats buyerSats) {
    setState(() => _budgetText = text);
    final value = int.tryParse(text);
    if (value == null) return;
    final buyer = buyerSats.value.toInt();
    final ppm = _budgetInSats
        ? (buyer == 0 ? null : (value * 1000000 / buyer).round())
        : value;
    final budget = ppm == null ? null : RoutingBudgetPpm.of(ppm);
    if (budget == null) return;
    setState(() => _budget = budget);
    _cubit.checkInvoice(_invoice, budget);
  }

  /// The unit of the budget switched, the field showing the budget in the other unit (`Forms/LightningPayout.tsx:403-410`, `:300`).
  void _switchBudgetUnit(Sats asked) {
    setState(() {
      _budgetInSats = !_budgetInSats;
      _budgetText = _budgetInSats
          ? '${(asked.value.toInt() / 1000000 * _budget.ppm).ceil()}'
          : '${_budget.ppm}';
    });
  }

  /// « Advanced options » off brings the reference's default budget back (`Forms/LightningPayout.tsx:229-243`).
  void _setAdvanced(bool on) {
    setState(() {
      _advanced = on;
      if (!on) {
        _budget = RoutingBudgetPpm.referenceDefault;
        _budgetInSats = false;
        _budgetText = '${RoutingBudgetPpm.referenceDefault.ppm}';
      }
    });
    if (!on) _cubit.checkInvoice(_invoice, _budget);
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
    switch (kind) {
      case PayoutKind.lightning:
        _setInvoice(text);
      case PayoutKind.onchain:
        _setAddress(text);
    }
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
      listenWhen: (before, after) => before.phase != after.phase,
      listener: _onState,
      builder: (context, state) {
        final status = request.seen.status;
        // 15 before the invoice expired: the coordinator retries; nothing to give yet.
        if (status case RoutingFailed(invoiceExpired: false)) {
          return _RetryView(
            status: status,
            now: request.now,
            coordinator: request.coordinator,
          );
        }
        final newInvoice = status is RoutingFailed;
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
            switch (state.ask) {
              null => const SizedBox.shrink(),
              Err(:final failure) => _Text(
                failure.toText(context, coordinator: request.coordinator),
                muted: true,
              ),
              Ok(value: final ask) => _form(context, state, ask, newInvoice),
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
    final colors = context.bull;
    final onchain = ask.onchain;
    // A tab whose option the coordinator withdrew falls back to Lightning.
    final kind = onchain == null ? PayoutKind.lightning : _kind;
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
            onSelected: (item) => setState(
              () => _kind = item == l10n.p2pPayoutTabOnchain
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
            use: switch (kind) {
              PayoutKind.lightning => _setInvoice,
              PayoutKind.onchain => _setAddress,
            },
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
        ..._outcome(context, state, kind, colors),
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
    final asked = ask.invoiceSatsFor(_budget);
    final budgetPpm = _budget.ppm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Text(l10n.p2pPayoutAdvancedOptions)),
            BullSwitch(value: _advanced, onChanged: _setAdvanced),
          ],
        ),
        if (_advanced) ...[
          const Gap(BullSpacing.sm),
          _Label(l10n.p2pPayoutRoutingBudget),
          Row(
            children: [
              Expanded(
                child: BullInputText(
                  value: _budgetText,
                  onChanged: (text) => _setBudget(text, ask.buyerSats),
                  digitsOnly: true,
                  maxLength: 9,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              TextButton(
                onPressed: asked == null
                    ? null
                    : () => _switchBudgetUnit(asked),
                child: Text(
                  _budgetInSats ? l10n.p2pSatsUnit : l10n.p2pPayoutUnitPpm,
                  style: TextStyle(color: colors.primary),
                ),
              ),
            ],
          ),
          if (budgetPpm > 10000)
            _Text(l10n.p2pPayoutBudgetTooHigh, color: colors.warning),
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
        _Label(l10n.p2pPayoutInvoiceField),
        BullInputText(
          value: _invoice,
          onChanged: _setInvoice,
          hint: l10n.p2pPayoutInvoiceField,
          maxLines: 4,
          maxLength: 2100,
          autocorrect: false,
          enableSuggestions: false,
          rightIcon: Tooltip(
            message: l10n.p2pCommonPaste,
            child: Icon(Icons.content_paste, color: colors.primary),
          ),
          onRightTap: () => _paste(PayoutKind.lightning),
        ),
        ..._check(context, state, PayoutKind.lightning),
        const Gap(BullSpacing.md),
        _submit(context, state, PayoutKind.lightning),
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
    final suggested = onchain.suggestedSatPerVbyte;
    // Without grouping, so that the text reads back as a number.
    _suggestedFee = suggested == null
        ? null
        : NumberFormat('0.###', l10n.localeName).format(suggested);
    final rate = _rateOf(_feeText);
    final sent = rate == null ? null : onchain.sentSatsFor(rate);
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
                formats.sats(onchain.swapFeeSats),
                number.format(onchain.swapFeePercent),
              ),
            ),
            if (rate != null)
              OrderDetailRow(
                l10n.p2pPayoutMiningFee,
                l10n.p2pPayoutMiningFeeValue(
                  formats.sats(onchain.miningFeeSatsFor(rate)),
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
        _Label(l10n.p2pPayoutAddressField),
        BullInputText(
          value: _address,
          onChanged: _setAddress,
          hint: l10n.p2pPayoutAddressField,
          maxLines: 2,
          maxLength: 100,
          autocorrect: false,
          enableSuggestions: false,
          rightIcon: Tooltip(
            message: l10n.p2pCommonPaste,
            child: Icon(Icons.content_paste, color: colors.primary),
          ),
          onRightTap: () => _paste(PayoutKind.onchain),
        ),
        const Gap(BullSpacing.sm),
        _Label(l10n.p2pPayoutMiningFeeField),
        BullInputText(
          value: _feeText,
          onChanged: _setFee,
          onlyNumbers: true,
          maxLength: 10,
          autocorrect: false,
          enableSuggestions: false,
        ),
        if (rate == null) _Text(l10n.p2pPayoutInvalid, color: colors.error),
        ..._check(context, state, PayoutKind.onchain),
        const Gap(BullSpacing.md),
        _submit(context, state, PayoutKind.onchain),
      ],
    );
  }

  /// What the check of [kind]'s text gave: why it cannot be given, or, for an invoice, what was read of it (amount, expiry, network), and the warnings.
  List<Widget> _check(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final formats = P2pFormats.of(context);
    final coordinator = widget.request.coordinator;
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
        if (payout case CheckedPayoutInvoice(
          :final amount,
          :final expiresAt,
          :final network,
        )) ...[
          const Gap(BullSpacing.sm),
          BullDetailsTable(
            items: [
              OrderDetailRow(
                l10n.p2pBookColumnAmount,
                l10n.p2pAmountSats(formats.sats(amount.value.toInt())),
              ),
              OrderDetailRow(
                l10n.p2pTradeInvoiceExpires,
                DateFormat.yMd(
                  l10n.localeName,
                ).add_Hms().format(expiresAt.toLocal()),
              ),
              OrderDetailRow(l10n.p2pTradeInvoiceNetwork, switch (network) {
                RobosatsNetwork.mainnet => l10n.p2pTradeNetworkMainnet,
                RobosatsNetwork.testnet => l10n.p2pTradeNetworkTestnet,
              }),
            ],
          ),
        ],
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
    return TradeButton(
      label: l10n.p2pPayoutSubmit,
      busy: sending,
      onPressed: state.submittable(kind) == null
          ? null
          : () => unawaited(_cubit.submit(kind)),
    );
  }

  /// What a payout being given waits for, and what the last one gave.
  List<Widget> _outcome(
    BuildContext context,
    PayoutPanelState state,
    PayoutKind kind,
    BullTheme colors,
  ) {
    final l10n = P2pLocalizations.of(context);
    final coordinator = widget.request.coordinator;
    return switch (state.phase) {
      PayoutSending(:final step) => [
        const Gap(BullSpacing.sm),
        _Text(
          step.toText(context, coordinator: coordinator),
          center: true,
          live: true,
        ),
        const Gap(BullSpacing.xs),
        LinearProgressIndicator(color: colors.primary),
        if (_waitedLong) ...[
          const Gap(BullSpacing.xs),
          _Text(
            l10n.p2pRobotStillWaiting(coordinator),
            center: true,
            muted: true,
            live: true,
          ),
        ],
      ],
      PayoutEditing(:final notice?) when notice.kind == kind => [
        const Gap(BullSpacing.sm),
        _Text(
          notice.toText(context, coordinator: coordinator),
          center: true,
          live: true,
          color: switch (notice) {
            PayoutNoticeGiven() => colors.success,
            PayoutNoticeUnknown() => colors.warning,
            PayoutNoticeNotSent(refusal: PayoutChangedSinceShown()) =>
              colors.warning,
            PayoutNoticeNotTaken() || PayoutNoticeNotSent() => colors.error,
          },
        ),
      ],
      PayoutEditing() => const [],
    };
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

/// The label above a field.
class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: BullSpacing.xs),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: context.bull.textMuted),
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
