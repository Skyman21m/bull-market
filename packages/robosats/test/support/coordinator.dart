import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// The responses recorded from the live federation, under `test/fixtures/coordinator/`: see its README.
///
/// Tests run with the package directory as working directory, as `make unit-test` does.
Uint8List recordedBody(String alias, RobosatsNetwork network, String endpoint) =>
    File(
      'test/fixtures/coordinator/$alias-${network.name}-$endpoint.json',
    ).readAsBytesSync();

/// The coordinators and endpoints recorded, as (alias, network).
const recordedCoordinators = [
  ('temple', RobosatsNetwork.mainnet),
  ('lake', RobosatsNetwork.mainnet),
  ('bazaar', RobosatsNetwork.mainnet),
  ('freeport', RobosatsNetwork.mainnet),
  ('ammanaya', RobosatsNetwork.mainnet),
  ('temple', RobosatsNetwork.testnet),
];

/// The coordinator of the embedded federation with this alias.
Coordinator coordinatorNamed(String alias) => switch (Federation.robosats
    .byAlias(alias)) {
  final coordinator? => coordinator,
  null => throw StateError('no coordinator $alias'),
};

/// A JSON response such as a coordinator sends it.
CoordinatorResponse jsonResponse(
  Object? json, {
  int statusCode = 200,
  String contentType = 'application/json',
}) => CoordinatorResponse(
  statusCode: statusCode,
  headers: {'content-type': contentType},
  body: utf8.encode(jsonEncode(json)),
);

/// A response with raw bytes.
CoordinatorResponse rawResponse(
  List<int> body, {
  int statusCode = 200,
  String? contentType = 'application/json',
}) => CoordinatorResponse(
  statusCode: statusCode,
  headers: {'content-type': ?contentType},
  body: Uint8List.fromList(body),
);

/// An in-memory [CoordinatorTransport] that answers by onion host and path, and records every request.
final class FakeCoordinatorTransport implements CoordinatorTransport {
  final Map<String, Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> Function(CoordinatorRequest)>
  _routes = {};
  final List<CoordinatorRequest> requests = [];

  /// Answers requests to [path] of the instance of [coordinator] on [network] with [response].
  void answer(
    Coordinator coordinator,
    RobosatsNetwork network,
    String path,
    Result<CoordinatorResponse, CoordinatorTransportFailure> response,
  ) => route(coordinator, network, path, (_) async => response);

  /// Answers requests to [path] of the instance of [coordinator] on [network] with [handler].
  void route(
    Coordinator coordinator,
    RobosatsNetwork network,
    String path,
    Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> Function(
      CoordinatorRequest,
    )
    handler,
  ) {
    final onion = coordinator.origins(network).onion;
    if (onion == null) throw StateError('$coordinator is not on $network');
    _routes['${Uri.parse(onion).host}$path'] = handler;
  }

  /// Answers [path] of a recorded coordinator with its recorded body.
  void answerRecorded(
    String alias,
    RobosatsNetwork network,
    String endpoint, {
    int statusCode = 200,
  }) => answer(
    coordinatorNamed(alias),
    network,
    '/api/$endpoint/',
    Ok(
      CoordinatorResponse(
        statusCode: statusCode,
        headers: const {'content-type': 'application/json'},
        body: recordedBody(alias, network, endpoint),
      ),
    ),
  );

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) {
    requests.add(request);
    final handler = _routes['${request.url.host}${request.url.path}'];
    if (handler == null) {
      return Future.value(const Err(CoordinatorUnreachable()));
    }
    return handler(request);
  }
}
