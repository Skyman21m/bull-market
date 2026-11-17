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
}) async {
  final fake =
      ScriptedMakerCoordinator(
          network: network,
          robots: const [],
          clock: () => DateTime.utc(2026, 11, 17),
          alias: alias,
        )
        ..devfund = devfund
        ..makerFee = makerFee;
  return switch (await CoordinatorClient(
    fake,
  ).fetchInfo(coordinatorOf(alias), network)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
}
