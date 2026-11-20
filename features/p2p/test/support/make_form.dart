import 'dart:convert';

import 'package:p2p/testing.dart' show ScriptedMakerCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// What the create form's tests (#181) read from a coordinator played by [ScriptedMakerCoordinator]: never a real one.

/// The text of the code points [codes], so that a test names an invisible character by its number and never holds it raw in its source.
String chars(List<int> codes) => String.fromCharCodes(codes);

/// The text of one code point.
String char(int code) => String.fromCharCode(code);

Coordinator coordinatorOf(String alias) =>
    Federation.robosats.byAlias(alias) ?? (throw StateError(alias));

final RobosatsCurrency eur =
    RobosatsCurrency.fromCode('EUR') ?? (throw StateError('EUR'));
final RobosatsCurrency usd =
    RobosatsCurrency.fromCode('USD') ?? (throw StateError('USD'));
final RobosatsCurrency gbp =
    RobosatsCurrency.fromCode('GBP') ?? (throw StateError('GBP'));

/// The `/api/limits/` of a coordinator whose price of a bitcoin is [prices] by currency id, its bounds 20,000 to 5,000,000 sats at it.
Future<CurrencyLimits> limitsAt(Map<int, double> prices) async {
  final fake = ScriptedMakerCoordinator(
    network: RobosatsNetwork.mainnet,
    robots: const [],
    clock: () => DateTime.utc(2026, 11, 17),
  );
  fake.prices
    ..clear()
    ..addAll(prices);
  return switch (await CoordinatorClient(
    fake,
  ).fetchLimits(coordinatorOf('temple'), RobosatsNetwork.mainnet)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
}

/// The `/api/info/` of [alias], with [devfund] and [makerFee] (its taker fee 0.00175).
Future<CoordinatorInfo> infoAt(
  String alias, {
  double? devfund,
  double makerFee = 0.00025,
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  ({int major, int minor, int patch}) version = (major: 0, minor: 8, patch: 8),
}) async {
  final fake =
      ScriptedMakerCoordinator(
          network: network,
          robots: const [],
          clock: () => DateTime.utc(2026, 11, 17),
          alias: alias,
        )
        ..devfund = devfund
        ..makerFee = makerFee
        ..version = version;
  return switch (await CoordinatorClient(
    fake,
  ).fetchInfo(coordinatorOf(alias), network)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
}

/// The `/api/limits/` of [entries], each currency id with its `price`, `min_amount` and `max_amount` as given, read by the package as from a coordinator: for bounds that are exact decimals.
Future<CurrencyLimits> limitsOf(
  Map<int, (double, double, double)> entries,
) async {
  final body = {
    for (final MapEntry(key: id, value: (price, min, max)) in entries.entries)
      '$id': {
        'code': RobosatsCurrency.fromId(id)?.code,
        'price': price,
        'min_amount': min,
        'max_amount': max,
      },
  };
  return switch (await CoordinatorClient(
    _Answering(body),
  ).fetchLimits(coordinatorOf('temple'), RobosatsNetwork.mainnet)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
}

/// A transport that answers [body] to every request.
final class _Answering implements CoordinatorTransport {
  final Object body;

  const _Answering(this.body);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async => Ok(
    CoordinatorResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    ),
  );
}
