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
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/coordinator_text.dart';
import 'coordinator_details_dialog.dart';
import 'depth_chart_view.dart';
import 'map_chart_view.dart';
import 'search_order_dialog.dart';
import 'widgets/coordinators_row.dart';
import 'widgets/filter_choice.dart';
import 'widgets/no_robot_dialog.dart';
import 'widgets/offer_row.dart';

/// The name of a coordinator, cleaned and bounded as every P2P screen shows it.
String _coordinatorName(Coordinator coordinator) => CoordinatorText.of(
  coordinator.longAlias,
  maxCodePoints: CoordinatorText.name,
);

/// The book of the P2P tab: the filter sentence, the row of the coordinators (`CoordinatorsRow`), one row per offer, and the choice of view.
///
/// The list is built lazily, so a book of thousands of orders only builds the rows on screen.
/// While the book loads, the wait shows as the official client's does: skeleton rows while no order is shown (`BookSkeleton`), then a bar running over the top of the book while a coordinator is still awaited over orders shown, after a pull to refresh or a retry too.
/// The row of the coordinators above it is Troc's own (#73): it shows who answered, who is awaited and who is offline, and stays once the offers are shown.
/// « Chart » shows the depth chart instead, as the official client does on a phone: without the filter sentence, whose currency and host it follows, and below the row of the coordinators.
/// « Map » shows, in the same place, every order of the book that has a position on a map of the world, whatever the filter, as the official client's map does.
class BookView extends StatefulWidget {
  final DateTime Function() now;
  final ValueChanged<PublicOrder> onOpenOrder;

  /// The cubit of the dialog of a coordinator, which a tap on its image in the row opens.
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  const BookView({
    super.key,
    required this.now,
    required this.onOpenOrder,
    required this.coordinatorDetails,
    this.onOpenGarage,
  });

  @override
  State<BookView> createState() => _BookViewState();
}

class _BookViewState extends State<BookView> {
  late DateTime _now;

  /// Moves the expiry rings on: they show hours or minutes, so once a minute is enough.
  Timer? _ticker;

  /// How many times « Search » was chosen, the key that puts the view bar back on the view shown.
  int _searches = 0;

  /// The view shown: the list, the depth chart or the map.
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
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<BookCubit>();
    final state = context.watch<BookCubit>().state;
    final shown = switch (_view) {
      BookViewChoice.list => state.orders.isNotEmpty,
      BookViewChoice.chart ||
      BookViewChoice.map => state.receivedOrders.isNotEmpty,
    };
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              BullRefreshIndicator(
                onRefresh: cubit.refresh,
                child: switch (_view) {
                  BookViewChoice.list => CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: BookFilterSentence(state: state),
                      ),
                      SliverToBoxAdapter(child: _coordinators(state)),
                      ..._content(context, state),
                    ],
                  ),
                  BookViewChoice.chart => _chart(
                    context,
                    state,
                    () => DepthChartView(
                      state: state,
                      onOpenOrder: widget.onOpenOrder,
                    ),
                  ),
                  BookViewChoice.map => _chart(
                    context,
                    state,
                    () => MapChartView(
                      state: state,
                      now: _now,
                      onOpenOrder: widget.onOpenOrder,
                    ),
                  ),
                },
              ),
              // While a coordinator is still awaited over orders already shown, a bar runs over the top of the book, as the official client's book runs one over its rows; with nothing shown, the skeleton or the spinner is the wait.
              // It lies over the book rather than above it, so that the book does not move when it comes and goes, and it lets touches through.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: BullFadingLinearProgress(
                    trigger: shown && state.loadingCoordinators.isNotEmpty,
                    height: 3,
                    foregroundColor: colors.primary,
                    backgroundColor: colors.transparent,
                  ),
                ),
              ),
            ],
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
              BookViewChoice.map => l10n.p2pBookViewMap,
            },
            onSelected: (item) {
              if (item == l10n.p2pCommonSearch) {
                unawaited(_searchOrder());
              } else if (item == l10n.p2pBookViewList) {
                setState(() => _view = BookViewChoice.list);
              } else if (item == l10n.p2pBookViewChart) {
                setState(() => _view = BookViewChoice.chart);
              } else if (item == l10n.p2pBookViewMap) {
                setState(() => _view = BookViewChoice.map);
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
        await NoRobotDialog.show(context, onOpenGarage: widget.onOpenGarage);
      case OrderSearchInvalidUrl() || null:
        break;
    }
  }

  /// The row of the coordinators, above the list and above the chart alike; a tap on an image opens the dialog of its coordinator, which asks it for its info.
  Widget _coordinators(BookState state) => CoordinatorsRow(
    state: state,
    onOpenCoordinator: (coordinator) => CoordinatorDetailsDialog.show(
      context,
      () => widget.coordinatorDetails(
        CoordinatorDetailsRequest(coordinator, state.network),
      ),
    ),
    onRetry: context.read<BookCubit>().retryFailed,
  );

  /// The least height of the depth chart and of the map: on a short screen they scroll rather than shrink.
  static const _chartMinHeight = 320.0;

  /// The row of the coordinators, as above the list, then the depth chart or the map ([view]) once an order has arrived, the wait before, or the empty book once no coordinator is still awaited and one has answered.
  ///
  /// The row scrolls with the chart or the map, which keeps at least [_chartMinHeight] below it whatever the size of the screen and of the text; a drag that starts on the map moves the map, so the row is where the view scrolls and is pulled to refresh.
  /// A coordinator offline is shown in the row, with « Retry » under it, whether the others gave orders or not: a failure is not an empty book.
  Widget _chart(BuildContext context, BookState state, Widget Function() view) {
    final colors = context.bull;
    final Widget content = state.receivedOrders.isNotEmpty
        ? view()
        : state.isWaitingForFirstBook || state.loadingCoordinators.isNotEmpty
        ? Center(child: CircularProgressIndicator(color: colors.primary))
        : state.hasAnswer
        ? EmptyBook(state: state)
        : const SizedBox.shrink();
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _coordinators(state)),
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
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: SizedBox(
              height: math.max(
                constraints.viewportMainAxisExtent -
                    constraints.precedingScrollExtent,
                BookSkeleton.rowExtent,
              ),
              child: const BookSkeleton(),
            ),
          ),
        ),
      ];
    }
    // When every coordinator is offline, the row above and « Retry » say so: the book is not empty, it is unknown.
    if (!state.hasAnswer) return const [];
    return [
      SliverFillRemaining(hasScrollBody: false, child: EmptyBook(state: state)),
    ];
  }
}

/// The views of the book the bar below it offers; « Search » opens a dialog.
enum BookViewChoice { list, chart, map }

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

/// The list while no order is shown and a coordinator is still awaited: rows of grey shapes, down to the bottom of the screen, as the official client's book shows skeleton rows (the loading overlay of its data grid).
///
/// Each row has the shape of an offer: the robot, three lines, the amount and the expiry ring; the first line shimmers.
/// The shapes are hidden from the accessibility tree: the line of the row of the coordinators above says what the book waits for.
class BookSkeleton extends StatelessWidget {
  /// The height of one row and its divider.
  static const rowExtent = 89.0;

  const BookSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rows = math.max(1, (constraints.maxHeight / rowExtent).ceil());
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < rows; row++) ...[
                    const _SkeletonRow(),
                    Divider(height: 1, color: colors.outlineVariant),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One row of [BookSkeleton], in the shape of an offer row, where only the nickname's line shimmers.
///
/// Each `BullShimmerLine` runs an animation and a mask layer of its own, so a row has one: the other shapes stay still, in the shimmer's base colour.
/// A shimmer of `bull_ui` that wraps a child would let a whole row, or the whole skeleton, share one sweep.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final base = context.bull.shimmerBase;
    Widget line(double width, double height) =>
        Container(width: width, height: height, color: base);
    Widget disc(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: base, shape: BoxShape.circle),
    );
    return SizedBox(
      height: BookSkeleton.rowExtent - 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BullSpacing.md,
          vertical: BullSpacing.sm,
        ),
        child: Row(
          children: [
            disc(40),
            const Gap(BullSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BullShimmerLine(
                    width: 120,
                    height: 14,
                    padding: EdgeInsets.zero,
                  ),
                  const Gap(BullSpacing.xs),
                  line(170, 10),
                  const Gap(BullSpacing.xs),
                  line(110, 10),
                ],
              ),
            ),
            const Gap(BullSpacing.xs),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [line(64, 14), const Gap(BullSpacing.xs), disc(36)],
            ),
          ],
        ),
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
