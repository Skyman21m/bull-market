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
import '../../domain/trade/trade_warning.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_rate_cubit.dart';
import '../../presentation/public_wait.dart';
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
import 'chat_actions.dart';
import 'chat_panel.dart';
import 'chat_step_panel.dart';
import 'confirm_cancel_dialog.dart';
import 'host_rating_section.dart';
import 'payout_panel.dart';
import 'payout_rate_line.dart';
import 'rate_gap_line.dart';
import 'successful_panel.dart';
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

  /// The chat panel of 9 and 10 (#93): `null`, and the chat step shows no chat, where the feature holds no robot (see [ChatPanel]).
  final ChatPanelBuilder? chat;

  /// « Audit Chat » and « Export » of « Order options » (#157), over the cubit of [chat]: given with it, `null` with it.
  final ChatOptionsBuilder? chatOptions;

  /// « Rate your host » at the end of a successful trade (#95): `null`, and the end shows no such rating, where the feature holds no robot (see [HostRatingSection]).
  final HostRatingBuilder? hostRating;

  /// The line that says, after status 3, where the payment of a bond paid by this wallet stands, given whether the trade goes on after the bond's lock: `null` without the wallet's port (#100).
  final Widget Function(BuildContext context, bool bondHeld)? walletBondLine;

  /// The line that says, after the seller's escrow step (6 and 7), where the payment of an escrow paid by this wallet stands, given whether the reference's title says the escrow locked: `null` without the wallet's port (#97).
  final Widget Function(BuildContext context, bool escrowHeld)?
  walletEscrowLine;

  /// Builds the cubit that takes the order once it is public again, with a fresh robot, as from the book; `null` when the feature holds no robots, and the order is then shown without « Take Order ».
  final TakeOrderCubit Function(PublicOrder order)? takeCubitFor;

  /// Opens the Garage, from the dialog shown when there is no robot to take with.
  final VoidCallback? onOpenGarage;

  /// Opens the trade a new take of the order started.
  final ValueChanged<TradeRecord>? onTaken;

  /// Every order the book of the tab received when the trade was opened (`BookState.receivedOrders`), for the figures of a maker's public order (« Public orders for … », « Premium rank », `Prompts/PublicWait.tsx:52-78`, #182); `null` when no book was received, and those figures are not shown.
  final List<PublicOrder>? book;

  /// Whether a [PayoutRateCubit] is above the screen (the wallet's port was lent): the owner's payment rule on a maker buyer's side (#182) is then read when its step is shown.
  final bool checksPayoutRate;

  const TradeScreen({
    super.key,
    required this.now,
    required this.coordinatorDetails,
    this.walletPayment,
    this.payout,
    this.moneyActionRunning,
    this.chat,
    this.chatOptions,
    this.hostRating,
    this.walletBond,
    this.walletBondLine,
    this.walletEscrowLine,
    this.takeCubitFor,
    this.onOpenGarage,
    this.onTaken,
    this.book,
    this.checksPayoutRate = false,
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
      if (!mounted) return;
      final state = context.read<TradeCubit>().state;
      _findIfPublic(state);
      _checkRate(state);
    });
  }

  /// Looks for the order in its coordinator's book once the trade shows it public again, for « Take Order ».
  void _findIfPublic(TradeScreenState state) {
    if (TradeView.of(state.watch) case TradeOrderOnly(:final order)) {
      unawaited(context.read<TradeOrderPageCubit>().findPublic(order));
    }
  }

  /// The owner's payment rule on a maker buyer's side (#182): the Bull wallet's price read once per contract and step when the screen shows the buyer's payout or « fiat sent » ([PayoutRateCubit.show]).
  void _checkRate(TradeScreenState state) {
    if (!widget.checksPayoutRate) return;
    if (state.watch case TradeWatchStatus(:final seen)) {
      unawaited(context.read<PayoutRateCubit>().show(seen));
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
      listener: (context, state) {
        _findIfPublic(state);
        _checkRate(state);
      },
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
                    // After status 3, or a maker's 0 (#180), where a bond paid by this wallet stands (in progress, refunded, kept, under review); at the bond's step the panel itself says it.
                    if (widget.walletBondLine case final bondLine?
                        when view is! TradeWaiting &&
                            !(view is TradeContract &&
                                view.prompt == TradePrompt.lockInvoice)) ...[
                      bondLine(
                        context,
                        // Locked only while the bond is (the reference's bond line « locked »).
                        view is TradeContract &&
                            view.bondLine == TradeBondLine.locked,
                      ),
                      const Gap(BullSpacing.sm),
                    ],
                    // After the escrow's step, where an escrow paid by this wallet stands (refunded, under review, support), whatever the view, as the bond's: a cancelled trade (`TradeMessage`) and an order back in the book (`TradeOrderOnly`) are where an escrow returned is said; at 6 and 7 the escrow panel itself says it.
                    if (widget.walletEscrowLine case final escrowLine?
                        when view is! TradeWaiting &&
                            !(view is TradeContract &&
                                view.prompt == TradePrompt.lockEscrow)) ...[
                      escrowLine(
                        context,
                        // Locked while the reference's title says so: « The trade collateral is locked! », « Chat with the buyer ».
                        view is TradeContract &&
                            (view.title == TradeTitle.collateralLocked ||
                                view.title == TradeTitle.chatWithBuyer),
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
                          amountSats: switch (contract.titleSats) {
                            final sats? => P2pFormats.of(
                              context,
                            ).sats(sats.value.toInt()),
                            null => '',
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
                        offersFiatReceived: context
                            .read<TradeCubit>()
                            .offersFiatReceived,
                        offersDispute: context.read<TradeCubit>().offersDispute,
                        offersRating: context.read<TradeCubit>().offersRating,
                        clock: widget.now,
                        coordinator: coordinator,
                        walletPayment: widget.walletPayment,
                        payout: widget.payout,
                        chat: widget.chat,
                        chatOptions: widget.chatOptions,
                        hostRating: widget.hostRating,
                        moneyActionRunning:
                            widget.moneyActionRunning?.call(context) ?? false,
                        walletBond: widget.walletBond,
                        book: widget.book,
                        payoutRate: widget.checksPayoutRate
                            ? context.watch<PayoutRateCubit>().state
                            : null,
                        onRetryRate: widget.checksPayoutRate
                            ? () => unawaited(
                                context.read<PayoutRateCubit>().retry(),
                              )
                            : null,
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
  final bool offersFiatReceived;
  final bool offersDispute;
  final bool offersRating;

  /// The screen's clock, which a countdown of a dialog reads as it ticks.
  final DateTime Function() clock;
  final String coordinator;
  final WalletPaymentBuilder? walletPayment;
  final PayoutPanelBuilder? payout;
  final ChatPanelBuilder? chat;
  final ChatOptionsBuilder? chatOptions;
  final HostRatingBuilder? hostRating;
  final bool moneyActionRunning;
  final WalletBondState Function(BuildContext context)? walletBond;

  /// The book of the tab, for a maker's public order ([TradeScreen.book]).
  final List<PublicOrder>? book;

  /// The owner's payment rule on a maker buyer's side (#182), `null` without the wallet's port, and its « Retry ».
  final PayoutRateState? payoutRate;
  final VoidCallback? onRetryRate;

  const _Contract({
    super.key,
    required this.contract,
    required this.now,
    required this.record,
    required this.cancel,
    required this.chatStep,
    required this.offersFiatSent,
    required this.offersUndoFiatSent,
    required this.offersFiatReceived,
    required this.offersDispute,
    required this.offersRating,
    required this.clock,
    required this.coordinator,
    required this.walletPayment,
    required this.payout,
    required this.chat,
    required this.chatOptions,
    required this.hostRating,
    required this.moneyActionRunning,
    required this.walletBond,
    required this.book,
    required this.payoutRate,
    required this.onRetryRate,
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
      amountSats: switch (contract.titleSats) {
        final sats? => formats.sats(sats.value.toInt()),
        null => '',
      },
    );
    final step = contract.step;
    final warnings = warningsOf(status, now: now);
    // The reference's alert of a collaborative cancel, above the title, at 9 only (`TradeBox/CollabCancelAlert.tsx`): the peer's ask, or this robot's.
    final collabAlert = switch ((status, contract.order)) {
      (Chatting(fiatSent: false, peerAskedToCancel: true), final order?) =>
        l10n.p2pEndCollabPeerAlert(order.maker.nickname),
      // A status kept from no order (a read refused as a whole): no nickname to name, so the reference's own words for the peer's ask (`Dialogs/ConfirmCollabCancel.tsx`).
      (Chatting(fiatSent: false, peerAskedToCancel: true), null) =>
        l10n.p2pEndCollabPeerAsked,
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
                  // « Trade finished! » in the success colour, the seller's escrow to lock in the warning colour (`titleColor`, `TradeBox/index.tsx:483`, `:501`, `:611`).
                  style: text.headlineLarge?.copyWith(
                    color: switch (contract.title) {
                      TradeTitle.finished => colors.success,
                      TradeTitle.lockEscrow => colors.warning,
                      _ => colors.primary,
                    },
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
          // A next contract seen late is information, not an alert (#178, #182): its own words, in the text colour.
          if (warning is ContractSeenLate)
            _Line(
              warning.toText(context, coordinator: coordinator),
              icon: Icons.info_outline,
            )
          else
            _Line(
              warning.toText(context, coordinator: coordinator),
              color: colors.warning,
              icon: Icons.warning_amber_rounded,
            ),
          const Gap(BullSpacing.sm),
        ],
        // An order made here whose coordinator contradicted the trade's history (a breach): what to do (design note § 6, row 8, #182).
        if (record.origin == TradeOrigin.madeHere &&
            (status.trail.breached || status.has<CoordinatorInconsistent>())) ...[
          _Line(
            l10n.p2pTradeBreachWhatToDo(coordinator),
            color: colors.warning,
            icon: Icons.info_outline,
          ),
          const Gap(BullSpacing.sm),
        ],
        _prompt(context, status),
        // What an action of the chat step gave, once the order moved past the chat step (a dispute, an end): said under the new status's prompt, as the reference says its `bad_request` whatever the status (#95); at 9 and 10 the chat step's panel says it, and at 14 the panel of the end, under its stars, when it offers them.
        if (contract.prompt != TradePrompt.chat &&
            !(contract.prompt == TradePrompt.finished && offersRating))
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
          _BondLine(line: contract.bondLine, maker: contract.maker),
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
    final chat = this.chat;
    final chatOptions = this.chatOptions;
    final chatRequest = ChatPanelRequest(
      record: record,
      seen: contract.seen,
      coordinator: coordinator,
    );
    return switch ((contract.prompt, status)) {
      // The taker's bond at 3, or the maker bond at 0 (#180): the same prompt (`Prompts/LockInvoice.tsx`, concept `bond`).
      (
        TradePrompt.lockInvoice,
        WaitingForTakerBond() || WaitingForMakerBond(),
      ) =>
        BondPanel(
          record: record,
          status: status,
          seen: contract.seen,
          walletPayment: walletPayment,
          now: now,
          swap: order?.currency.isBitcoin ?? false,
          seller: record.role == TradeRole.seller,
          payable: contract.payable,
        ),
      // The seller's escrow (#96), from this wallet (#97) or another.
      (
        TradePrompt.lockEscrow,
        WaitingForBoth(:final escrow, :final currency, :final escrowDuration) ||
            WaitingForEscrow(
              :final escrow,
              :final currency,
              :final escrowDuration,
            ),
      ) =>
        EscrowPanel(
          invoice: escrow,
          currency: currency,
          escrowDuration: escrowDuration,
          now: now,
          payable: contract.payable,
          record: record,
          seen: contract.seen,
          walletPayment: walletPayment,
        ),
      (TradePrompt.lockEscrow, _) => const SizedBox.shrink(),
      // A maker's public order (#182): `Prompts/PublicWait.tsx`, without the pause button (#184).
      (TradePrompt.publicWait, _) => _PublicWait(
        order: order,
        book: book,
        escrowDuration: order?.escrowDuration,
      ),
      // A maker's order paused from another app (#182): `Prompts/Paused.tsx`'s text; « Unpause Order » comes with the pause (#184).
      (TradePrompt.paused, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pTradePausedText),
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pTradeUnpauseLater, color: colors.textMuted),
        ],
      ),
      (TradePrompt.payoutWait, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pTradePayoutWait),
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pTradePayoutWaitHangOn),
        ],
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
          // A maker buyer's line of the gap, before « Submit » (design note § 3.3, #182).
          if (_gapLine(context, status) case final gap?) ...[
            gap,
            const Gap(BullSpacing.sm),
          ],
          // The owner's payment rule on a maker buyer's side, before « Submit » (#182).
          ?_rateLines(context),
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
      // The chat step (#95; the seller's, #96), with the chat panel (#93) in its place when the screen was given one.
      (TradePrompt.chat, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The owner's payment rule on a maker buyer's side, before « Confirm … sent » (#182), with its « Retry ».
          ?_rateLines(context),
          ChatStepPanel(
        seen: contract.seen,
        order: order,
        coordinator: coordinator,
        chatStep: chatStep,
        cancel: cancel,
        otherActionRunning: moneyActionRunning,
        offersFiatSent: offersFiatSent,
        offersUndoFiatSent: offersUndoFiatSent,
        offersFiatReceived: offersFiatReceived,
        offersCollaborativeCancel: true,
        offersDispute: offersDispute,
        now: clock,
        // The chat panel (#93) in the step's place for it, between the prompt's text and the action buttons.
        chat: chat == null
            ? null
            : KeyedSubtree(
                key: const ValueKey('trade-chat-panel'),
                child: chat(context, chatRequest),
              ),
        // « Audit Chat » and « Export » in « Order options » (#157), over the chat panel's cubit.
        chatOptions: chatOptions == null
            ? null
            : () => chatOptions(context, chatRequest),
        rateLines: switch (payoutRate) {
          PayoutRateChecked(:final check, :final step)
              when step == PayoutRateStep.of(status) =>
            PayoutRateLines.linesOf(
              context,
              check,
              coordinator: coordinator,
              amount: PayoutRateLines.amountOf(context, order),
            ),
          PayoutRateReading(:final step)
              when step == PayoutRateStep.of(status) => [
            (text: l10n.p2pPayoutRateReading, alert: false),
          ],
          _ => const [],
        },
      ),
        ],
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
      // « Trade finished! »: the rating, the on-chain payment's lines and the trade summary (#95).
      (TradePrompt.finished, Succeeded(:final summary, :final onchainPayout)) =>
        _successful(context, summary, onchainPayout),
      // The seller's at 13 and 15 too, where the buyer is still being paid (`TradeBox/index.tsx:602-631`, `:663-690`, #96).
      (
        TradePrompt.finished,
        SendingSats(:final summary) || RoutingFailed(:final summary),
      ) =>
        _successful(context, summary, null),
      (TradePrompt.finished, _) => const SizedBox.shrink(),
      (
        TradePrompt.disputeOpen ||
            TradePrompt.disputeWaitPeer ||
            TradePrompt.disputeWaitResolution ||
            TradePrompt.disputeWon ||
            TradePrompt.disputeLost,
        _,
      ) =>
        _DisputePrompt(
          prompt: contract.prompt,
          coordinator:
              contract.order?.coordinator ??
              Federation.robosats.byAlias(record.coordinatorAlias),
          coordinatorName: coordinator,
          orderId: record.orderId,
        ),
      _ => _Line(l10n.p2pTradeStepLater, color: colors.textMuted),
    };
  }

  /// The lines of the owner's payment rule for the step shown, with their « Retry » (#182); `null` where there are none.
  Widget? _rateLines(BuildContext context) {
    final state = payoutRate;
    // Only the check of the step shown: never one of a step before.
    final shown = PayoutRateStep.of(contract.status);
    final step = switch (state) {
      PayoutRateReading(:final step) || PayoutRateChecked(:final step) => step,
      _ => null,
    };
    if (state == null || step == null || step != shown) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.sm),
      child: PayoutRateLines(
        state: state,
        coordinator: coordinator,
        amount: PayoutRateLines.amountOf(context, contract.order),
        onRetry: onRetryRate,
      ),
    );
  }

  /// The line of the gap of a maker's contract at 6 and 8 ([RateGapLine]), from the status's own figure and the order it was read from; `null` for a taker, whose statuses carry no gap.
  Widget? _gapLine(BuildContext context, TradeStatus status) {
    final order = contract.order;
    final (gap, role) = switch (status) {
      WaitingForBoth(:final rateGap, :final role) ||
      WaitingForPayout(:final rateGap, :final role) => (rateGap, role),
      _ => (null, record.role),
    };
    if (order == null) return null;
    return RateGapLine.of(
      context,
      gap: gap,
      role: role,
      coordinator: coordinator,
      sats: order.satoshisNow,
      amount: switch ((order.takenAmount, order.amount)) {
        (final taken?, _) => taken,
        (null, FixedOrderAmount(:final amount)) => amount,
        _ => null,
      },
      currency: order.currency,
    );
  }

  /// « Trade finished! »: the rating, the on-chain payment's lines and the trade summary (#95).
  Widget _successful(
    BuildContext context,
    TradeSummary? summary,
    OnchainPayout? onchainPayout,
  ) => SuccessfulPanel(
    key: const ValueKey('trade-successful-panel'),
    seen: contract.seen,
    summary: summary,
    onchainPayout: onchainPayout,
    order: contract.order,
    coordinator: coordinator,
    chatStep: chatStep,
    otherActionRunning: moneyActionRunning || cancel is CancelRunning,
    offersRating: offersRating,
    hostRating: hostRating?.call(context, contract.seen, coordinator),
  );

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

/// « Your taker bond is locked / unlocked / settled », « Your maker bond is … » for a maker (`BondStatus.tsx:39`, #182), with the reference's icons (`TradeBox/BondStatus.tsx`).
class _BondLine extends StatelessWidget {
  final TradeBondLine line;
  final bool maker;

  const _BondLine({required this.line, required this.maker});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final (icon, color, label) = switch (line) {
      TradeBondLine.unlocked => (
        Icons.lock_open,
        colors.success,
        maker ? l10n.p2pTradeMakerBondUnlocked : l10n.p2pTradeBondUnlocked,
      ),
      TradeBondLine.settled => (
        Icons.balance,
        colors.error,
        maker ? l10n.p2pTradeMakerBondSettled : l10n.p2pTradeBondSettled,
      ),
      TradeBondLine.locked || TradeBondLine.hide => (
        Icons.lock,
        colors.primary,
        maker ? l10n.p2pTradeMakerBondLocked : l10n.p2pTradeBondLocked,
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

  /// Where a payment of the bond, or of the escrow, from this wallet stands: « Cancel » waits while one is sent, and its dialog says when one is on its way.
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
    // At 6 and 7, where the cancel costs the bond, the escrow's payment on its way is said the same way (#97).
    final note = switch (widget.offer) {
      TradeCancelOffer.free when widget.bond.sent => P2pLocalizations.of(
        context,
      ).p2pPayCancelNote,
      TradeCancelOffer.losesBond when widget.bond.escrowSent =>
        P2pLocalizations.of(context).p2pPayEscrowCancelNote,
      _ => null,
    };
    try {
      // A status that comes from no order read (an answer refused as a whole keeps the last status without its order) cannot be cancelled until the order is read again: no dialog, the cancel is asked and refused with « Wait until the order is read again before cancelling. » (`CancelNeedsARead`), nothing sent.
      // A status kept while the trade is opened anew (#152) is cancelled as the reference cancels from the order it holds (`TradeBox/index.tsx:244-253`): the request carries that status's guard, which the coordinator refuses for another status (1020).
      if (seen.order == null) {
        await cubit.cancel(seen);
        return;
      }
      switch (widget.offer) {
        case TradeCancelOffer.free:
          if (await CancelOrderDialog.show(context, note: note)) {
            await cubit.cancel(seen);
          }
        // A maker's public or paused order: cancelled at once, with no dialog, as the reference (`CancelButton.tsx:30`, `:79-80`): its bond is returned by the coordinator (#182).
        case TradeCancelOffer.immediate:
          await cubit.cancel(seen);
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
              : offer == TradeCancelOffer.free ||
                    offer == TradeCancelOffer.immediate
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

/// 11, 16, 17 and 18, read-only (#95, design note § 2.7): the reference's texts of each prompt, the order's number to identify it, and the coordinator's contacts as its dialog shows them (`CoordinatorContacts`).
///
/// At 11, before this robot's statement is in, the reference shows its statement form, which comes in a later phase: in its place, the project's line that says to contact the coordinator, then the reference's advice to save what identifies the order. At 17 the reference says to claim from the profile's rewards, which Bull Market cannot yet: the project's line says so.
class _DisputePrompt extends StatelessWidget {
  final TradePrompt prompt;
  final Coordinator? coordinator;
  final String coordinatorName;
  final int orderId;

  const _DisputePrompt({
    required this.prompt,
    required this.coordinator,
    required this.coordinatorName,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final contact = coordinator?.contact;
    // The coordinator's email in the reference's texts of 17 and 18, cleaned as every coordinator's text is; its name when it gives none.
    final email = switch (contact?.email) {
      final email? when email.trim().isNotEmpty => CoordinatorText.of(
        email,
        maxCodePoints: CoordinatorText.copyBound,
      ),
      _ => coordinatorName,
    };
    // The project's lines point to the contacts below only when there are some: a coordinator missing from the app's list has none (review of #156).
    final lines = switch (prompt) {
      TradePrompt.disputeOpen => [
        if (contact != null)
          l10n.p2pEndStatementLater(coordinatorName)
        else
          l10n.p2pEndStatementLaterNoContacts(coordinatorName),
        l10n.p2pEndDisputeSaveInfoPeer,
      ],
      TradePrompt.disputeWaitPeer => [
        l10n.p2pEndDisputeWaitPeer,
        l10n.p2pEndDisputeSaveInfoPeer,
      ],
      TradePrompt.disputeWaitResolution => [
        l10n.p2pEndDisputeWaitResolution,
        l10n.p2pEndDisputeSaveInfoResolution,
      ],
      TradePrompt.disputeWon => [
        l10n.p2pEndDisputeWinner(email),
        if (contact != null)
          l10n.p2pEndRewardsLater(coordinatorName)
        else
          l10n.p2pEndRewardsLaterNoContacts(coordinatorName),
      ],
      _ => [l10n.p2pEndDisputeLoser(email)],
    };
    final showsId =
        prompt == TradePrompt.disputeOpen ||
        prompt == TradePrompt.disputeWaitPeer ||
        prompt == TradePrompt.disputeWaitResolution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const Gap(BullSpacing.sm),
          _Line(line),
        ],
        if (showsId) ...[
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pEndOrderId('$orderId'), color: colors.textMuted),
        ],
        if (contact != null) ...[
          const Gap(BullSpacing.sm),
          CoordinatorContacts(contact: contact),
        ],
      ],
    );
  }
}

/// « Your order is public » (`TradeBox/Prompts/PublicWait.tsx:80-147`, #182): the reference's two lines, then « Public orders for {{currencyCode}} » with its count and « Premium rank » with its share, computed from the book of the tab ([PublicWaitStanding]); without the pause button, which comes with the pause (#184). Without an order read, the lines alone; without a book received, no figure.
class _PublicWait extends StatelessWidget {
  final CoordinatorOrder? order;
  final List<PublicOrder>? book;
  final Duration? escrowDuration;

  const _PublicWait({
    required this.order,
    required this.book,
    required this.escrowDuration,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    final seconds = escrowDuration?.inSeconds;
    final order = this.order;
    final book = this.book;
    final standing = order == null || book == null
        ? null
        : PublicWaitStanding.of(order, book: book);
    Widget figure(IconData icon, String primary, String secondary) => Semantics(
      container: true,
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, color: colors.textMuted)),
          const Gap(BullSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: text.bodyLarge?.copyWith(color: colors.text),
                ),
                Text(
                  secondary,
                  style: text.labelMedium?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seconds != null) ...[
          _Line(
            l10n.p2pTradePublicWait(
              '${seconds ~/ 3600}',
              '${(seconds - seconds ~/ 3600 * 3600) ~/ 60}',
            ),
          ),
          const Gap(BullSpacing.sm),
        ],
        _Line(l10n.p2pTradePublicExpiresUntaken),
        if (order != null && standing != null) ...[
          Divider(height: BullSpacing.lg, color: colors.outlineVariant),
          figure(
            Icons.storefront,
            formats.count(standing.similarOrders),
            l10n.p2pTradePublicOrdersFor(order.currency.code),
          ),
          Divider(height: BullSpacing.lg, color: colors.outlineVariant),
          figure(
            Icons.percent,
            l10n.p2pTradePremiumRank(formats.number(standing.premiumRank)),
            l10n.p2pTradePremiumRankAmong(order.currency.code),
          ),
        ],
      ],
    );
  }
}
