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

/// The book is being requested; [previous] is the book read before, kept on screen while it reloads.
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

/// The coordinator could not give its book: it is shown as offline, and its orders are not.
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

  /// One entry per coordinator of the network once the book is requested, in the order of the federation.
  final Map<Coordinator, CoordinatorBookStatus> coordinators;
  final BookFilter filter;

  /// The orders [filter] keeps, in its order.
  final List<PublicOrder> orders;

  const BookState({
    required this.network,
    this.tor = TorWait.initializing,
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

  /// Whether no book has arrived yet, so there is nothing to show but a wait.
  bool get isWaitingForFirstBook =>
      coordinators.isEmpty ||
      coordinators.values.every(
        (status) => status is CoordinatorBookLoading && status.previous == null,
      );

  BookState copyWith({
    TorWait? tor,
    Map<Coordinator, CoordinatorBookStatus>? coordinators,
    BookFilter? filter,
    List<PublicOrder>? orders,
  }) => BookState(
    network: network,
    tor: tor ?? this.tor,
    coordinators: coordinators ?? this.coordinators,
    filter: filter ?? this.filter,
    orders: orders ?? this.orders,
  );
}
