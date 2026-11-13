import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

import '../domain/book_filter.dart';
import '../domain/tor_wait.dart';

/// Where the book of one coordinator stands.
@immutable
sealed class CoordinatorBookStatus {
  const CoordinatorBookStatus();

  /// The orders of the coordinator the book can show now.
  List<PublicOrder> get orders;
}

/// The book is awaited: it is being requested, or the coordinator gave no answer and is about to be asked again; [previous] is the book read before, kept on screen while it reloads.
final class CoordinatorBookLoading extends CoordinatorBookStatus {
  final OrderBook? previous;

  const CoordinatorBookLoading([this.previous]);

  @override
  List<PublicOrder> get orders => previous?.orders ?? const [];
}

final class CoordinatorBookLoaded extends CoordinatorBookStatus {
  final OrderBook book;

  const CoordinatorBookLoaded(this.book);

  @override
  List<PublicOrder> get orders => book.orders;
}

/// The coordinator gave no book after its last attempt, or none yet after `BookRetry.awaitedAtMost`, its attempts going on: it is shown offline, and its orders are not.
final class CoordinatorBookFailed extends CoordinatorBookStatus {
  final CoordinatorFailure failure;

  const CoordinatorBookFailed(this.failure);

  @override
  List<PublicOrder> get orders => const [];
}

/// The P2P book screen: the wait for Tor, then the book of every coordinator as it arrives, filtered.
@immutable
final class BookState {
  final RobosatsNetwork network;
  final TorWait tor;

  /// The percentage of its start Tor has done, as the wait shows it (`TorWait.percentAfter`); `null` shows none.
  final int? torPercent;

  /// One entry per coordinator of the network once the book is requested, in the order of the federation.
  final Map<Coordinator, CoordinatorBookStatus> coordinators;
  final BookFilter filter;

  /// The orders [filter] keeps, in its order.
  final List<PublicOrder> orders;

  const BookState({
    required this.network,
    this.tor = TorWait.initializing,
    this.torPercent,
    this.coordinators = const {},
    this.filter = const BookFilter(),
    this.orders = const [],
  });

  /// Every order received, coordinator after coordinator in the order of the federation, each book in the order its coordinator listed it.
  Iterable<PublicOrder> get receivedOrders =>
      coordinators.values.expand((status) => status.orders);

  List<Coordinator> get loadingCoordinators => [
    for (final MapEntry(:key, :value) in coordinators.entries)
      if (value is CoordinatorBookLoading) key,
  ];

  List<Coordinator> get failedCoordinators => [
    for (final MapEntry(:key, :value) in coordinators.entries)
      if (value is CoordinatorBookFailed) key,
  ];

  /// How many coordinators have given their book, an empty one included.
  int get answeredCount =>
      coordinators.values.whereType<CoordinatorBookLoaded>().length;

  /// Whether a coordinator gave its book, even an empty one: until one does, an empty book is not known to be empty.
  bool get hasAnswer =>
      coordinators.values.any((status) => status is CoordinatorBookLoaded);

  /// Whether no book has arrived yet, so there is nothing to show but a wait.
  bool get isWaitingForFirstBook =>
      coordinators.isEmpty ||
      coordinators.values.every(
        (status) => status is CoordinatorBookLoading && status.previous == null,
      );

  /// A copy with what is given; [torPercent] goes with [tor], so a new step without a percentage shows none.
  BookState copyWith({
    TorWait? tor,
    int? torPercent,
    Map<Coordinator, CoordinatorBookStatus>? coordinators,
    BookFilter? filter,
    List<PublicOrder>? orders,
  }) => BookState(
    network: network,
    tor: tor ?? this.tor,
    torPercent: tor == null ? this.torPercent : torPercent,
    coordinators: coordinators ?? this.coordinators,
    filter: filter ?? this.filter,
    orders: orders ?? this.orders,
  );
}
