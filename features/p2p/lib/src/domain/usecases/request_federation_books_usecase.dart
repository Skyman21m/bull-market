import 'package:robosats/robosats.dart';

/// Asks every coordinator of the federation on one network for its book, all at once.
final class RequestFederationBooksUsecase {
  final FederationBookReader _reader;
  final Federation _federation;

  const RequestFederationBooksUsecase(this._reader, this._federation);

  /// One pending book per coordinator that has an onion address on [network], in the order of the federation, every request started without waiting for the others.
  ///
  /// Each future completes with the book or the failure of its coordinator, so a screen lists the coordinators at once and shows each book as it arrives: a slow or failing coordinator delays only its own.
  Map<Coordinator, Future<CoordinatorBookOutcome>> execute(
    RobosatsNetwork network,
  ) {
    final federation = Federation(_federation.on(network));
    final requests = _reader.requestAll(federation, network);
    return {
      for (final (index, coordinator) in federation.coordinators.indexed)
        coordinator: requests[index],
    };
  }
}
