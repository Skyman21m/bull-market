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
import '../../domain/trade/maker_terms.dart';
import '../../domain/trade/payout_trace.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_edges.dart';
import '../../domain/trade/trade_pause.dart';
import '../../domain/trade/trade_renewal.dart';
import '../../domain/trade/shown_alerts.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_warning.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../../domain/usecases/trade/check_payout_rate_usecase.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_rate_cubit.dart';
import '../../presentation/public_wait.dart';
import '../../presentation/renewals_cubit.dart';
import '../../presentation/settled_state.dart';
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
import '../widgets/trade_dialog_body.dart';
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
import 'renew_check_dialog.dart';
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

  /// Where the escrows of the order's other contracts, paid or attempted with this wallet, stand (#188, a maker seller's order taken more than once), and an alert when a refund pending turns held or kept again: shown whatever the view, the trade's end included; `null` without the wallet's port.
  final WidgetBuilder? walletEarlierEscrows;

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

  /// Opens the renewal's page of the order of the trade (#185), and completes when that page is left with no order made (an order made replaces this page by the new trade's, `P2pRouter.openRenewal`): « Renew Order » at 5 and « Renew » at « Trade finished! » for an order made here, at a status marked stored where the reference offers it ([OrderRenewal.offeredAt]); `null` where the feature cannot make an order, and neither button is shown.
  final Future<void> Function(TradeRecord record)? onRenew;

  /// Whether a [RenewalsCubit] is above the screen (#216, #217: the terms kept of an order made here and the orders made here since with them): read only where the renewal is offered (functional review of #220, R6); `false` with [onRenew], and nothing is said of them.
  final bool readsRenewals;

  /// Opens the trade of another order of this device: the newest order made since with the terms of this one (#217), in place of this page; `null` with [onRenew].
  final ValueChanged<TradeRecord>? onOpenTrade;

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
    this.walletEarlierEscrows,
    this.takeCubitFor,
    this.onOpenGarage,
    this.onTaken,
    this.book,
    this.checksPayoutRate = false,
    this.onRenew,
    this.readsRenewals = false,
    this.onOpenTrade,
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

  /// Whether the renewal's page opened by « Renew Order » or « Renew » is open (#185): another tap opens nothing more, so that one tap opens one page.
  bool _renewing = false;

  /// What the records said of the order's renewals at the last build (#217), for the tap.
  RenewalsState? _renewalsSeen;

  /// « Renew Order » or « Renew » (#185): the renewal's page of [record], once at a time; the button spins until that page is left. « Renew this order? » first ([RenewCheckDialog]) when something should be known before one more order and its bond: the end not confirmed by the one read of a trade opened again, or shown otherwise, or still running at the coordinator (security review of #220, C1); an order with the same terms made here since, or one still being created (#217, R2); or records that could not tell, a read of them that did not answer within [_renewalsWait] included (C3, R3). Never a lock: « Renew anyway » goes on (the reference, which keeps the robot, has the coordinator refuse a second order while the first is active, `api/logics.py:75-100`, error 1000; here the robot is fresh, so nothing refuses it). While the records are still being read, their first answer is awaited before deciding, so that no quick tap skips the dialog (functional review of #220, R3).
  Future<void> _renew(TradeRecord record) async {
    final open = widget.onRenew;
    if (open == null || _renewing) return;
    setState(() => _renewing = true);
    try {
      final l10n = P2pLocalizations.of(context);
      final trade = context.read<TradeCubit>().state;
      final coordinator = _coordinatorName(trade);
      final reasons = <String>[
        if (trade.watch case TradeWatchStatus(:final endReread?))
          switch (endReread) {
            TradeEndShownAlive() => l10n.p2pRenewEndAlive(coordinator),
            TradeEndShownOtherwise() => l10n.p2pRenewEndOtherwise(coordinator),
            TradeEndReading() ||
            TradeEndNotRead() ||
            TradeEndUnknownToCoordinator() => l10n.p2pRenewEndNotConfirmed(
              coordinator,
            ),
          },
      ];
      if (widget.readsRenewals) {
        final cubit = context.read<RenewalsCubit>();
        var known = cubit.state;
        if (known is RenewalsReading) {
          known = await settledState(
            cubit,
            (state) => state is! RenewalsReading,
            wait: _renewalsWait,
          );
          if (!mounted) return;
        }
        switch (known) {
          case RenewalsListed(:final renewals):
            if (renewals.shown case final shown?) {
              reasons.add(
                l10n.p2pRenewSameTermsMade(
                  '${shown.record.orderId}',
                  _standsText(l10n, shown),
                ),
              );
            }
            if (renewals.pendingSameTerms) {
              reasons.add(l10n.p2pSameTermsPending);
            }
          // Not known, or not known in time: said, never taken for « none ».
          case RenewalsUnknown() || RenewalsReading():
            reasons.add(l10n.p2pRenewSameTermsUnknown);
        }
      }
      if (reasons.isNotEmpty &&
          (!await RenewCheckDialog.show(context, reasons: reasons) ||
              !mounted)) {
        return;
      }
      await open(record);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  /// Whether [watch] is an end opened again whose one read runs (security review of #220, C1).
  static bool _readingEnd(TradeWatchState? watch) =>
      watch is TradeWatchStatus && watch.endReread is TradeEndReading;

  /// How long a tap on « Renew Order » waits for the records' first answer about orders made since with the same terms.
  static const Duration _renewalsWait = Duration(seconds: 10);

  /// Where this device saw [made] stand, in the user's language.
  static String _standsText(P2pLocalizations l10n, OrderMadeSince made) =>
      switch (made.stands) {
        MadeSinceStands.running => l10n.p2pSameTermsRunning,
        MadeSinceStands.expired => l10n.p2pSameTermsExpired,
        MadeSinceStands.cancelled => l10n.p2pSameTermsCancelled,
        MadeSinceStands.completed => l10n.p2pSameTermsCompleted,
        MadeSinceStands.ended => l10n.p2pSameTermsEnded,
      };

  /// The renewal offered for the status [seen] of [record] (#185): an order made here, at a status where the reference offers its maker a renewal, that status the one the read stored or, for a record closed, the end its records hold (#216: a record is closed only once its end is on disk, and a trade opened again shows that end restored, or read again, never stored anew); `null` otherwise. The renewal itself reads the records again and refuses an order they do not show ended (`MakeOrderUsecase.renewal`).
  VoidCallback? _renewalOf(TradeRecord record, TradeSeen seen) {
    if (widget.onRenew == null ||
        record.origin != TradeOrigin.madeHere ||
        !(seen.stored || record.closedAt != null) ||
        !OrderRenewal.offeredAt(seen.status.position, role: record.role)) {
      return null;
    }
    return () => unawaited(_renew(record));
  }

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
      _checkRate(state, appeared: true);
    });
  }

  /// Looks for the order in its coordinator's book once the trade shows it public again, for « Take Order ».
  void _findIfPublic(TradeScreenState state) {
    if (TradeView.of(state.watch) case TradeOrderOnly(:final order)) {
      unawaited(context.read<TradeOrderPageCubit>().findPublic(order));
    }
  }

  /// The owner's payment rule on a maker buyer's side (#182): the Bull wallet's price read once per contract and step when the screen shows the buyer's payout or « fiat sent », and again when the step [appeared] anew with a read 3 minutes old ([PayoutRateCubit.show]).
  void _checkRate(TradeScreenState state, {bool appeared = false}) {
    // Hidden (another tab, a page above it): nothing is read, the step appears anew when shown again.
    if (!widget.checksPayoutRate || _shown == false) return;
    if (state.watch case TradeWatchStatus(:final seen)) {
      unawaited(context.read<PayoutRateCubit>().show(seen, appeared: appeared));
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
    final cubit = context.read<TradeCubit>()
      ..signal(shown ? TradeWatchSignal.onScreen : TradeWatchSignal.offScreen);
    // Shown again: the rule's step appeared anew, told after the frame, out of the build.
    if (shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkRate(cubit.state, appeared: true);
      });
    }
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
        _checkRate(cubit.state, appeared: true);
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
    // The records of the renewals read only where a renewal is offered (functional review of #220, R6): the cubit, made lazily, is not made for a trade that runs.
    final offered = switch (state.watch) {
      TradeWatchStatus(:final record, :final seen) =>
        _renewalOf(record, seen) != null,
      _ => false,
    };
    _renewalsSeen = widget.readsRenewals && offered
        ? context.watch<RenewalsCubit>().state
        : null;
    final lines = _lines(context, state, coordinator);
    // What an action of the chat step gave, said under a wait too: a « Confirm » pressed while a read is refused sends nothing, and the wait says so (security review of #219, C2).
    final waitNotice = switch (state.chatStep) {
      ChatStepIdle(:final notice?, :final action) => (notice, action),
      _ => null,
    };
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
                    // The escrows of the order's other contracts (#188), whatever the view, a wait included (security review of #188, R3): an escrow paid for a contract the order moved on from is said until it is back, after the trade's end too.
                    if (widget.walletEarlierEscrows case final earlier?)
                      earlier(context),
                    switch (view) {
                      TradeWaiting(:final warnings)
                          when warnings.isEmpty && waitNotice == null =>
                        TradeFirstReadWait(coordinator: coordinator),
                      // A status that carries alerts while the screen waits (a read refused for terms changed): said, never a plain wait (#211); and what an action of the chat step gave meanwhile, never a silent wait (security review of #219, C2).
                      TradeWaiting(:final warnings) => _AlertedWait(
                        warnings: warnings,
                        madeHere: record.origin == TradeOrigin.madeHere,
                        coordinator: coordinator,
                        notice: waitNotice,
                      ),
                      TradeMessage(:final kind) => _Message(
                        // An end opened again whose read runs, or that the coordinator shows still running, is never said over (security review of #220, C1).
                        text: switch ((kind, state.watch)) {
                          (
                            TradeMessageKind.ended,
                            TradeWatchStatus(endReread: TradeEndReading()),
                          ) =>
                            l10n.p2pTradeEndReading(coordinator),
                          (
                            TradeMessageKind.ended,
                            TradeWatchStatus(
                              endReread: TradeEndShownAlive() ||
                                  TradeEndNotRead() ||
                                  TradeEndUnknownToCoordinator(),
                              :final record,
                              :final seen,
                            ),
                          ) =>
                            l10n.p2pTradeEndKeptEnded(
                              _date(
                                l10n,
                                record.closedAt ?? seen.status.seenAt,
                              ),
                            ),
                          _ => kind.toText(context, coordinator: coordinator),
                        },
                        below: kind == TradeMessageKind.ended
                            ? _renewUnderEnd(record, state.watch)
                            : null,
                        waits:
                            kind == TradeMessageKind.takePending ||
                            (kind == TradeMessageKind.ended &&
                                _readingEnd(state.watch)),
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
                        pause: state.pause,
                        pauseUncertainty: state.pauseUncertainty,
                        actionRunning: state.actionRunning,
                        offersPause: context.read<TradeCubit>().offersPause,
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
                        rateCubit: widget.checksPayoutRate
                            ? context.read<PayoutRateCubit>()
                            : null,
                        trade: context.read<TradeCubit>(),
                        onRetryRate: widget.checksPayoutRate
                            ? () => unawaited(
                                context.read<PayoutRateCubit>().retry(),
                              )
                            : null,
                        beforeAct: widget.checksPayoutRate
                            ? context.read<PayoutRateCubit>().beforeAct
                            : null,
                        onRenew: _renewalOf(record, contract.seen),
                        renewing: _renewing,
                      ),
                    },
                    // The end read again with other terms, said under its panel (functional review of #220, R10).
                    ..._endRereadTail(context, state, coordinator),
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
      // An end opened again whose one read did not show it as kept (#216, functional review of #220, C1): what that read gave, each in its own words, never as if read again; an answer otherwise, under the state machine's alerts of it in their usual words, and nothing reassuring beside them.
      if (watch case TradeWatchStatus(
        :final endReread?,
        :final record,
        :final seen,
      ))
        ..._endRereadLines(
          context,
          endReread,
          record: record,
          date: _date(l10n, record.closedAt ?? seen.status.seenAt),
          coordinator: coordinator,
        ),
      // Where a renewal is offered (#216, #217): the terms kept here, and an order made since with them.
      if (watch case TradeWatchStatus(
        :final record,
        :final seen,
      ) when _renewalOf(record, seen) != null)
        ..._renewalLines(context, record),
    ];
  }

  /// « Renew Order » or « Renew » under « This trade is over for this robot. »: an end opened again shown as the records hold it has no panel of its end, so the renewal its records allow is offered under that text, in the reference's words of that end, as under the expiry's reason (#216, functional review of #220, R7); `null` where none is offered.
  Widget? _renewUnderEnd(TradeRecord record, TradeWatchState? watch) {
    if (watch is! TradeWatchStatus) return null;
    final renew = _renewalOf(record, watch.seen);
    if (renew == null) return null;
    final l10n = P2pLocalizations.of(context);
    return TradeButton(
      key: const ValueKey('trade-renew'),
      label: watch.seen.status.position == TradePosition.succeeded
          ? l10n.p2pRenew
          : l10n.p2pRenewOrder,
      outlined: true,
      busy: _renewing,
      onPressed: renew,
    );
  }

  /// The date and time of [at], in the user's language.
  static String _date(P2pLocalizations l10n, DateTime at) =>
      DateFormat.yMMMd(l10n.localeName).add_Hm().format(at.toLocal());

  /// What the one read of an end opened again gave, when it did not show that end as kept (#216, functional review of #220, C1): no answer; an order the coordinator does not know; or an answer otherwise, the state machine's alerts of it first, with the advice given an order made here for any alert, then that the coordinator shows the order otherwise.
  List<Widget> _endRereadLines(
    BuildContext context,
    TradeEndReread reread, {
    required TradeRecord record,
    required String date,
    required String coordinator,
  }) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return switch (reread) {
      // Said by the message itself (« Reading this order again… »).
      TradeEndReading() => const [],
      TradeEndNotRead() => [
        _Line(
          l10n.p2pTradeEndNotRead(coordinator, date),
          color: colors.warning,
        ),
      ],
      TradeEndUnknownToCoordinator() => [
        _Line(
          l10n.p2pTradeEndUnknown(coordinator, date),
          color: colors.warning,
        ),
      ],
      // The order possibly still under way at the coordinator, its record closed here (security review of #220, C1): an alert, in the colour of one.
      TradeEndShownAlive() => [
        _Line(
          l10n.p2pTradeEndAlive(coordinator),
          color: colors.error,
          icon: Icons.warning_amber,
          live: true,
        ),
      ],
      // That very end with other terms: said under its panel, whose alert comes first (functional review of #220, R10).
      TradeEndShownOtherwise(asRead: true) => const [],
      TradeEndShownOtherwise(:final warnings) => [
        for (final warning in warnings)
          _warningLine(context, warning, coordinator),
        if (record.origin == TradeOrigin.madeHere)
          _Line(
            l10n.p2pTradeBreachWhatToDo(coordinator),
            color: colors.warning,
            icon: Icons.info_outline,
          ),
        _Line(
          l10n.p2pTradeEndOtherwise(coordinator, date),
          color: colors.warning,
        ),
      ],
    };
  }

  /// Under the panel of an end read again with other terms (functional review of #220, R10): the advice given an order made here, then that the coordinator shows the order otherwise; nothing for any other status.
  List<Widget> _endRereadTail(
    BuildContext context,
    TradeScreenState state,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    if (state.watch case TradeWatchStatus(
      endReread: TradeEndShownOtherwise(asRead: true),
      :final record,
      :final seen,
    )) {
      return [
        if (record.origin == TradeOrigin.madeHere) ...[
          const Gap(BullSpacing.sm),
          _Line(
            l10n.p2pTradeBreachWhatToDo(coordinator),
            color: colors.warning,
            icon: Icons.info_outline,
          ),
        ],
        const Gap(BullSpacing.sm),
        _Line(
          l10n.p2pTradeEndOtherwise(
            coordinator,
            _date(l10n, record.closedAt ?? seen.status.seenAt),
          ),
          color: colors.warning,
        ),
      ];
    }
    return const [];
  }

  /// What the records say of the order of [record], where its renewal is offered (#216, #217): the terms kept here, with the day it was made; an order made here after it with the same terms, where this device saw it stand (only what is established, functional review of #220, R1), with a button that opens it; or that the records cannot tell, never « none ».
  List<Widget> _renewalLines(BuildContext context, TradeRecord record) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return switch (_renewalsSeen) {
      null || RenewalsReading() => const [],
      RenewalsUnknown() => [
        _Line(l10n.p2pSameTermsUnknown, color: colors.warning),
      ],
      RenewalsListed(:final renewals) => [
        _Line(
          l10n.p2pTradeKeptTerms(
            _date(l10n, record.takenAt),
            renewals.kept.summary(context),
          ),
          color: colors.textMuted,
        ),
        if (renewals.shown case final shown?) ...[
          _Line(
            l10n.p2pSameTermsMade(
              '${shown.record.orderId}',
              _standsText(l10n, shown),
            ),
            color: colors.warning,
            icon: Icons.info_outline,
          ),
          if (widget.onOpenTrade case final open?)
            TradeButton(
              key: const ValueKey('trade-same-terms-open'),
              label: l10n.p2pSameTermsOpen('${shown.record.orderId}'),
              outlined: true,
              onPressed: () => open(shown.record),
            ),
        ],
        if (renewals.pendingSameTerms)
          _Line(
            l10n.p2pSameTermsPending,
            color: colors.warning,
            icon: Icons.info_outline,
          ),
      ],
    };
  }
}

/// A message shown alone, as the official client shows the coordinator's message on the order page; [waits] adds the bar of a wait.
class _Message extends StatelessWidget {
  final String text;
  final bool waits;

  /// What an action of the chat step gave, when the order it was sent for is now shown as a message (cancelled, ended): said under it, as the reference says its `bad_request` whatever the status (#95).
  final (ChatStepNotice, ChatStepAction)? notice;
  final String coordinator;

  /// What comes under the text: the renewal of an end shown as the records hold it (#216); `null` for none.
  final Widget? below;

  const _Message({
    required this.text,
    required this.waits,
    this.notice,
    required this.coordinator,
    this.below,
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
          if (below case final below?) ...[const Gap(BullSpacing.md), below],
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

  /// Where a pause or an unpause stands (#184), whether any action of the trade runs, and whether the screen offers the pause at all ([TradeCubit.offersPause]).
  final TradePauseState pause;

  /// What stays uncertain after a pause or an unpause whose outcome was unknown (security review of #184, C1 and C2).
  final PauseUncertainty? pauseUncertainty;
  final bool actionRunning;
  final bool offersPause;
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

  /// The rule's cubit, `null` without the wallet's port: what the dialog of « Confirm … sent » reads when it opens and follows while open (security review of #208, C1).
  final PayoutRateCubit? rateCubit;

  /// The trade's cubit: the order the dialog of « Confirm … sent » computes its gap line from when it opens and while open, the one the screen shows (#209).
  final TradeCubit trade;
  final VoidCallback? onRetryRate;

  /// Before « Submit » and the dialog of « Confirm … sent »: the rule's price read again when old ([PayoutRateCubit.beforeAct]), `false` stopping the press; `null` without the rule.
  final Future<bool> Function()? beforeAct;

  /// « Renew Order » at 5, « Renew » at « Trade finished! » (#185): `null` where not offered; spinning and off while [renewing].
  final VoidCallback? onRenew;
  final bool renewing;

  const _Contract({
    super.key,
    required this.contract,
    required this.now,
    required this.record,
    required this.cancel,
    required this.chatStep,
    required this.pause,
    required this.pauseUncertainty,
    required this.actionRunning,
    required this.offersPause,
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
    required this.rateCubit,
    required this.trade,
    required this.onRetryRate,
    required this.beforeAct,
    required this.onRenew,
    required this.renewing,
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
    // How the bond and the escrow were paid, as the trade's payment records tell: « Cancel » and the line under a bond returned (#207).
    final paid = walletBond?.call(context) ?? WalletBondState.none;
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
          _warningLine(context, warning, coordinator),
          const Gap(BullSpacing.sm),
        ],
        // The trace of terms the coordinator showed otherwise, then put back (#231): said until the trade ends.
        if (termsShownOtherwise(
              context,
              status,
              coordinator,
              own: contract.seen.ownPremium,
            )
            case final trace?) ...[
          _Line(
            trace,
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const Gap(BullSpacing.sm),
        ],
        // An order made here whose coordinator contradicted the trade's history (a breach): what to do (design note § 6, row 8, #182).
        if (record.origin == TradeOrigin.madeHere &&
            (status.trail.breached ||
                status.has<CoordinatorInconsistent>())) ...[
          _Line(
            l10n.p2pTradeBreachWhatToDo(coordinator),
            color: colors.warning,
            icon: Icons.info_outline,
          ),
          const Gap(BullSpacing.sm),
        ],
        _prompt(context, status, paid),
        // The pause button or « Unpause Order » off while a cancel runs: said why (functional review of #184, B1).
        if (offersPause &&
            (contract.prompt == TradePrompt.publicWait ||
                contract.prompt == TradePrompt.paused) &&
            cancel is CancelRunning &&
            pause is! PauseRunning) ...[
          const Gap(BullSpacing.sm),
          _Line(
            l10n.p2pTradePauseWhileCancel,
            color: colors.textMuted,
            center: true,
            live: true,
          ),
        ],
        // A cancel waiting for a pause of the order to end, behind the order's lock: said (security review of #184, R3).
        if (cancel is CancelRunning && pause is PauseRunning) ...[
          const Gap(BullSpacing.sm),
          _Line(
            l10n.p2pTradeCancelAfterPause,
            color: colors.textMuted,
            center: true,
            live: true,
          ),
        ],
        // A pause or an unpause that has run [TradeCubit.stillWaitingAfter]: what it waits for (#184).
        if (pause case PauseRunning(waitedLong: true)) ...[
          const Gap(BullSpacing.sm),
          _Line(
            l10n.p2pRobotStillWaiting(coordinator),
            color: colors.textMuted,
            center: true,
            live: true,
          ),
        ],
        // What a pause or an unpause gave (#184), under the prompt of whatever status the order is now read at: the order may have been taken or expired meanwhile.
        if (pause case PauseIdle(:final notice?, :final wanted)) ...[
          const Gap(BullSpacing.md),
          _PauseNoticeLines(
            notice: notice,
            wanted: wanted,
            seen: contract.seen,
            coordinator: coordinator,
          ),
        ],
        // A pause or an unpause whose outcome was unknown, from this screen or another of the run, while the order is read public or paused: counted as possibly public until a read sent after the request shows it paused, then a reserve until a second read, minutes later, still does (security review of #184, C1 and C2).
        if (_uncertainLine(l10n) case final line?) ...[
          const Gap(BullSpacing.sm),
          _Line(
            line,
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
            live: true,
          ),
        ],
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
          _BondLine(
            line: contract.bondLine,
            maker: contract.maker,
            swapLine: _backThroughSwap(l10n, paid),
          ),
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
            bond: paid,
          ),
        ],
      ],
    );
  }

  /// The line of what stays uncertain, while the order is read public or paused; `null` for none.
  String? _uncertainLine(P2pLocalizations l10n) {
    final uncertain = pauseUncertainty;
    if (uncertain == null || contract.status is! MakerOrderPublic) return null;
    return uncertain.pausedSinceRequest
        ? l10n.p2pTradePauseMayStillArrive
        : l10n.p2pTradeMayBePublic;
  }

  /// The pause button of `Prompts/PublicWait.tsx` at 1, or « Unpause Order » of `Prompts/Paused.tsx` at 2 (#184): one tap, no dialog, as the reference (`TradeBox/index.tsx:310-313`); spinning while its request runs (`LoadingButton loading={pauseLoading}`), off while another action of the trade runs. It hands the cubit the status shown at the tap, which the use case reads again before sending anything.
  Widget _pauseButton(BuildContext context) => _PauseButton(
    seen: contract.seen,
    paused: contract.prompt == TradePrompt.paused,
    running: pause is PauseRunning,
    blocked: actionRunning && pause is! PauseRunning,
  );

  Widget _prompt(
    BuildContext context,
    TradeStatus status,
    WalletBondState paid,
  ) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
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
      // A maker's public order (#182): `Prompts/PublicWait.tsx`, with its pause button (#184).
      (TradePrompt.publicWait, _) => _PublicWait(
        order: order,
        book: book,
        escrowDuration: order?.escrowDuration,
        swapLine: _backThroughSwap(l10n, paid),
        pauseButton: offersPause ? _pauseButton(context) : null,
      ),
      // A maker's paused order (#182): `Prompts/Paused.tsx`'s text and « Unpause Order » (#184).
      (TradePrompt.paused, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // « At the moment it cannot be seen or taken by other robots »: not said while anything stays uncertain after a pause or an unpause whose outcome is unknown, neither while the order may be public (the status shown coming from a read sent before the request, security review of #184, C1) nor while a request still on its way could make it public again (the reserve, its R-b, #214): never beside the line that says so.
          if (pauseUncertainty == null) _Line(l10n.p2pTradePausedText),
          if (offersPause) ...[
            const Gap(BullSpacing.md),
            _pauseButton(context),
          ],
        ],
      ),
      (TradePrompt.payoutWait, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pTradePayoutWait),
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pTradePayoutWaitHangOn),
          // The reference's « you will get back the trade collateral and your bond automatically » is a taker's case: for a maker seller the collateral comes back, the order goes back to the book and its bond stays locked (`api/logics.py:445-458`, #188).
          if (record.origin == TradeOrigin.madeHere) ...[
            const Gap(BullSpacing.sm),
            _Line(
              l10n.p2pTradePayoutWaitMaker,
              color: colors.warning,
              icon: Icons.info_outline,
            ),
          ],
          // « you will get back the trade collateral and your bond »: both come back the same way when paid with this wallet; for a maker seller the collateral only.
          if (_backThroughSwap(
                l10n,
                record.origin == TradeOrigin.madeHere ? paid.escrowOnly : paid,
                escrow: true,
              )
              case final line?) ...[
            const Gap(BullSpacing.sm),
            _Line(line, color: colors.textMuted, icon: Icons.info_outline),
          ],
        ],
      ),
      (TradePrompt.payout, _) => _payoutPrompt(context, order),
      // 15: the payout panel, and since #237 the owner's payment rule once a new invoice is asked, as at 6 and 8: its lines above the panel where the panel does not say them.
      (TradePrompt.routingFailed, _) => _routingFailedPrompt(context),
      (TradePrompt.escrowWait, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Line(l10n.p2pTradeEscrowWait),
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pTradeEscrowWaitHangOn),
          // The reference's « you will get your bond back automatically » is a taker's case: for a maker the order goes back to the book, its bond locked (#182).
          if (record.origin == TradeOrigin.madeHere) ...[
            const Gap(BullSpacing.sm),
            _Line(
              l10n.p2pTradeEscrowWaitMaker,
              color: colors.warning,
              icon: Icons.info_outline,
            ),
          ] else if (_backThroughSwap(l10n, paid) case final line?) ...[
            const Gap(BullSpacing.sm),
            _Line(line, color: colors.textMuted, icon: Icons.info_outline),
          ],
        ],
      ),
      // The coordinator's expiry reason, then « Renew Order » for an order made here (`Prompts/Expired.tsx:31-97`, #185).
      (TradePrompt.expired, Expired(:final reason)) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reason != null) _Line(reason.toText(context), center: true),
          if (onRenew case final renew?) ...[
            if (reason != null) const Gap(BullSpacing.sm),
            TradeButton(
              key: const ValueKey('trade-renew'),
              label: l10n.p2pRenewOrder,
              outlined: true,
              busy: renewing,
              onPressed: renew,
            ),
          ],
        ],
      ),
      (TradePrompt.expired, _) => const SizedBox.shrink(),
      // The chat step (#95; the seller's, #96), with the chat panel (#93) in its place when the screen was given one.
      (TradePrompt.chat, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The owner's payment rule on a maker buyer's side, before « Confirm … sent » (#182), with its « Retry »; the gap under it, only without a comparison.
          ?_rateLines(context),
          if (_gapLine(context) case final gap?) ...[
            gap,
            const Gap(BullSpacing.sm),
          ],
          // Where this contract's payout came from, before « Confirm … sent » of a buyer (#204): nothing when from this wallet.
          if (payoutTraceOf(context, contract.seen, rule: _ruleShown)
              case final trace?) ...[
            _Line(
              trace,
              color: colors.warning,
              icon: Icons.warning_amber_rounded,
            ),
            const Gap(BullSpacing.sm),
          ],
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
            // Built from the rule's state and the trade's order when the dialog opens and at each change of either while open, never from this build's (security review of #208, C1; #209).
            rateLines: LiveDialogLines(
              of: (context) => _dialogLines(context, rateCubit?.state),
              alerts: _dialogAlerts,
              changes: _changesOf(rateCubit?.stream, trade.stream),
            ),
            beforeConfirmFiatSent: beforeAct,
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

  /// The rule's state for the step shown, `null` when it is another step's or there is none: never the check of a step before.
  PayoutRateState? get _ruleShown => _ruleOf(payoutRate, contract.status);

  /// [state] when it is the rule's state for the step of [status], `null` otherwise.
  static PayoutRateState? _ruleOf(PayoutRateState? state, TradeStatus status) {
    final shown = PayoutRateStep.of(status);
    final step = switch (state) {
      PayoutRateReading(:final step) ||
      PayoutRateChecked(:final step) ||
      PayoutRateSatsMissing(:final step) ||
      PayoutRateAmountsDisagree(:final step) ||
      PayoutRateAlertAlone(:final step) ||
      PayoutRateTermsUnread(:final step) => step,
      _ => null,
    };
    if (step == null || step != shown) return null;
    return state;
  }

  /// The payout's prompt at 6 and 8 (`Prompts/Payout.tsx`): its text, the owner's payment rule before « Submit » (#182) where the payout panel does not say it, the gap from the creation's rate only without a comparison with the Bull wallet's price, then the payout panel. Where the panel is drawn, the rule's check at 6 and 8 is the panel's breakdown's (its gap line, its alert, its detail, #228, #250): not said above it, no banner.
  Widget _payoutPrompt(BuildContext context, CoordinatorOrder? order) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final panel = _payoutPanel(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order != null) ...[
          _Line(switch (_payoutPromptAmount(order)) {
            final amount? => l10n.p2pTradePayoutPrompt(
              formats.payoutAmount(amount, inBitcoin: order.currency.isBitcoin),
              order.currency.isBitcoin ? l10n.p2pSatsUnit : order.currency.code,
            ),
            null => l10n.p2pTradePayoutPromptNoAmount,
          }),
          const Gap(BullSpacing.sm),
        ],
        ?_rateLines(context, inPanel: panel != null),
        if (_gapLine(context) case final gap?) ...[
          gap,
          const Gap(BullSpacing.sm),
        ],
        ?panel,
      ],
    );
  }

  /// 15 (`Prompts/RoutingFailed.tsx`): the payout panel and, once a new invoice is asked, the owner's payment rule (#237: the same figures as at 6 and 8, design note § 3.3 bis), said in the panel's breakdown where it is drawn and above it otherwise.
  Widget _routingFailedPrompt(BuildContext context) {
    final panel = _payoutPanel(context);
    final rule = _rateLines(context, inPanel: panel != null);
    if (rule == null) return panel ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [rule, ?panel],
    );
  }

  /// The amount « Before letting you send … » names (`Prompts/Payout.tsx`): for an order made here, the contract's amount as asked here ([TradeSeen.contractAmountShown]); none, and the prompt without a figure, when it is not known or the order read shows another (security review of #183, C2, C4). A taker's as before: the amount its take chose, or the order's.
  double? _payoutPromptAmount(CoordinatorOrder order) {
    if (!contract.maker) {
      return (order.takenAmount ?? order.amount.max).value;
    }
    return contract.seen.contractAmountShown?.value;
  }

  /// What the screen shows now, as the trade's cubit holds it (`TradeView.of` of its last state, the screen's own).
  TradeView get _viewNow => TradeView.of(trade.state.watch);

  /// The alerts « Confirm … sent » says first, those the screen shows now, in its words and its colours (security review of #219, C2): under a contract, the state machine's warnings of its status and, for an order made here whose coordinator broke the trade's history, what to do; above a wait, the alerts of the status it waits on and, for an order made here, what to do; a message shown alone, that message. Never the rule's « do not add up » in their place: the warnings name the cause (terms changed, amounts that do not add up, a status refused).
  List<TradeDialogLine> _dialogAlerts(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    TradeDialogLine alertOf(TradeWarning warning) => (
      text: warning.toText(context, coordinator: coordinator),
      tone: warning is ContractSeenLate
          ? TradeDialogTone.plain
          : TradeDialogTone.warning,
    );
    final advice = (
      text: l10n.p2pTradeBreachWhatToDo(coordinator),
      tone: TradeDialogTone.warning,
    );
    final madeHere = record.origin == TradeOrigin.madeHere;
    return switch (_viewNow) {
      TradeContract(:final status, :final seen) => [
        for (final warning in warningsOf(status, now: clock()))
          alertOf(warning),
        // The trace of terms shown otherwise (#231) and where this contract's payout came from (#204), as the screen says them.
        if (termsShownOtherwise(
              context,
              status,
              coordinator,
              own: seen.ownPremium,
            )
            case final trace?)
          (text: trace, tone: TradeDialogTone.warning),
        if (payoutTraceOf(
              context,
              seen,
              rule: _ruleOf(rateCubit?.state, status),
            )
            case final trace?)
          (text: trace, tone: TradeDialogTone.warning),
        if (madeHere &&
            (status.trail.breached || status.has<CoordinatorInconsistent>()))
          advice,
      ],
      TradeWaiting(:final warnings) => [
        for (final warning in warnings) alertOf(warning),
        if (madeHere && warnings.any((warning) => warning is! ContractSeenLate))
          advice,
      ],
      TradeMessage(:final kind) => [
        (
          text: kind.toText(context, coordinator: coordinator),
          tone: TradeDialogTone.warning,
        ),
      ],
      TradeOrderOnly() => const [],
    };
  }

  /// The lines « Confirm … sent » says after the reference's text for a maker buyer (#182), from the status the screen shows now, never the press's (#209; security review of #219, C1): the rule's lines for the step of that status only, none when it shows another step or no contract (a wait, a message); and, only where the rule does not run, the gap from the creation's rate, in the warning colour when it is against the buyer (#234: never beside « rate not checked »).
  List<TradeDialogLine> _dialogLines(
    BuildContext context,
    PayoutRateState? now,
  ) {
    final shown = switch (_viewNow) {
      TradeContract(:final seen) => seen,
      _ => null,
    };
    if (shown == null) return const [];
    final state = _ruleOf(now, shown.status);
    // As on the screen: only where the rule is not on the page (#234).
    final gap = rateCubit == null ? _gapOf(context, shown) : null;
    return [
      if (state != null)
        ...PayoutRateLines.linesOf(
          context,
          state,
          coordinator: coordinator,
          amount: PayoutRateLines.amountOf(context, shown),
        ),
      if (gap != null)
        (
          text: gap.text,
          tone: gap.gap.effectFor(gap.role) == RateGapEffect.unfavourable
              ? TradeDialogTone.warning
              : TradeDialogTone.plain,
        ),
    ];
  }

  /// The lines of the owner's payment rule for the step shown, with their « Retry » (#182); `null` where there are none. With [inPanel] (the payout panel drawn under them at 6 and 8), the rule's check of the sats paid is the panel's breakdown's (#250).
  Widget? _rateLines(BuildContext context, {bool inPanel = false}) {
    final state = _ruleShown;
    if (state == null || state is PayoutRateNone) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.sm),
      child: PayoutRateLines(
        state: state,
        coordinator: coordinator,
        amount: PayoutRateLines.amountOf(context, contract.seen),
        onRetry: onRetryRate,
        // At 6 and 8 the payout panel's breakdown says the rule's check (#228, #250), only where the panel is drawn.
        comparisonInBreakdown: inPanel,
      ),
    );
  }

  /// The line of the gap of a maker buyer's contract at 6, 8 and 9 ([RateGapLine]), only where the owner's rule is not on the page ([rateCubit] `null`: no wallet's port lent, a composition the app does not use): one mechanism, so never beside a comparison, « rate not checked » or a currency the Bull wallet does not price, nor before the rule's first answer (#234); `null` for a taker, whose statuses carry no gap, and for a maker seller ([_gapOf]).
  Widget? _gapLine(BuildContext context) {
    // The rule is on this page (a wallet's port lent): no gap from the creation's rate, whatever it says or before it says anything (#234; its functional review, R4).
    if (rateCubit != null) return null;
    final gap = _gapOf(context, contract.seen);
    if (gap == null) return null;
    return RateGapLine(gap: gap.gap, role: gap.role, text: gap.text);
  }

  /// The gap of a maker buyer's contract at 6, 8 and 9, its role and its words, from [seen]'s status's own figure and the order it was read from. Never a seller's: the owner's rule runs for a buyer only (`PayoutRateStep.of`), a maker seller's escrow is compared at its confirmation (#188), and at 9 a seller has nothing to compare: no figure of the creation's price is said to a seller (functional review of #234, C1).
  ({TradeRateGap gap, TradeRole role, String text})? _gapOf(
    BuildContext context,
    TradeSeen seen,
  ) {
    final status = seen.status;
    final order = seen.order;
    // A contract shown with another amount than the one asked here: the state machine's alert alone, no gap beside it (C5 and C4 of #183).
    if (seen.contractAmountMoved) return null;
    final (gap, role, amount) = switch (status) {
      WaitingForBoth(:final rateGap, role: TradeRole.buyer) ||
      WaitingForPayout(:final rateGap, role: TradeRole.buyer) => (
        rateGap,
        TradeRole.buyer,
        // The contract's amount the gap is computed with, as asked here (#183), never the read's alone.
        seen.contractAmountShown,
      ),
      Chatting(
        :final rateGap,
        role: TradeRole.buyer,
        fiatSent: false,
        :final amount,
      ) =>
        (rateGap, TradeRole.buyer, amount),
      _ => (null, record.role, null),
    };
    final sats = order?.satoshisNow;
    if (gap == null || amount == null || sats == null || order == null) {
      return null;
    }
    return (
      gap: gap,
      role: role,
      text: RateGapLine.textOf(
        context,
        gap: gap,
        coordinator: coordinator,
        sats: sats,
        amount: amount,
        currency: order.currency,
      ),
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
    onRenew: onRenew,
    renewing: renewing,
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
      beforeSubmit: beforeAct,
      // The rule's check of the step shown, for the breakdown's gap line, its alert and its detail (#228, #250): only at 6, 8 and, since #237, 15.
      check: PayoutRateLines.checkOf(
        context,
        _ruleShown,
        amount: PayoutRateLines.amountOf(context, contract.seen),
      ),
      onRetry: onRetryRate,
      // The rule runs on this page, at 15 too since #237: the breakdown no longer says it is not compared there.
      checkedByRule: rateCubit != null,
    ),
  )) {
    final panel? => KeyedSubtree(
      key: const ValueKey('trade-payout-panel'),
      child: panel,
    ),
    null => null,
  };
}

/// The line of the trace a coordinator left by showing this trade with other terms than its own, then putting them back (#231; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis): from when (the first read that showed other terms), and the premiums reads showed, never less than was seen (security reviews of schema 9, C1, R8): up to the highest when all were above [own], down to the lowest when all were below, both when on both sides, [own] being the trade's own from its terms kept here (`TradeSeen.ownPremium`, R1; `null`, the premiums shown alone); `null` without a trace, once the trade ended (an end is no longer a step to act on), or while the status shown carries `TradeTermsChanged` itself, whose own alert speaks.
String? termsShownOtherwise(
  BuildContext context,
  TradeStatus status,
  String coordinator, {
  required Premium? own,
}) {
  final at = status.trail.termsChangedAt;
  // Drawn exactly when `ShownAlerts.termsTrace` says so: the one rule of what counts as an alert beside a comparison (#249).
  if (at == null || !ShownAlerts.termsTrace(status)) return null;
  final l10n = P2pLocalizations.of(context);
  final formats = P2pFormats.of(context);
  final day = formats.day(at);
  final time = formats.time(at);
  // A premium the trail holds is bounded (`TradeTrail.restore`): never below the package's minimum.
  String percent(double value) => switch (Premium.tryCreate(value)) {
    final premium? => formats.premium(premium),
    null => formats.number(value),
  };
  final low = status.trail.termsChangedPremiumLow;
  final high = status.trail.termsChangedPremiumHigh;
  if (low == null || high == null) {
    return l10n.p2pTermsShownOther(coordinator, day, time);
  }
  final ownPercent = own?.percent;
  if (ownPercent == null) {
    return low == high
        ? l10n.p2pTermsShownPremiumAlone(coordinator, day, time, percent(low))
        : l10n.p2pTermsShownPremiums(
            coordinator,
            day,
            time,
            percent(low),
            percent(high),
          );
  }
  final ownText = percent(ownPercent);
  return switch ((low < ownPercent, high > ownPercent)) {
    (true, true) => l10n.p2pTermsShownBoth(
      coordinator,
      day,
      time,
      percent(low),
      percent(high),
      ownText,
    ),
    (true, false) => l10n.p2pTermsShownBelow(
      coordinator,
      day,
      time,
      percent(low),
      ownText,
    ),
    (false, _) => l10n.p2pTermsShownAbove(
      coordinator,
      day,
      time,
      percent(high),
      ownText,
    ),
  };
}

/// The line of where the payout of the contract shown came from, before « Confirm … sent » of a buyer (#204; design note § 3.5 bis): pasted, not given from this device, or not known (a contract under way before payouts were recorded, records that cannot be read, a trace not read); `null` when it was given from this wallet, for a seller, where « Confirm … sent » is not the step, or when [rule], the owner's payment rule for the step shown, already says in red that this app never saw the contract's payout invoice (`p2pPayoutRateNotSeen`, a contract seen late), which says more: an alert is said alone (functional review of schema 9, C2).
String? payoutTraceOf(
  BuildContext context,
  TradeSeen seen, {
  required PayoutRateState? rule,
}) {
  // Drawn exactly when `ShownAlerts.payoutTrace` says so (the one rule of what counts as an alert beside a comparison, #249), but where the rule's own red line says the invoice was never seen here.
  if (!ShownAlerts.payoutTrace(seen) || _saysPayoutNotSeen(rule)) return null;
  final l10n = P2pLocalizations.of(context);
  return switch (seen.payout) {
    PayoutFromThisWallet() => null,
    PayoutPasted(kind: PayoutTraceKind.invoice) => l10n.p2pPayoutTracePasted,
    PayoutPasted(kind: PayoutTraceKind.address) =>
      l10n.p2pPayoutTracePastedAddress,
    PayoutNotGivenHere() => l10n.p2pPayoutTraceNotGivenHere,
    // A trace not read is said as unknown, never silence, which says « from this wallet » (security review of schema 9, R6).
    null ||
    PayoutUnrecorded() ||
    PayoutTraceUnreadable() => l10n.p2pPayoutTraceUnknown,
  };
}

/// Whether [rule] says in red that this app never saw the payout invoice of the contract (`PayoutRateLines`, `p2pPayoutRateNotSeen`).
bool _saysPayoutNotSeen(PayoutRateState? rule) => switch (rule) {
  PayoutRateSatsMissing(notSeen: true) ||
  PayoutRateAmountsDisagree(notSeen: true) ||
  PayoutRateChecked(basis: PayoutRateNotSeen()) => true,
  _ => false,
};

/// The line of [warning] under a contract's title or above the wait (#211): a next contract seen late is information, not an alert (#178, #182), its own words in the text colour; every other in the warning colour.
Widget _warningLine(
  BuildContext context,
  TradeWarning warning,
  String coordinator,
) => warning is ContractSeenLate
    ? _Line(
        warning.toText(context, coordinator: coordinator),
        icon: Icons.info_outline,
      )
    : _Line(
        warning.toText(context, coordinator: coordinator),
        color: context.bull.warning,
        icon: Icons.warning_amber_rounded,
      );

/// The wait of a status that carries alerts (#211): each alert, with the words it has under a contract, then, for an order made here, what to do (open it in the official app), then the wait itself, then what an action of the chat step gave meanwhile; nothing to tap, nothing blocked.
class _AlertedWait extends StatelessWidget {
  final List<TradeWarning> warnings;
  final bool madeHere;
  final String coordinator;

  /// What an action of the chat step gave, said under the wait (security review of #219, C2); `null` for none.
  final (ChatStepNotice, ChatStepAction)? notice;

  const _AlertedWait({
    required this.warnings,
    required this.madeHere,
    required this.coordinator,
    this.notice,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final warning in warnings) ...[
        _warningLine(context, warning, coordinator),
        const Gap(BullSpacing.sm),
      ],
      // The advice the contract gives an order made here whose coordinator broke the trade's history (design note § 6, row 8, #182), here for any alert: the screen can show nothing else of the order while it waits.
      if (madeHere && warnings.any((warning) => warning is! ContractSeenLate))
        _Line(
          P2pLocalizations.of(context).p2pTradeBreachWhatToDo(coordinator),
          color: context.bull.warning,
          icon: Icons.info_outline,
        ),
      TradeFirstReadWait(coordinator: coordinator),
      if (notice case (final notice, final action))
        ChatStepNoticeLine(
          notice: notice,
          coordinator: coordinator,
          action: action,
        ),
    ],
  );
}

/// Each change of the rule's state ([rule], none without the wallet's port) and of the trade's ([trade]), as one stream: each listener is subscribed to both, and cancelled from both (#209).
Stream<Object?> _changesOf(Stream<Object?>? rule, Stream<Object?> trade) =>
    Stream<Object?>.multi((controller) {
      final subscriptions = [
        ?rule?.listen(controller.add),
        trade.listen(controller.add),
      ];
      controller.onCancel = () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]);
    });

/// The project's line under a text of the reference that says a bond is returned (and, at 8 for a seller, the collateral too: [escrow]), from how the trade's payment records say each was paid ([paid], functional review of #182, U2, #207): named when paid with this wallet, said as a condition (true in every case) when the records cannot tell, `null` when neither was paid with this wallet or without the wallet's port.
String? _backThroughSwap(
  P2pLocalizations l10n,
  WalletBondState paid, {
  bool escrow = false,
}) {
  final bond = paid.bondPaid;
  final collateral = escrow ? paid.escrowPaid : WalletPaidHere.no;
  if (collateral == WalletPaidHere.cannotTell) {
    return l10n.p2pTradeBondOrEscrowBackThroughSwap;
  }
  if (bond == WalletPaidHere.cannotTell) {
    return collateral == WalletPaidHere.yes
        ? l10n.p2pTradeBondOrEscrowBackThroughSwap
        : l10n.p2pTradeBondBackThroughSwap;
  }
  return switch ((bond, collateral)) {
    (WalletPaidHere.yes, WalletPaidHere.yes) => l10n.p2pTradeBothPaidHereBack,
    (WalletPaidHere.yes, _) => l10n.p2pTradeBondPaidHereBack,
    (_, WalletPaidHere.yes) => l10n.p2pTradeEscrowPaidHereBack,
    _ => null,
  };
}

/// « Your taker bond is locked / unlocked / settled », « Your maker bond is … » for a maker (`BondStatus.tsx:39`, #182), with the reference's icons (`TradeBox/BondStatus.tsx`).
class _BondLine extends StatelessWidget {
  final TradeBondLine line;
  final bool maker;

  /// The line under « … bond is unlocked » of a bond paid with this wallet ([_backThroughSwap]), `null` for none.
  final String? swapLine;

  const _BondLine({
    required this.line,
    required this.maker,
    required this.swapLine,
  });

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
    final row = Row(
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
    final swapLine = this.swapLine;
    if (line != TradeBondLine.unlocked || swapLine == null) return row;
    // A bond « unlocked » by the coordinator comes back to this wallet through the swap service when paid with it (#182, second review; #207).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const Gap(BullSpacing.xs),
        _Line(swapLine, color: colors.textMuted, center: true),
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
            // A maker's public or paused order whose status moved before the cancel (1020, after a pause or an unpause it waited for): what to do (security review of #184, R1).
            _movedPublicOrPaused(notice)
                ? l10n.p2pTradeCancelMovedOnTapAgain
                : notice.toText(context, coordinator: coordinator),
            color: colors.error,
            center: true,
            live: true,
          ),
          if (_movedPublicOrPaused(notice) &&
              showsPublicOrder(widget.seen)) ...[
            const Gap(BullSpacing.sm),
            _Line(
              l10n.p2pTradeStillPublic,
              color: colors.warning,
              icon: Icons.warning_amber_rounded,
              live: true,
            ),
          ],
        ],
      ],
    );
  }

  /// Whether [notice] is a refusal of the coordinator because the status moved (1020), for an order made here now read public or paused.
  bool _movedPublicOrPaused(TradeCancelNotice notice) =>
      notice is CancelWasNotDone &&
      notice.cause is OrderStatusChanged &&
      widget.record.origin == TradeOrigin.madeHere &&
      widget.seen.status is MakerOrderPublic;
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

/// « Your order is public » (`TradeBox/Prompts/PublicWait.tsx:80-147`, #182): the reference's two lines, then « Public orders for {{currencyCode}} » with its count and the pause button (#184), and « Premium rank » with its share, computed from the book of the tab ([PublicWaitStanding]). Without an order read, the lines alone; without a book received, no figure, the pause button alone under the lines.
class _PublicWait extends StatelessWidget {
  final CoordinatorOrder? order;
  final List<PublicOrder>? book;
  final Duration? escrowDuration;

  /// The line under « your bond will return to you » of a bond paid with this wallet ([_backThroughSwap]), `null` for none.
  final String? swapLine;

  /// The pause button (#184), beside « Public orders for {{currencyCode}} » as the reference puts it (`Prompts/PublicWait.tsx:101-133`), or under the lines when that figure is not shown; `null` where the screen offers no pause.
  final Widget? pauseButton;

  const _PublicWait({
    required this.order,
    required this.book,
    required this.escrowDuration,
    required this.swapLine,
    required this.pauseButton,
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
        // The reference's box rings; this app neither rings nor follows the order outside this screen (#182, functional review), said before the order's first read too.
        _Line(
          l10n.p2pTradeNoRingYet,
          color: colors.warning,
          icon: Icons.info_outline,
        ),
        const Gap(BullSpacing.sm),
        _Line(l10n.p2pTradePublicExpiresUntaken),
        if (swapLine case final swapLine?) ...[
          const Gap(BullSpacing.sm),
          _Line(swapLine, color: colors.textMuted, icon: Icons.info_outline),
        ],
        if (order != null && standing != null) ...[
          Divider(height: BullSpacing.lg, color: colors.outlineVariant),
          Row(
            children: [
              Expanded(
                child: figure(
                  Icons.storefront,
                  formats.count(standing.similarOrders),
                  l10n.p2pTradePublicOrdersFor(order.currency.code),
                ),
              ),
              ?pauseButton,
            ],
          ),
          Divider(height: BullSpacing.lg, color: colors.outlineVariant),
          figure(
            Icons.percent,
            l10n.p2pTradePremiumRank(formats.number(standing.premiumRank)),
            l10n.p2pTradePremiumRankAmong(order.currency.code),
          ),
        ] else if (pauseButton case final pauseButton?) ...[
          Divider(height: BullSpacing.lg, color: colors.outlineVariant),
          Align(alignment: AlignmentDirectional.centerEnd, child: pauseButton),
        ],
      ],
    );
  }
}

/// The pause button of a maker's public order, an icon with the reference's tooltip « Pause the public order » (`Prompts/PublicWait.tsx:116-132`), or « Unpause Order » with its icon (`Prompts/Paused.tsx:30-35`) for a paused one (#184).
///
/// A tap hands [seen], the status shown, to [TradeCubit.pause], which does nothing while an action of the trade runs: a second tap, quick or not, sends nothing more. While it runs, the button spins and is off (after [TradeCubit.stillWaitingAfter], the prompt says what it waits for under it).
class _PauseButton extends StatelessWidget {
  final TradeSeen seen;

  /// « Unpause Order » rather than the pause icon.
  final bool paused;
  final bool running;

  /// Another action of the trade runs (a cancel): off, not spinning.
  final bool blocked;

  const _PauseButton({
    required this.seen,
    required this.paused,
    required this.running,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    void press() => unawaited(context.read<TradeCubit>().pause(seen));
    return paused
        // Busy, it ignores taps and keeps its colour, as the reference's loading button.
        ? TradeButton(
            label: l10n.p2pTradeUnpauseOrder,
            icon: Icons.play_circle,
            outlined: true,
            busy: running,
            onPressed: blocked ? null : press,
          )
        : IconButton(
            tooltip: l10n.p2pTradePauseOrder,
            iconSize: 36,
            color: colors.primary,
            onPressed: running || blocked ? null : press,
            icon: running
                ? SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  )
                : const Icon(Icons.pause_circle),
          );
  }
}

/// What a pause or an unpause gave (#184), in the app's words: the notice, then, when the user asked to pause, whether the order is public, so that an order the user believes paused and that can be taken is seen (design note § 3.4).
class _PauseNoticeLines extends StatelessWidget {
  final TradePauseNotice notice;
  final PauseWanted? wanted;

  /// The status shown now.
  final TradeSeen seen;
  final String coordinator;

  const _PauseNoticeLines({
    required this.notice,
    required this.wanted,
    required this.seen,
    required this.coordinator,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final notice = this.notice;
    if (notice is PausePublicAgain) {
      return _Line(
        notice.toText(context, coordinator: coordinator),
        color: colors.warning,
        icon: Icons.warning_amber_rounded,
        live: true,
      );
    }
    // Asked to pause, not done, and a stored read shows it public: said. An outcome unknown says « count on your order being public » through what stays uncertain, whatever was asked (`_uncertainLine`).
    final publicLine =
        wanted == PauseWanted.paused &&
            notice is! PauseWasUnknown &&
            showsPublicOrder(seen)
        ? l10n.p2pTradeStillPublic
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          notice.toText(context, coordinator: coordinator),
          color: colors.error,
          center: true,
          live: true,
        ),
        if (publicLine != null) ...[
          const Gap(BullSpacing.sm),
          _Line(
            publicLine,
            color: colors.warning,
            icon: Icons.warning_amber_rounded,
            live: true,
          ),
        ],
      ],
    );
  }
}
