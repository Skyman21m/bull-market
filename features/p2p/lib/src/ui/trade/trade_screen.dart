import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/p2p_failure.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_cubit.dart';
import '../../presentation/trade_l10n.dart';
import '../../presentation/trade_panel.dart';
import '../coordinator_details_dialog.dart';
import '../widgets/testnet_banner.dart';
import '../widgets/trade_button.dart';
import 'bond_panel.dart';
import 'cancel_order_dialog.dart';
import 'confirm_cancel_dialog.dart';
import 'trade_order_details.dart';
import 'wallet_payment_section.dart';

/// The page of one trade: the official client's order page of a participant on a phone (`basic/OrderPage/index.tsx` at commit ff1998c), the tabs « Order » and « Contract », « Contract » open first, in the wallet's look.
///
/// « Contract » is the reference's `TradeBox` for the status the trade's watch gives ([TradeView]): its title with the step, its prompt, its bond line and « Copy URL » / « Cancel » with their dialogs; « Order » is the order as its coordinator describes it to the robot ([TradeOrderDetails]), with « Expires in », « Deposit » and the bar.
/// A message of the coordinator that the reference shows alone (1043, 1044) is shown alone, and an order public again alone, with no contract, as the reference shows it to a robot that is no participant.
/// What the reference has no screen for (a take whose answer is unknown, records that cannot be read…) is a line of the app, with no action.
///
/// The screen follows the trade through its [TradeCubit]: shown or not by the ticker mode of its route (the tab of the shell hidden, another tab shown), read now when the app comes back from a short absence, the watch stopped while the app is hidden or paused and started again on its return.
/// It names no coordinator member and no money member: it calls the cubit only.
class TradeScreen extends StatefulWidget {
  final DateTime Function() now;

  /// Builds the cubit of the coordinator dialog.
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// What fills the slot of « Pay with this wallet » of the bond panel: `null` today (see [WalletPaymentSection]).
  final WalletPaymentBuilder? walletPayment;

  const TradeScreen({
    super.key,
    required this.now,
    required this.coordinatorDetails,
    this.walletPayment,
  });

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> with WidgetsBindingObserver {
  late DateTime _now;

  /// Moves the countdown on, every second as in the official client.
  Timer? _ticker;

  /// Whether the « Order » tab is shown rather than « Contract ».
  bool _orderTab = false;

  /// What the screen last told the watch: shown or not.
  bool? _shown;

  /// Whether the watch was stopped because the app was hidden or paused.
  bool _suspended = false;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = widget.now()),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown == _shown) return;
    final first = _shown == null;
    _shown = shown;
    // The watch starts as shown; only a change is told.
    if (first && shown) return;
    context.read<TradeCubit>().signal(
      shown ? TradeWatchSignal.onScreen : TradeWatchSignal.offScreen,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = context.read<TradeCubit>();
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        if (_suspended) return;
        _suspended = true;
        unawaited(cubit.suspend());
      case AppLifecycleState.resumed:
        if (_suspended) {
          _suspended = false;
          cubit.resume();
        } else {
          cubit.signal(TradeWatchSignal.readNow);
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<TradeCubit>().state;
    final record = state.record;
    final view = TradeView.of(state.watch);
    final coordinator = _coordinatorName(state);
    final lines = _lines(context, state, coordinator);
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (record.network == RobosatsNetwork.testnet)
              const TestnetBanner(),
            const Gap(BullSpacing.xs),
            BullTopBar(
              title: l10n.p2pNavOrder,
              onBack: () {
                if (context.canPop()) context.pop();
              },
            ),
            if (view is TradeContract)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: BullSpacing.md),
                child: BullSegmented(
                  items: {l10n.p2pNavOrder, l10n.p2pTradeTabContract},
                  initialValue: _orderTab
                      ? l10n.p2pNavOrder
                      : l10n.p2pTradeTabContract,
                  onSelected: (item) =>
                      setState(() => _orderTab = item == l10n.p2pNavOrder),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(BullSpacing.md),
                children: [
                  for (final line in lines) ...[
                    line,
                    const Gap(BullSpacing.sm),
                  ],
                  switch (view) {
                    TradeWaiting() => Padding(
                      padding: const EdgeInsets.all(BullSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(color: colors.primary),
                      ),
                    ),
                    TradeMessage(:final kind) => _Message(
                      text: kind.toText(context, coordinator: coordinator),
                      waits: kind == TradeMessageKind.takePending,
                    ),
                    TradeOrderOnly(:final order) => TradeOrderDetails(
                      order: order,
                      now: _now,
                      onOpenCoordinator: () => _openCoordinator(order),
                    ),
                    TradeContract(:final order?) when _orderTab =>
                      TradeOrderDetails(
                        order: order,
                        now: _now,
                        onOpenCoordinator: () => _openCoordinator(order),
                      ),
                    TradeContract() when _orderTab => Padding(
                      padding: const EdgeInsets.all(BullSpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(color: colors.primary),
                      ),
                    ),
                    final TradeContract contract => _Contract(
                      contract: contract,
                      record: record,
                      cancel: state.cancel,
                      coordinator: coordinator,
                      walletPayment: widget.walletPayment,
                    ),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCoordinator(CoordinatorOrder order) =>
      CoordinatorDetailsDialog.show(
        context,
        () => widget.coordinatorDetails(
          CoordinatorDetailsRequest(order.coordinator, order.network),
        ),
      );

  /// The long alias of the trade's coordinator, from its last read or the federation list, else its short alias as recorded.
  static String _coordinatorName(TradeScreenState state) {
    final known =
        state.seen?.order?.coordinator ??
        Federation.robosats.byAlias(state.record.coordinatorAlias);
    return CoordinatorText.of(
      known?.longAlias ?? state.record.coordinatorAlias,
      maxCodePoints: CoordinatorText.name,
    );
  }

  /// The lines above the panel the watch asks for (#87): reads that keep failing, the last status kept with its time; a write of the records that failed.
  List<Widget> _lines(
    BuildContext context,
    TradeScreenState state,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final watch = state.watch;
    final problem = switch (watch) {
      TradeWatchStatus(:final recordProblem) => recordProblem,
      TradeWatchTakeNeverSent(:final recordProblem) => recordProblem,
      _ => null,
    };
    return [
      if (watch case TradeWatchStatus(
        :final failedReads,
        :final seen,
      ) when failedReads >= 3)
        _Line(
          l10n.p2pTradeReadsFailing(
            coordinator,
            DateFormat.Hm(l10n.localeName).format(seen.status.seenAt.toLocal()),
          ),
          color: colors.warning,
        ),
      if (problem != null)
        _Line(
          problem is TradeClosedFailure
              ? l10n.p2pTradeClosedProblem(coordinator)
              : l10n.p2pTradeRecordProblem,
          color: colors.warning,
        ),
    ];
  }
}

/// A message shown alone, as the official client shows the coordinator's message on the order page; [waits] adds the bar of a wait.
class _Message extends StatelessWidget {
  final String text;
  final bool waits;

  const _Message({required this.text, required this.waits});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: colors.secondary),
            ),
          ),
          if (waits) ...[
            const Gap(BullSpacing.md),
            LinearProgressIndicator(color: colors.primary),
          ],
        ],
      ),
    );
  }
}

/// The contract of a status: title and step, the warnings, the prompt, the bond line, and « Copy URL » / « Cancel » where the reference offers them.
class _Contract extends StatelessWidget {
  final TradeContract contract;
  final TradeRecord record;
  final TradeCancelState cancel;
  final String coordinator;
  final WalletPaymentBuilder? walletPayment;

  const _Contract({
    required this.contract,
    required this.record,
    required this.cancel,
    required this.coordinator,
    required this.walletPayment,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final status = contract.status;
    final title = contract.title.toText(
      context,
      bondSats: switch (status) {
        WaitingForTakerBond(:final bond) => formats.sats(
          bond.orderAmount.value.toInt(),
        ),
        _ => '',
      },
    );
    final step = contract.step;
    final warnings = warningsOf(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          child: Text(
            step == null
                ? title
                : '$title ${l10n.p2pTradeStep('${step.$1}', '${step.$2}')}',
            textAlign: TextAlign.center,
            style: text.headlineLarge?.copyWith(
              color: contract.title == TradeTitle.finished
                  ? colors.success
                  : colors.primary,
            ),
          ),
        ),
        Divider(height: BullSpacing.lg, color: colors.outlineVariant),
        for (final warning in warnings) ...[
          _Line(
            warning.toText(context, coordinator: coordinator),
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const Gap(BullSpacing.sm),
        ],
        _prompt(context, status),
        if (contract.bondLine != TradeBondLine.hide) ...[
          const Gap(BullSpacing.md),
          _BondLine(line: contract.bondLine),
        ],
        if (contract.cancel != TradeCancelOffer.none) ...[
          const Gap(BullSpacing.md),
          _CancelRow(
            offer: contract.cancel,
            record: record,
            seen: contract.seen,
            cancel: cancel,
            coordinator: coordinator,
          ),
        ],
      ],
    );
  }

  Widget _prompt(BuildContext context, TradeStatus status) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final formats = P2pFormats.of(context);
    final order = contract.order;
    return switch ((contract.prompt, status)) {
      (TradePrompt.lockInvoice, final WaitingForTakerBond bond) => BondPanel(
        record: record,
        status: bond,
        walletPayment: walletPayment,
        payable: contract.payable,
      ),
      (TradePrompt.payout, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (order != null) ...[
            _Line(
              l10n.p2pTradePayoutPrompt(switch ((
                order.takenAmount,
                order.amount,
              )) {
                (final taken?, _) => formats.amount(taken),
                (null, FixedOrderAmount(:final amount)) => formats.amount(
                  amount,
                ),
                (null, final range) => formats.orderAmount(range),
              }, order.currency.code),
            ),
            const Gap(BullSpacing.sm),
          ],
          _Line(l10n.p2pTradePayoutLater, color: colors.textMuted),
        ],
      ),
      (TradePrompt.escrowWait, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pTradeEscrowWait),
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pTradeEscrowWaitHangOn),
        ],
      ),
      (TradePrompt.expired, Expired(:final reason?)) => _Line(
        reason.toText(context),
        center: true,
      ),
      (TradePrompt.expired, _) => const SizedBox.shrink(),
      _ => _Line(l10n.p2pTradeStepLater, color: colors.textMuted),
    };
  }
}

/// « Your taker bond is locked / unlocked / settled » with the reference's icons (`TradeBox/BondStatus.tsx`).
class _BondLine extends StatelessWidget {
  final TradeBondLine line;

  const _BondLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final (icon, color, label) = switch (line) {
      TradeBondLine.unlocked => (
        Icons.lock_open,
        colors.success,
        l10n.p2pTradeBondUnlocked,
      ),
      TradeBondLine.settled => (
        Icons.balance,
        colors.error,
        l10n.p2pTradeBondSettled,
      ),
      TradeBondLine.locked || TradeBondLine.hide => (
        Icons.lock,
        colors.primary,
        l10n.p2pTradeBondLocked,
      ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 18, color: color)),
        const Gap(BullSpacing.xs),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// « Copy URL » and « Cancel » (`TradeBox/CancelButton.tsx`): a free cancel asks « Cancel the order? » of the pre-take, one that loses the bond the confirmation that alone builds its acknowledgement.
class _CancelRow extends StatelessWidget {
  final TradeCancelOffer offer;
  final TradeRecord record;
  final TradeSeen seen;
  final TradeCancelState cancel;
  final String coordinator;

  const _CancelRow({
    required this.offer,
    required this.record,
    required this.seen,
    required this.cancel,
    required this.coordinator,
  });

  Future<void> _press(BuildContext context) async {
    final cubit = context.read<TradeCubit>();
    switch (offer) {
      case TradeCancelOffer.free:
        if (await CancelOrderDialog.show(context)) {
          await cubit.cancel(seen);
        }
      case TradeCancelOffer.losesBond:
        final acknowledged = await ConfirmCancelDialog.show(
          context,
          record: record,
          seen: seen,
        );
        if (acknowledged != null) {
          await cubit.cancel(seen, bondLoss: acknowledged);
        }
      case TradeCancelOffer.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final running = cancel is CancelRunning;
    final notice = switch (cancel) {
      CancelIdle(:final notice?) => notice,
      _ => null,
    };
    final url =
        '${record.coordinatorOnion}/order/${record.coordinatorAlias}/${record.orderId}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: l10n.p2pTradeCopyOrderUrl,
          child: TradeButton(
            label: l10n.p2pTradeCopyUrl,
            outlined: true,
            onPressed: () =>
                unawaited(Clipboard.setData(ClipboardData(text: url))),
          ),
        ),
        const Gap(BullSpacing.sm),
        Tooltip(
          message: offer == TradeCancelOffer.free
              ? l10n.p2pTradeCancelOrder
              : l10n.p2pTradeCancelUnilateral,
          child: TradeButton(
            label: l10n.p2pCommonCancel,
            outlined: true,
            color: colors.secondary,
            busy: running,
            onPressed: () => unawaited(_press(context)),
          ),
        ),
        if (notice != null) ...[
          const Gap(BullSpacing.sm),
          _Line(
            notice.toText(context, coordinator: coordinator),
            color: colors.error,
            center: true,
          ),
        ],
      ],
    );
  }
}

/// A line of the trade screen, which wraps at any text size and is read out when it changes.
class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  final bool center;

  const _Line(this.text, {this.color, this.icon, this.center = false});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: color ?? context.bull.text);
    final icon = this.icon;
    final line = Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: style,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: icon == null
          ? line
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(icon, size: 18, color: color)),
                const Gap(BullSpacing.xs),
                Expanded(child: line),
              ],
            ),
    );
  }
}
