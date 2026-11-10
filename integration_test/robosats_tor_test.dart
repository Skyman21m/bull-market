import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/init.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bull_tor/tor.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One RoboSats coordinator onion, copied from `frontend/static/federation.json` of RoboSats/robosats at commit ff1998c.
typedef _Coordinator = ({
  String alias,
  String network,
  String onion,
  String nodeId,
});

// `nodeId` is the coordinator's `mainnetNodesPubkeys` or `testnetNodesPubkeys` entry in the same file.
const _coordinators = <_Coordinator>[
  (
    alias: 'temple',
    network: 'mainnet',
    onion: 'ngdk7ocdzmz5kzsysa3om6du7ycj2evxp2f2olfkyq37htx3gllwp2yd.onion',
    nodeId:
        '0226f31c5f3a8b48bbbb7aaa97a10effcfb445b5972a676955d5c095383d35a428',
  ),
  (
    alias: 'lake',
    network: 'mainnet',
    onion: '4t4jxmivv6uqej6xzx2jx3fxh75gtt65v3szjoqmc4ugdlhipzdat6yd.onion',
    nodeId:
        '0385262f7e9e2eeeba1e7d6182a0efec98e79d01154b76189f3e0b88bcee279dd0',
  ),
  (
    alias: 'bazaar',
    network: 'mainnet',
    onion: 'librebazovfmmkyi2jekraxsuso3mh622avuuzqpejixdl5dhuhb4tid.onion',
    nodeId:
        '03ab3468f06d3aac93992ef7ae79bce083e18617dc760f09ef687d7bca89667a15',
  ),
  (
    alias: 'freeport',
    network: 'mainnet',
    onion: '2enoseg66hme76khjjn2qvrhipnzwgwa44mewgrdphrxbhzcxd2vdiqd.onion',
    nodeId:
        '03230eea7d63303c3e54076f84745aeabf447e01a572e984e77b796665419d43cc',
  ),
  (
    alias: 'ammanaya',
    network: 'mainnet',
    onion: 'ammannjgzybw4qm2odmci7xgolh5grzijidacjxose5tthm375dcopad.onion',
    nodeId:
        '02cd566293ad8c8fd55bf5c5be38df5fc0af2b445333b10cbbd8b8a7d4c7ed7fe3',
  ),
  (
    alias: 'temple',
    network: 'testnet',
    onion: 'jpp3w5tpxtyg6lifonisdszpriiapszzem4wod2zsdweyfenlsxeoxid.onion',
    nodeId:
        '028e7a019180a664b84edf77ba656e96f2eb84f67f56d93020341caf4109e0dbc7',
  ),
  (
    alias: 'lake',
    network: 'testnet',
    onion: 'ghbtv7lhoyhomyir4xvxaeyqgx4ylxksia343jaat3njqqlkqpdjqcyd.onion',
    nodeId:
        '0355f8604df9ec4bee20a284f045f94e26cdd1fc5e15dee0716a5a5dfc7cd33b7c',
  ),
];

const _infoPath = '/api/info/';
const _sequentialRequests = 10;

/// Prints one measurement as a single greppable line: `ROBOSATS_TOR_MEASURE {json}`.
void _measure(String step, Map<String, Object?> values) {
  debugPrint('ROBOSATS_TOR_MEASURE ${jsonEncode({'step': step, ...values})}');
}

/// A Dio bound to one Tor session, with the session and socket it owns.
final class _TorDio {
  final Dio dio;
  final HttpClient _client;
  final TorSession _session;
  TorConnectFailure? connectFailure;

  _TorDio._(this.dio, this._client, this._session);

  static Future<_TorDio> open(String onion) async {
    final session = await locator<Tor>().embedded.sessions.open();
    late final _TorDio torDio;
    final client = locator<TorHttpClientFactory>().create(
      session.endpoint,
      onConnectFailure: (failure) => torDio.connectFailure = failure,
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://$onion',
        connectTimeout: torConnectDeadline,
        receiveTimeout: torConnectDeadline,
        sendTimeout: torConnectDeadline,
      ),
    );
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () =>
        client;
    return torDio = _TorDio._(dio, client, session);
  }

  Future<void> close() async {
    _client.close(force: true);
    await _session.close();
  }
}

Future<void> main({bool isInitialized = false}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  // Opt-in only: these tests call live RoboSats coordinators over Tor, so an outage there must never fail CI or a normal local run.
  // The environment variable is the form verified on Linux desktop.
  // The dart-define form is meant for a phone, where the app does not inherit the shell environment, and has not been exercised yet.
  final runLiveRobosatsTest =
      Platform.environment['RUN_LIVE_ROBOSATS_TEST'] == 'true' ||
      const bool.fromEnvironment('RUN_LIVE_ROBOSATS_TEST');

  // The first coordinator that answered, reused for the sequential latency test.
  _Coordinator? answered;

  group(
    'RoboSats coordinators over embedded Tor',
    skip: runLiveRobosatsTest
        ? false
        : 'calls live RoboSats coordinators: set RUN_LIVE_ROBOSATS_TEST=true',
    () {
      test(
        'embedded Tor becomes ready',
        timeout: const Timeout(Duration(minutes: 4)),
        () async {
          final tor = locator<Tor>().embedded;
          final before = tor.current.runtimeType.toString();
          final watch = Stopwatch()..start();
          final state = await tor.ensureReady();
          _measure('tor_start', {
            'ms': watch.elapsedMilliseconds,
            'stateBefore': before,
            'state': state.runtimeType.toString(),
            'transport': state is TorReady ? state.route.transport?.name : null,
          });
          expect(state, isA<TorReady>());
        },
      );

      for (final coordinator in _coordinators) {
        final label = '${coordinator.alias} ${coordinator.network}';
        test(
          '$label answers GET $_infoPath',
          timeout: const Timeout(Duration(minutes: 3)),
          () async {
            final watch = Stopwatch()..start();
            final torDio = await _TorDio.open(coordinator.onion);
            final sessionMs = watch.elapsedMilliseconds;
            try {
              watch.reset();
              final Response<Object?> response;
              try {
                response = await torDio.dio.get<Object?>(_infoPath);
              } on DioException catch (error) {
                _measure('first_request', {
                  'coordinator': label,
                  'ok': false,
                  'sessionMs': sessionMs,
                  'ms': watch.elapsedMilliseconds,
                  'dioType': error.type.name,
                  'cause': error.error?.runtimeType.toString(),
                  'status': error.response?.statusCode,
                  'torFailure': torDio.connectFailure?.name,
                });
                final reason = torDio.connectFailure?.name ?? error.type.name;
                fail('$label did not answer: $reason');
              }
              final requestMs = watch.elapsedMilliseconds;
              final info = response.data;
              final version = info is Map ? info['version'] : null;
              _measure('first_request', {
                'coordinator': label,
                'ok': true,
                'sessionMs': sessionMs,
                'ms': requestMs,
                'status': response.statusCode,
                'network': info is Map ? info['network'] : null,
                'nodeId': info is Map ? info['node_id'] : null,
                'version': version,
              });

              expect(response.statusCode, 200);
              // Fields set unconditionally by `InfoView.get` in RoboSats `api/views.py`.
              expect(
                info,
                isA<Map<String, dynamic>>()
                    .having((i) => i['network'], 'network', coordinator.network)
                    .having((i) => i['node_id'], 'node_id', coordinator.nodeId)
                    .having((i) => i['maker_fee'], 'maker_fee', isA<num>())
                    .having((i) => i['taker_fee'], 'taker_fee', isA<num>())
                    .having((i) => i['bond_size'], 'bond_size', isA<num>())
                    .having(
                      (i) => i['min_order_size'],
                      'min_order_size',
                      isA<int>(),
                    )
                    .having(
                      (i) => i['max_order_size'],
                      'max_order_size',
                      isA<int>(),
                    )
                    .having(
                      (i) => i['num_public_buy_orders'],
                      'num_public_buy_orders',
                      isA<int>(),
                    )
                    .having(
                      (i) => i['num_public_sell_orders'],
                      'num_public_sell_orders',
                      isA<int>(),
                    ),
              );
              expect(
                version,
                isA<Map<String, dynamic>>()
                    .having((v) => v['major'], 'major', isA<int>())
                    .having((v) => v['minor'], 'minor', isA<int>())
                    .having((v) => v['patch'], 'patch', isA<int>()),
              );
              answered ??= coordinator;
            } finally {
              await torDio.close();
            }
          },
        );
      }

      test(
        '$_sequentialRequests sequential requests to one coordinator',
        timeout: const Timeout(Duration(minutes: 15)),
        () async {
          final coordinator = answered;
          if (coordinator == null) fail('no coordinator answered');

          // One session and one keep-alive client for the whole series, as a screen polling a coordinator would do.
          final torDio = await _TorDio.open(coordinator.onion);
          final latencies = <int>[];
          var failures = 0;
          try {
            for (var i = 0; i < _sequentialRequests; i++) {
              final watch = Stopwatch()..start();
              try {
                await torDio.dio.get<Object?>(_infoPath);
                latencies.add(watch.elapsedMilliseconds);
              } on DioException {
                failures++;
              }
            }
          } finally {
            await torDio.close();
          }

          final sorted = [...latencies]..sort();
          _measure('sequential_requests', {
            'coordinator': '${coordinator.alias} ${coordinator.network}',
            'requests': _sequentialRequests,
            'failures': failures,
            'ms': latencies,
            'minMs': sorted.firstOrNull,
            'medianMs': sorted.isEmpty
                ? null
                : (sorted[(sorted.length - 1) ~/ 2] +
                          sorted[sorted.length ~/ 2]) ~/
                      2,
            'maxMs': sorted.lastOrNull,
          });
          expect(failures, 0);
        },
      );
    },
  );
}
