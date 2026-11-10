import 'dart:async';
import 'dart:convert';

import 'package:bull_tor/tor.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// The clock of every test: books are read as if it were this time.
final testNow = DateTime.utc(2026, 11, 10, 14);

/// A maker hash id built from [seed], valid for `RobotHashId.parse`.
String hashId(int seed) => List.generate(
  64,
  (i) => '0123456789abcdef'[(seed * 7 + i * 13) % 16],
).join();

/// One element of `/api/book/` as a coordinator sends it.
Map<String, Object?> bookOrder({
  required int id,
  int type = 1,
  int currency = 2,
  double? amount = 100,
  double? minAmount,
  double? maxAmount,
  String paymentMethod = 'Revolut Instant SEPA',
  double premium = 2,
  double bond = 3,
  int? satoshisNow = 106900,
  double? price = 93330,
  Duration expiresIn = const Duration(hours: 17),
  Duration age = const Duration(hours: 7),
  int escrow = 10800,
  String? makerStatus = 'Active',
  int makerSeed = 1,
}) {
  final range = minAmount != null && maxAmount != null;
  return {
    'id': id,
    'created_at': testNow.subtract(age).toIso8601String(),
    'expires_at': testNow.add(expiresIn).toIso8601String(),
    'type': type,
    'currency': currency,
    'amount': range ? null : amount?.toString(),
    'has_range': range,
    'min_amount': minAmount?.toString(),
    'max_amount': maxAmount?.toString(),
    'payment_method': paymentMethod,
    'is_explicit': false,
    'premium': premium.toString(),
    'satoshis': null,
    'maker': 1,
    'escrow_duration': escrow,
    'bond_size': bond.toString(),
    'latitude': null,
    'longitude': null,
    'maker_hash_id': hashId(makerSeed),
    'satoshis_now': satoshisNow,
    'price': price,
    'maker_status': makerStatus,
  };
}

/// The onion host of [alias] on [network].
String hostOf(String alias, RobosatsNetwork network) =>
    Uri.parse(coordinator(alias).origins(network).onion ?? '').host;

Coordinator coordinator(String alias) =>
    switch (Federation.robosats.byAlias(alias)) {
      final coordinator? => coordinator,
      null => throw StateError('no coordinator $alias'),
    };

/// A transport that answers each coordinator, by short alias, with the book the test gives, a failure, or nothing until the test says so.
///
/// A coordinator the test does not mention answers an empty book (`404`, `not_found`).
final class FakeTransport implements CoordinatorTransport {
  final RobosatsNetwork network;
  final Map<String, List<Map<String, Object?>>> books;
  final Map<String, CoordinatorTransportFailure> failures;
  final Set<String> held;
  final Map<String, Completer<void>> _releases = {};
  final List<String> requested = [];

  /// Each `/api/info/` answer, by short alias.
  final Map<String, Map<String, Object?>> infos;

  FakeTransport({
    this.network = RobosatsNetwork.mainnet,
    Map<String, List<Map<String, Object?>>>? books,
    Map<String, CoordinatorTransportFailure>? failures,
    Set<String>? held,
    Map<String, Map<String, Object?>>? infos,
  }) : books = books ?? {},
       failures = failures ?? {},
       held = held ?? {},
       infos = infos ?? {};

  /// Lets the held requests to [alias] answer.
  void release(String alias) {
    held.remove(alias);
    _releases.remove(alias)?.complete();
  }

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    final path = request.url.path;
    requested.add('$alias$path');
    if (held.contains(alias)) {
      await (_releases[alias] ??= Completer<void>()).future;
    }
    if (failures[alias] case final failure?) return Err(failure);
    if (path.startsWith('/api/info')) {
      return Ok(_json(200, infos[alias] ?? const {}));
    }
    final book = books[alias];
    if (book == null) return Ok(_json(404, {'not_found': 'No orders found'}));
    return Ok(_json(200, book));
  }

  String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(network)) {
      if (Uri.parse(coordinator.origins(network).onion ?? '').host == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

/// A Tor whose states the test pushes, and that counts the starts and retries asked of it.
final class FakeTor implements Tor {
  @override
  final FakeEmbeddedTor embedded = FakeEmbeddedTor();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class FakeEmbeddedTor implements EmbeddedTor {
  final StreamController<TorConnectionState> controller =
      StreamController.broadcast();
  int starts = 0;
  int retries = 0;

  static final route = TorRoute(
    source: TorSource.embedded,
    endpoint: TorProxyEndpoint(host: '127.0.0.1', port: 9050),
    evidence: TorReadinessEvidence.embeddedBootstrap,
  );

  void notStarted() => controller.add(const TorUninitialized());

  void stopped() => controller.add(const TorStopped(TorSource.embedded));

  void connecting() =>
      controller.add(const TorConnecting(source: TorSource.embedded));

  void ready() => controller.add(TorReady(route));

  void failed() => controller.add(
    const TorUnavailable(
      source: TorSource.embedded,
      failure: TorBootstrapTimeoutFailure(),
    ),
  );

  @override
  Stream<TorConnectionState> get states => controller.stream;

  @override
  Future<TorConnectionState> ensureReady() async {
    starts++;
    return const TorUninitialized();
  }

  @override
  Future<TorConnectionState> retry() async {
    retries++;
    return const TorUninitialized();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
