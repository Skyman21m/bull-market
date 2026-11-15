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
import '../../domain/taker_estimate.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_cubit.dart';
import '../../presentation/take_order_cubit.dart';
import '../../presentation/trade_l10n.dart';
import '../../presentation/trade_order_page_cubit.dart';
import '../../presentation/trade_panel.dart';
import '../coordinator_details_dialog.dart';
import '../take_order_section.dart';
import 'trade_first_read_wait.dart';
import '../widgets/order_detail_row.dart';
import '../widgets/testnet_banner.dart';
import '../widgets/trade_button.dart';
import 'bond_panel.dart';
import 'cancel_order_dialog.dart';
import 'chat_step_panel.dart';
import 'confirm_cancel_dialog.dart';
import 'payout_panel.dart';
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

  /// Where a payment of the bond from this wallet stands, for « Cancel »: `null` without the wallet's port (#100).
  final WalletBondState Function(BuildContext context)? walletBond;

  /// What fills the slot of « Pay with this wallet » of the bond panel: `null` today (see [WalletPaymentSection]).
  final WalletPaymentBuilder? walletPayment;

  /// The payout panel of 6, 8 and 15 (#91): `null`, and the prompt shows no form, where the feature holds no robot (see [PayoutPanel]).
  final PayoutPanelBuilder? payout;

  /// Whether an action that moves money runs for this trade (a payout being given, #91): « Cancel » is then off, so that a cancel never leaves while it runs; `null` for none.
  final bool Function(BuildContext context)? moneyActionRunning;

  /// The line that says, after status 3, where the payment of a bond paid by this wallet stands, given whether the trade goes on after the bond's lock: `null` without the wallet's port (#100).
  final Widget Function(BuildContext context, bool bondHeld)? walletBondLine;

  /// Builds the cubit that takes the order once it is public again, with a fresh robot, as from the book; `null` when the feature holds no robots, and the order is then shown without « Take Order ».
  final TakeOrderCubit Function(PublicOrder order)? takeCubitFor;

  /// Opens the Garage, from the dialog shown when there is no robot to take with.
  final VoidCallback? onOpenGarage;

  /// Opens the trade a new take of the order started.
  final ValueChanged<TradeRecord>? onTaken;

  const TradeScreen({
    super.key,
    required this.now,
    required this.coordinatorDetails,
    this.walletPayment,
    this.payout,
    this.moneyActionRunning,
    this.walletBond,
    this.walletBondLine,
    this.takeCubitFor,
    this.onOpenGarage,
    this.onTaken,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findIfPublic(context.read<TradeCubit>().state);
    });
  }

  /// Looks for the order in its coordinator's book once the trade shows it public again, for « Take Order ».
  void _findIfPublic(TradeScreenState state) {
    if (TradeView.of(state.watch) case TradeOrderOnly(:final order)) {
      unawaited(context.read<TradeOrderPageCubit>().findPublic(order));
    }
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
        // The clock first, so that an invoice that expired while the app was away is not drawn for a frame.
        setState(() => _now = widget.now());
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
    final page = context.watch<TradeOrderPageCubit>().state;
    final record = state.record;
    final view = TradeView.of(state.watch);
    final coordinator = _coordinatorName(state);
    final lines = _lines(context, state, coordinator);
    return BlocListener<TradeCubit, TradeScreenState>(
      listener: (context, state) => _findIfPublic(state),
      child: Material(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: BullSpacing.md,
                  ),
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
                    // After status 3, where a bond paid by this wallet stands (in progress, refunded, kept, under review); at status 3 the panel itself says it.
                    if (widget.walletBondLine case final bondLine?
                        when view is! TradeWaiting &&
                            !(view is TradeContract &&
                                view.status is WaitingForTakerBond)) ...[
                      bondLine(
                        context,
                        // Locked only while the bond is (the reference's bond line « locked »).
                        view is TradeContract &&
                            view.bondLine == TradeBondLine.locked,
                      ),
                      const Gap(BullSpacing.sm),
                    ],
                    switch (view) {
                      TradeWaiting() => TradeFirstReadWait(
                        coordinator: coordinator,
                      ),
                      TradeMessage(:final kind) => _Message(
                        text: kind.toText(context, coordinator: coordinator),
                        waits: kind == TradeMessageKind.takePending,
                        notice: switch (state.chatStep) {
                          ChatStepIdle(:final notice?, :final action) => (
                            notice,
                            action,
                          ),
                          _ => null,
                        },
                        coordinator: coordinator,
                      ),
                      TradeOrderOnly(:final order) => _PublicAgain(
                        order: order,
                        now: _now,
                        info: page.info,
                        lookup: page.publicOrder,
                        takeCubitFor: widget.takeCubitFor,
                        onOpenGarage: widget.onOpenGarage,
                        onTaken: widget.onTaken,
                        onOpenCoordinator: () => _openCoordinator(order),
                      ),
                      TradeContract(:final order?) when _orderTab =>
                        TradeOrderDetails(
                          order: order,
                          now: _now,
                          info: page.info,
                          onOpenCoordinator: () => _openCoordinator(order),
                        ),
                      // No order read to show: the status the contract shows, with the lines above, never an endless wait.
                      final TradeContract contract when _orderTab => _Line(
                        contract.title.toText(
                          context,
                          bondSats: switch (contract.status) {
                            WaitingForTakerBond(:final bond) => P2pFormats.of(
                              context,
                            ).sats(bond.orderAmount.value.toInt()),
                            _ => '',
                          },
                        ),
                        center: true,
                      ),
                      // Keyed, so that a line added above it (reads that fail, a record not written) keeps it as it is.
                      final TradeContract contract => _Contract(
                        key: const ValueKey('trade-contract'),
                        contract: contract,
                        now: _now,
                        record: record,
                        cancel: state.cancel,
                        chatStep: state.chatStep,
                        offersFiatSent: context
                            .read<TradeCubit>()
                            .offersFiatSent,
                        offersUndoFiatSent: context
                            .read<TradeCubit>()
                            .offersUndoFiatSent,
                        coordinator: coordinator,
                        walletPayment: widget.walletPayment,
                        payout: widget.payout,
                        moneyActionRunning:
                            widget.moneyActionRunning?.call(context) ?? false,
                        walletBond: widget.walletBond,
                      ),
                    },
                  ],
                ),
              ),
            ],
          ),
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

  /// What an action of the chat step gave, when the order it was sent for is now shown as a message (cancelled, ended): said under it, as the reference says its `bad_request` whatever the status (#95).
  final (ChatStepNotice, ChatStepAction)? notice;
  final String coordinator;

  const _Message({
    required this.text,
    required this.waits,
    this.notice,
    required this.coordinator,
  });

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
          if (notice case (final notice, final action)) ...[
            const Gap(BullSpacing.md),
            ChatStepNoticeLine(
              notice: notice,
              coordinator: coordinator,
              action: action,
            ),
          ],
        ],
      ),
    );
  }
}

/// The contract of a status: title and step, the warnings, the prompt, the bond line, and « Copy URL » / « Cancel » where the reference offers them.
class _Contract extends StatelessWidget {
  /// The screen's clock, which hides an invoice past its `payableUntil` between two reads.
  final DateTime now;

  final TradeContract contract;
  final TradeRecord record;
  final TradeCancelState cancel;
  final ChatStepState chatStep;
  final bool offersFiatSent;
  final bool offersUndoFiatSent;
  final String coordinator;
  final WalletPaymentBuilder? walletPayment;
  final PayoutPanelBuilder? payout;
  final bool moneyActionRunning;
  final WalletBondState Function(BuildContext context)? walletBond;

  const _Contract({
    super.key,
    required this.contract,
    required this.now,
    required this.record,
    required this.cancel,
    required this.chatStep,
    required this.offersFiatSent,
    required this.offersUndoFiatSent,
    required this.coordinator,
    required this.walletPayment,
    required this.payout,
    required this.moneyActionRunning,
    required this.walletBond,
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
    final warnings = warningsOf(status, now: now);
    // The reference's alert of a collaborative cancel, above the title, at 9 only (`TradeBox/CollabCancelAlert.tsx`): the peer's ask, or this robot's.
    final collabAlert = switch ((status, contract.order)) {
      (Chatting(fiatSent: false, peerAskedToCancel: true), final order?) =>
        l10n.p2pEndCollabPeerAlert(order.maker.nickname),
      (Chatting(fiatSent: false, askedToCancel: true), _) =>
        l10n.p2pEndCollabAskedAlert,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (collabAlert != null) ...[
          _Line(
            collabAlert,
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
            live: true,
          ),
          const Gap(BullSpacing.md),
        ],
        // The title is what a screen reader reads out when the status changes, rather than each line of the panel.
        Semantics(
          container: true,
          header: true,
          liveRegion: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // « Trade finished! » between the reference's two bolts, in its warning colour (`TradeBox/index.tsx:633-636`).
              if (contract.title == TradeTitle.finished) ...[
                ExcludeSemantics(
                  child: Icon(Icons.bolt, color: colors.warning),
                ),
                const Gap(BullSpacing.xs),
              ],
              Flexible(
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
              if (contract.title == TradeTitle.finished) ...[
                const Gap(BullSpacing.xs),
                ExcludeSemantics(
                  child: Icon(Icons.bolt, color: colors.warning),
                ),
              ],
            ],
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
        // What an action of the chat step gave, once the order moved past the chat step (a dispute, an end): said under the new status's prompt, as the reference says its `bad_request` whatever the status (#95); at 9 and 10 the chat step's panel says it.
        if (contract.prompt != TradePrompt.chat)
          if (chatStep case ChatStepIdle(:final notice?, :final action)) ...[
            const Gap(BullSpacing.md),
            ChatStepNoticeLine(
              notice: notice,
              coordinator: coordinator,
              action: action,
            ),
          ],
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
            moneyActionRunning: moneyActionRunning,
            bond: walletBond?.call(context) ?? WalletBondState.none,
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
        seen: contract.seen,
        walletPayment: walletPayment,
        now: now,
        swap: order?.currency.isBitcoin ?? false,
        payable: contract.payable,
      ),
      (TradePrompt.payout, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (order != null) ...[
            _Line(
              l10n.p2pTradePayoutPrompt(
                formats.payoutAmount(
                  (order.takenAmount ?? order.amount.max).value,
                  inBitcoin: order.currency.isBitcoin,
                ),
                order.currency.isBitcoin
                    ? l10n.p2pSatsUnit
                    : order.currency.code,
              ),
            ),
            const Gap(BullSpacing.sm),
          ],
          ?_payoutPanel(context),
        ],
      ),
      (TradePrompt.routingFailed, _) =>
        _payoutPanel(context) ?? const SizedBox.shrink(),
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
      // The buyer's chat step (#95): the chat's place stays empty until the chat panel (#93) fills it.
      (TradePrompt.chat, _) => ChatStepPanel(
        seen: contract.seen,
        order: order,
        coordinator: coordinator,
        chatStep: chatStep,
        cancel: cancel,
        otherActionRunning: moneyActionRunning,
        offersFiatSent: offersFiatSent,
        offersUndoFiatSent: offersUndoFiatSent,
        offersCollaborativeCancel: true,
      ),
      (TradePrompt.sendingSats, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pEndSendingSats),
          const Gap(BullSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l10n.p2pEndTakingTooLong,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' '),
                TextSpan(text: l10n.p2pEndTakingTooLongText),
              ],
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.md),
          Center(child: CircularProgressIndicator(color: colors.primary)),
        ],
      ),
      // « Trade finished! » with its title alone: the rating and the summary come with a later pull request of #95.
      (TradePrompt.finished, _) => const SizedBox.shrink(),
      _ => _Line(l10n.p2pTradeStepLater, color: colors.textMuted),
    };
  }

  /// The payout panel of the status shown, when the screen was given one, keyed so that a change of the prompt around it keeps it.
  Widget? _payoutPanel(BuildContext context) => switch (payout?.call(
    context,
    PayoutPanelRequest(
      record: record,
      seen: contract.seen,
      coordinator: coordinator,
      now: now,
      cancelling: cancel is CancelRunning,
    ),
  )) {
    final panel? => KeyedSubtree(
      key: const ValueKey('trade-payout-panel'),
      child: panel,
    ),
    null => null,
  };
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
class _CancelRow extends StatefulWidget {
  final TradeCancelOffer offer;
  final TradeRecord record;
  final TradeSeen seen;
  final TradeCancelState cancel;
  final String coordinator;

  /// Whether an action that moves money runs: « Cancel » is off meanwhile.
  final bool moneyActionRunning;

  /// Where a payment of the bond from this wallet stands: « Cancel » waits while it is sent, and its dialog says when one is on its way.
  final WalletBondState bond;

  const _CancelRow({
    required this.offer,
    required this.record,
    required this.seen,
    required this.cancel,
    required this.coordinator,
    required this.moneyActionRunning,
    required this.bond,
  });

  @override
  State<_CancelRow> createState() => _CancelRowState();
}

class _CancelRowState extends State<_CancelRow> {
  /// Whether a dialog of the cancel is open: a second press meanwhile opens nothing more.
  bool _asking = false;

  /// Cancels with the status seen when « Cancel » was pressed, never the one shown when the dialog closes: an agreement given for one status is not given for another (`CancelTradeUsecase` sends that status's guard, and a [BondLossAcknowledged] covers that status only).
  Future<void> _press() async {
    if (_asking) return;
    _asking = true;
    final cubit = context.read<TradeCubit>();
    final seen = widget.seen;
    // The project's line under the reference's text, when a payment of the bond is on its way from this wallet: informed, not stopped.
    // Only at 3, where the cancel is free: from 6 on the bond is locked and the reference's text says it is lost.
    final note = widget.bond.sent && widget.offer == TradeCancelOffer.free
        ? P2pLocalizations.of(context).p2pPayCancelNote
        : null;
    try {
      // A status that comes from no order read (an answer refused as a whole keeps the last status without its order) cannot be cancelled until the order is read again: no dialog, the cancel is asked and refused with « Wait until the order is read again before cancelling. » (`CancelNeedsARead`), nothing sent.
      if (seen.order == null) {
        await cubit.cancel(seen);
        return;
      }
      switch (widget.offer) {
        case TradeCancelOffer.free:
          if (await CancelOrderDialog.show(context, note: note)) {
            await cubit.cancel(seen);
          }
        case TradeCancelOffer.losesBond:
          final acknowledged = await ConfirmCancelDialog.show(
            context,
            record: widget.record,
            seen: seen,
            note: note,
          );
          if (acknowledged != null) {
            await cubit.cancel(seen, bondLoss: acknowledged);
          }
        case TradeCancelOffer.none:
          break;
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final offer = widget.offer;
    final record = widget.record;
    final coordinator = widget.coordinator;
    final running = widget.cancel is CancelRunning;
    final notice = switch (widget.cancel) {
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
          child: _CopyUrlButton(url: url),
        ),
        const Gap(BullSpacing.sm),
        Tooltip(
          // While a payout is given, why « Cancel » is off, for a screen reader and a long press.
          message: widget.moneyActionRunning
              ? l10n.p2pTradeCancelWhilePayout
              : offer == TradeCancelOffer.free
              ? l10n.p2pTradeCancelOrder
              : l10n.p2pTradeCancelUnilateral,
          child: TradeButton(
            label: l10n.p2pCommonCancel,
            outlined: true,
            color: colors.secondary,
            busy: running,
            // A payment of the bond being sent ends first, as the payment's own button waits (the cancel takes the order's lock too); a payout being given too (#91).
            onPressed: widget.moneyActionRunning || widget.bond.sending
                ? null
                : () => unawaited(_press()),
          ),
        ),
        if (notice != null) ...[
          const Gap(BullSpacing.sm),
          _Line(
            notice.toText(context, coordinator: coordinator),
            color: colors.error,
            center: true,
            live: true,
          ),
        ],
      ],
    );
  }
}

/// A line of the trade screen, which wraps at any text size; a [live] one is read out when it changes.
class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  final bool center;

  /// Whether a screen reader reads it out when it changes: a notice of what an action gave, not the static text of a panel.
  final bool live;

  const _Line(
    this.text, {
    this.color,
    this.icon,
    this.center = false,
    this.live = false,
  });

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
      liveRegion: live,
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

/// « Copy URL », which says « Copied! » for a moment once the order's address is copied, as « Copy to clipboard » does.
class _CopyUrlButton extends StatefulWidget {
  final String url;

  const _CopyUrlButton({required this.url});

  @override
  State<_CopyUrlButton> createState() => _CopyUrlButtonState();
}

class _CopyUrlButtonState extends State<_CopyUrlButton> {
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return Semantics(
      liveRegion: _copied,
      child: TradeButton(
        label: _copied ? l10n.p2pCommonCopied : l10n.p2pTradeCopyUrl,
        outlined: true,
        onPressed: () => unawaited(_copy()),
      ),
    );
  }
}

/// An order public again: the order with « Take Order », as the official client shows it to a robot that is no participant (`components/OrderDetails/index.tsx:566-578`).
///
/// Once the coordinator's book lists it ([TradeOrderPageCubit.findPublic]), the order shown is the book's, as on the order details of the book, and « Take Order » takes that same order, with a fresh robot, through the same single caller of the take; until then, the order as the trade's last read describes it. An order the book does not list says it is not available; a book that could not be read says nothing of the order and offers « Retry », once per press.
class _PublicAgain extends StatelessWidget {
  final CoordinatorOrder order;
  final DateTime now;
  final CoordinatorInfo? info;
  final PublicOrderLookup lookup;
  final TakeOrderCubit Function(PublicOrder order)? takeCubitFor;
  final VoidCallback? onOpenGarage;
  final ValueChanged<TradeRecord>? onTaken;
  final VoidCallback onOpenCoordinator;

  const _PublicAgain({
    required this.order,
    required this.now,
    required this.info,
    required this.lookup,
    required this.takeCubitFor,
    required this.onOpenGarage,
    required this.onTaken,
    required this.onOpenCoordinator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final takeCubitFor = this.takeCubitFor;
    final onTaken = this.onTaken;
    final takes = takeCubitFor != null && onTaken != null;
    if (takes) {
      if (lookup case PublicOrderFound(
        order: final public,
      ) when public.id == order.id) {
        // The take's cubit is above the order details too, which show the robot's read once the take is prepared (#119).
        return BlocProvider(
          key: ValueKey(public.id),
          create: (_) => takeCubitFor(public),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrderHostRow(
                coordinator: public.coordinator,
                orderId: public.id,
                onTap: onOpenCoordinator,
              ),
              const Gap(BullSpacing.sm),
              TakeOrderFeeRow(info: info, canTake: true),
              const Gap(BullSpacing.sm),
              TakeOrderDetailsCard(
                order: public,
                estimate: TakerEstimate.of(
                  public,
                  takerFee: info?.takerFee ?? 0,
                ),
                now: now,
                canTake: true,
              ),
              const Gap(BullSpacing.md),
              TakeOrderMakerRow(order: public, canTake: true),
              const Gap(BullSpacing.lg),
              TakeOrderSection(
                order: public,
                takerFee: info?.takerFee ?? 0,
                canTake: true,
                onOpenGarage: onOpenGarage,
                onTaken: onTaken,
              ),
            ],
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TradeOrderDetails(
          order: order,
          now: now,
          info: info,
          onOpenCoordinator: onOpenCoordinator,
        ),
        if (takes)
          switch (lookup) {
            PublicOrderNotListed(:final orderId) when orderId == order.id =>
              Padding(
                padding: const EdgeInsets.only(top: BullSpacing.lg),
                child: _Line(l10n.p2pOrderNotAvailable, center: true),
              ),
            // The book could not be read: a fault, not an answer about the order; the coordinator dialog's words and « Retry ».
            PublicOrderLookFailed(:final orderId) when orderId == order.id =>
              Padding(
                padding: const EdgeInsets.only(top: BullSpacing.lg),
                child: Column(
                  children: [
                    _Line(
                      l10n.p2pCoordinatorOffline,
                      color: colors.error,
                      center: true,
                      live: true,
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        context.read<TradeOrderPageCubit>().retryPublic(order),
                      ),
                      child: Text(
                        l10n.p2pCommonRetry,
                        style: text.labelLarge?.copyWith(color: colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            _ => const SizedBox.shrink(),
          },
      ],
    );
  }
}
