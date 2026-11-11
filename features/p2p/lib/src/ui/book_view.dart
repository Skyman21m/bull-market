import 'dart:async';
import 'dart:math' as math;

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/book_filter.dart';
import '../domain/order_search.dart';
import '../presentation/book_cubit.dart';
import '../presentation/book_state.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/p2p_failure_l10n.dart';
import 'depth_chart_view.dart';
import 'search_order_dialog.dart';
import 'widgets/filter_choice.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/offer_row.dart';

/// The name of a coordinator, cleaned and bounded as every P2P screen shows it.
String _coordinatorName(Coordinator coordinator) => CoordinatorText.of(
  coordinator.longAlias,
  maxCodePoints: CoordinatorText.name,
);

/// The book of the P2P tab: the filter sentence, the state of each coordinator, one row per offer, and the choice of view.
///
/// The list is built lazily, so a book of thousands of orders only builds the rows on screen.
/// « Chart » shows the depth chart instead, as the official client does on a phone: without the filter sentence, whose currency and host it follows, and below the state of the coordinators.
class BookView extends StatefulWidget {
  final DateTime Function() now;
  final ValueChanged<PublicOrder> onOpenOrder;

  const BookView({super.key, required this.now, required this.onOpenOrder});

  @override
  State<BookView> createState() => _BookViewState();
}

class _BookViewState extends State<BookView> {
  late DateTime _now;

  /// Moves the expiry rings on: they show hours or minutes, so once a minute is enough.
  Timer? _ticker;

  /// How many times « Search » was chosen, the key that puts the view bar back on the view shown.
  int _searches = 0;

  /// The view shown: the list, or the depth chart.
  BookViewChoice _view = BookViewChoice.list;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() => _now = widget.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<BookCubit>();
    final state = context.watch<BookCubit>().state;
    return Column(
      children: [
        Expanded(
          child: BullRefreshIndicator(
            onRefresh: cubit.refresh,
            child: switch (_view) {
              BookViewChoice.list => CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: BookFilterSentence(state: state)),
                  SliverToBoxAdapter(child: CoordinatorsStatus(state: state)),
                  ..._content(context, state),
                ],
              ),
              BookViewChoice.chart => _chart(context, state),
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(BullSpacing.md),
          child: BullSegmented(
            // « Search » is not a view: once it is chosen the bar is built again on the view shown.
            key: ValueKey(_searches),
            items: {
              l10n.p2pBookViewList,
              l10n.p2pBookViewChart,
              l10n.p2pBookViewMap,
              l10n.p2pCommonSearch,
            },
            initialValue: switch (_view) {
              BookViewChoice.list => l10n.p2pBookViewList,
              BookViewChoice.chart => l10n.p2pBookViewChart,
            },
            disabledItems: {l10n.p2pBookViewMap},
            onSelected: (item) {
              if (item == l10n.p2pCommonSearch) {
                unawaited(_searchOrder());
              } else if (item == l10n.p2pBookViewList) {
                setState(() => _view = BookViewChoice.list);
              } else if (item == l10n.p2pBookViewChart) {
                setState(() => _view = BookViewChoice.chart);
              }
            },
          ),
        ),
      ],
    );
  }

  /// « Search order »: opens the order the URL names when the book received it, and otherwise says that a robot is needed.
  Future<void> _searchOrder() async {
    setState(() => _searches++);
    final outcome = await SearchOrderDialog.show(
      context,
      context.read<BookCubit>().searchOrder,
    );
    if (!mounted) return;
    switch (outcome) {
      case OrderSearchFound(:final order):
        widget.onOpenOrder(order);
      case OrderSearchNeedsRobot():
        await NoRobotDialog.show(context);
      case OrderSearchInvalidUrl() || null:
        break;
    }
  }

  /// The least height of the depth chart: on a short screen it scrolls rather than shrinks.
  static const _chartMinHeight = 320.0;

  /// The state of the coordinators, as above the list, then the depth chart once an order has arrived, the wait before, or the empty book once no coordinator is still loading and one has answered.
  ///
  /// The state of the coordinators scrolls with the chart, which keeps at least [_chartMinHeight] below it whatever the size of the screen and of the text.
  /// A coordinator that failed is shown above with « Retry », whether the others gave orders or not: a failure is not an empty book.
  Widget _chart(BuildContext context, BookState state) {
    final colors = context.bull;
    final Widget content = state.receivedOrders.isNotEmpty
        ? DepthChartView(state: state, onOpenOrder: widget.onOpenOrder)
        : state.isWaitingForFirstBook || state.loadingCoordinators.isNotEmpty
        ? Center(child: CircularProgressIndicator(color: colors.primary))
        : state.hasAnswer
        ? EmptyBook(state: state)
        : const SizedBox.shrink();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: CoordinatorsStatus(state: state)),
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: SizedBox(
              height: math.max(
                constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent,
                _chartMinHeight,
              ),
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, BookState state) {
    final colors = context.bull;
    if (state.orders.isNotEmpty) {
      return [
        SliverList.separated(
          itemCount: state.orders.length,
          itemBuilder: (context, index) {
            final order = state.orders[index];
            return OfferRow(
              key: ValueKey((order.coordinator.shortAlias, order.id)),
              order: order,
              now: _now,
              onTap: () => widget.onOpenOrder(order),
            );
          },
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.outlineVariant),
        ),
      ];
    }
    if (state.isWaitingForFirstBook || state.loadingCoordinators.isNotEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: colors.primary),
          ),
        ),
      ];
    }
    // When every coordinator failed, their lines above and « Retry » say so: the book is not empty, it is unknown.
    if (!state.hasAnswer) return const [];
    return [
      SliverFillRemaining(hasScrollBody: false, child: EmptyBook(state: state)),
    ];
  }
}

/// The views of the book the bar below it offers; « Map » is not built yet and « Search » opens a dialog.
enum BookViewChoice { list, chart }

/// « I want to [Buy] and use [EUR] pay with [ANY] hosted by [ANY] »: each choice opens a list.
class BookFilterSentence extends StatelessWidget {
  final BookState state;

  const BookFilterSentence({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<BookCubit>();
    final filter = state.filter;
    final words = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textMuted);
    Widget word(String text) => Text(text, style: words);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BullSpacing.md,
        BullSpacing.xs,
        BullSpacing.md,
        BullSpacing.sm,
      ),
      child: Wrap(
        spacing: BullSpacing.xs,
        runSpacing: BullSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          word(l10n.p2pBookFilterIWantTo),
          FilterChoice(
            label: _sideLabel(filter.side, l10n),
            onTap: () async {
              final side = await _pick(
                context,
                title: l10n.p2pBookFilterSelectOrderType,
                options: BookSide.values,
                selected: filter.side,
                label: (side) => _sideLabel(side, l10n),
              );
              if (side != null) cubit.selectSide(side.value ?? BookSide.any);
            },
          ),
          word(l10n.p2pBookFilterAndUse),
          FilterChoice(
            label: filter.currency?.code ?? l10n.p2pBookFilterAny,
            onTap: () async {
              final currency = await _pick<RobosatsCurrency>(
                context,
                title: l10n.p2pBookFilterSelectCurrency,
                options: [
                  for (final currency in RobosatsCurrency.all)
                    if (!currency.isBitcoin) currency,
                ],
                selected: filter.currency,
                label: (currency) => currency.code,
                any: l10n.p2pBookFilterAny,
              );
              if (currency != null) cubit.selectCurrency(currency.value);
            },
          ),
          word(l10n.p2pBookFilterPayWith),
          FilterChoice(
            label: filter.paymentMethod ?? l10n.p2pBookFilterAny,
            onTap: () async {
              final method = await _pick<String>(
                context,
                title: l10n.p2pBookFilterSelectMethod,
                options: [
                  for (final method in filter.paymentMethodsIn(
                    state.receivedOrders,
                  ))
                    method.name,
                ],
                selected: filter.paymentMethod,
                label: (method) => method,
                any: l10n.p2pBookFilterAny,
              );
              if (method != null) cubit.selectPaymentMethod(method.value);
            },
          ),
          word(l10n.p2pBookFilterHostedBy),
          FilterChoice(
            label: switch (filter.host) {
              final host? => _coordinatorName(host),
              null => l10n.p2pBookFilterAny,
            },
            onTap: () async {
              final host = await _pick<Coordinator>(
                context,
                title: l10n.p2pBookFilterSelectHost,
                options: state.coordinators.keys.toList(),
                selected: filter.host,
                label: _coordinatorName,
                any: l10n.p2pBookFilterAny,
              );
              if (host != null) cubit.selectHost(host.value);
            },
          ),
        ],
      ),
    );
  }

  static String _sideLabel(BookSide side, P2pLocalizations l10n) =>
      switch (side) {
        BookSide.any => l10n.p2pBookFilterAny,
        BookSide.buy => l10n.p2pBookFilterBuy,
        BookSide.sell => l10n.p2pBookFilterSell,
      };

  /// Opens a list of [options], with [any] first when given; completes with the choice, or `null` when the list is closed without one.
  static Future<_Choice<T>?> _pick<T extends Object>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required T? selected,
    required String Function(T) label,
    String? any,
  }) => BullBottomSheet.show<_Choice<T>>(
    context: context,
    child: BullPickerSheet<_Choice<T>>(
      title: title,
      options: [
        if (any != null) _Choice<T>(null),
        for (final option in options) _Choice(option),
      ],
      isSelected: (choice) => choice.value == selected,
      label: (choice) => switch (choice.value) {
        final value? => label(value),
        null => any ?? '',
      },
    ),
  );
}

/// One option of a filter list, `null` standing for « ANY ».
final class _Choice<T extends Object> {
  final T? value;

  const _Choice(this.value);
}

/// The coordinators still loading, and those whose book failed with a way to ask them again: a failed coordinator never hides the others.
class CoordinatorsStatus extends StatelessWidget {
  final BookState state;

  const CoordinatorsStatus({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final loading = state.loadingCoordinators;
    final failed = state.failedCoordinators;
    if (loading.isEmpty && failed.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BullSpacing.md,
        0,
        BullSpacing.md,
        BullSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading.isNotEmpty && !state.isWaitingForFirstBook)
            Row(
              children: [
                SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textMuted,
                  ),
                ),
                const Gap(BullSpacing.xs),
                // A long line, or a large text size, wraps rather than overflows.
                Flexible(
                  child: Text(
                    l10n.p2pBookCoordinatorsLoading(loading.length),
                    style: text.labelMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          if (failed.isNotEmpty) ...[
            if (loading.isNotEmpty) const Gap(BullSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(BullSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  left: BorderSide(color: colors.warning, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final coordinator in failed)
                          Text(
                            '${_coordinatorName(coordinator)} · ${switch (state.coordinators[coordinator]) {
                              CoordinatorBookFailed(:final failure) => failure.toTranslated(context),
                              _ => '',
                            }}',
                            style: text.labelMedium?.copyWith(
                              color: colors.text,
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: context.read<BookCubit>().retryFailed,
                    child: Text(
                      l10n.p2pCommonRetry,
                      style: text.labelLarge?.copyWith(color: colors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// No order matches: « No orders found to buy BTC for EUR », then « Be the first one to create an order ».
class EmptyBook extends StatelessWidget {
  final BookState state;

  const EmptyBook({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final code = state.filter.currency?.code ?? l10n.p2pBookFilterAny;
    return Padding(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            state.filter.side == BookSide.sell
                ? l10n.p2pBookEmptySell(code)
                : l10n.p2pBookEmptyBuy(code),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.xs),
          Text(
            l10n.p2pBookEmptyBeFirst,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.primary),
          ),
        ],
      ),
    );
  }
}
