# Spike 1 — Reaching a RoboSats coordinator through the embedded Tor

Measurements of 2026-11-10, between 07:01 and 07:30 UTC. Test: `integration_test/robosats_tor_test.dart`. Code base: `main` at `50a931af8`.

## Verdict: it works (on desktop Linux, in a debug build)

From Dart, with the Tor already embedded by Bull and without any new dependency, the app calls `GET /api/info/` on the `.onion` address of a RoboSats coordinator and receives the expected response.

## Summary for the owner

1. **The 5 coordinators of the real network (mainnet) answered**, as did the "temple" test coordinator. Each one returned the right identity (the one listed in the official RoboSats list).
2. **The "lake" test coordinator never answered**: 9 attempts, 9 failures in 29 minutes, while its twin on the real network was answering. A manual check with a regular Tor, independent of the app, failed the same way, but its output was not kept. It answered normally on a tenth run, twenty minutes later: it was a temporary outage. Both test coordinators therefore exist, but their availability is not guaranteed.
3. **Tor startup**: 14 to 28 seconds the very first time, about 10 seconds on later runs.
4. **First contact with a coordinator**: 2 to 13 seconds, half of the attempts between 4.4 and 7.2 seconds.
5. **Once the connection is open, it is fast**: about 1 second per request.
6. **Reliability**: of 54 first contacts with the 6 online coordinators, 51 succeeded and 3 failed (one of which waited 60 seconds before giving up). Of 90 requests chained on an already open connection, none failed.
7. **Consequence for the app**: plan a waiting screen on first display (estimate: 20 to 40 seconds cold, Tor startup plus a first contact; querying in parallel was not measured), query the coordinators in parallel, retry automatically after a failure, and keep the connection open instead of reopening one each time.
8. **What is not proven yet**: the behavior on a real Android phone (speed, mobile network, sleep). These measurements come from a PC.

## Measurement conditions

- App built for desktop Linux in debug mode, run headless (Xvfb) in a Docker container, on a PC (AMD Ryzen 7 5700U, 16 threads). Flutter 3.44.9, Dart 3.12.2.
- **The PC is behind a Mullvad VPN** (WireGuard, exit in Zurich, checked during the session). Tor connected in direct mode every time; the Snowflake fallback was never triggered.
- 9 app runs in 29 minutes: 4 "cold" (no Tor state on disk, like a first install) and 5 "warm" (app restarted, Tor state of the previous run kept on disk).
- A single time slot, a single network, a single machine: these are orders of magnitude, not guarantees.
- The first 8 runs used intermediate versions of the test, the last one the version of the first commit. All of them measured the same raw times; the statistics below are recomputed from those times.
- **The 81 raw measurement lines are versioned** in [tor-robosats-measurements.jsonl](tor-robosats-measurements.jsonl), in run order, so that the figures can be rechecked.

## Rerun after review (2026-11-10, 07:49 UTC)

A tenth run was made with the corrected version of the test, twenty minutes after the first nine: **all 7 coordinators answered, lake testnet included**, and the test is fully green (10 cases passed). The absence of lake testnet during the first nine runs was therefore a temporary outage, not an outdated address. Tor started cold in 14.5 s; the series of 10 requests gave 0 failures, median 1.1 s. The measurements of this run are in [tor-robosats-measurements-rerun.jsonl](tor-robosats-measurements-rerun.jsonl). The tables below cover the first nine runs.

## Measurements

### Tor startup (`ensureReady()` until `TorReady`)

| Case | Runs | Values (s) |
|---|---|---|
| Cold | 4 | 14.0 · 14.1 · 19.7 · 27.7 |
| Warm | 5 | 9.7 · 9.8 · 9.9 · 10.0 · 10.0 |

This time includes Bull's deliberate 5-second hold after Arti's "ready" signal (visible in the logs: "holding readiness for 5s"). Opening a session once Tor is ready takes 3 to 15 ms.

### First request per coordinator (new Tor session, new connection)

| Coordinator | Network | Successes | Min (s) | Median (s) | Max (s) | Version | Failures |
|---|---|---|---|---|---|---|---|
| temple | mainnet | 8/9 | 5.6 | 7.0 | 9.5 | 0.8.8 | 1 × `timeout` after 60.1 s |
| lake | mainnet | 8/9 | 3.7 | 5.2 | 9.0 | 0.8.8 | 1 × `other` after 5.1 s |
| bazaar | mainnet | 9/9 | 3.3 | 6.5 | 13.4 | 0.8.7 | — |
| freeport | mainnet | 9/9 | 3.6 | 5.9 | 7.7 | 0.8.7 | — |
| ammanaya | mainnet | 9/9 | 2.1 | 3.9 | 4.9 | 0.8.8 | — |
| temple | testnet | 8/9 | 4.3 | 6.2 | 9.4 | 0.8.6 | 1 × `other` after 5.2 s |
| lake | testnet | 0/9 | — | — | — | — | 9 × `hostUnreachable` (4.0 to 43.9 s) |

Excluding lake testnet: 51 successes out of 54, median 5.6 s, from 2.1 to 13.4 s. Every successful response had HTTP status 200, the expected `network` field, a `node_id` equal to the key listed in `federation.json`, and the fields checked by the test (`version`, `maker_fee`, `taker_fee`, `bond_size`, `min_order_size`, `max_order_size`, `num_public_buy_orders`, `num_public_sell_orders`).

### 10 requests in a row on the same connection

9 series of 10 requests (8 to temple mainnet, 1 to lake mainnet), one session and one HTTP client per series: **90 requests, 0 failures**.

| Requests | Count | Min (s) | Median (s) | Max (s) |
|---|---|---|---|---|
| The first of each series (opens the connection) | 9 | 5.6 | 8.0 | 11.6 |
| The following ones (connection reused, judging by the times) | 81 | 0.59 | 0.93 | 2.40 |
| All | 90 | 0.59 | 0.95 | 11.6 |

Per series of 10, the median ranges from 0.69 to 1.22 s. Three requests out of 81 took more than 1.5 s. Note: `/api/info/` is cached for 30 seconds by the server, so these times mostly measure the Tor round trip.

## Pitfalls found

1. **No automatic retry.** In this code model, nothing retries a failed first contact. The costliest case observed: 60 seconds of waiting (Tor budget `torConnectBudget`) before the `timeout` failure, on temple mainnet, at the first request of a warm run. The two other failures came within 5 seconds. A single occurrence of each: the cause is not established.
2. **Dio hides the reason for the failure.** Connection failures arrive as a `DioException` of type `unknown`. In 11 failures out of 12, `DioException.error` contained a `SocksClientConnectionCommandFailedException` (the first run did not record this field). The readable reason (`timeout`, `hostUnreachable`…) is obtained with `TorHttpClientFactory.classify`, a public static method, or through the `onConnectFailure` callback. Prefer `classify`: the callback feeds a shared variable, which becomes wrong with parallel requests. Two failures were classified as `other`: the SOCKS reply code was not recorded.
3. **The first contact is expensive, the following requests are not.** 2.1 to 13.4 s for the first request of a session (5.6 to 11.6 s in the chained series), about 1 s afterwards. The test does not separate what comes from the HTTP connection kept open from what comes from reusing the Tor circuit. One session per request would be unusable.
4. **One test coordinator out of two never answered.** lake testnet remained unreachable from the embedded Tor for the whole session. It answered on the tenth run, which rules out an outdated address: it was a temporary outage. Expect the project's later testnet tests to sometimes be able to rely on only one of the two.
5. **A 200 status is not enough.** Side check done by hand (regular Tor + `curl`, outside the app), whose output was not kept: temple mainnet answers 200 to `curl` with its default header, but as `text/plain`, with an announced size of several MB of random data sent at a trickle. With a browser `User-Agent` header, a Dart one, or no header, it returns the normal JSON in 2 s. The app's client (Dio on `dart:io`, default header not recorded) never received this decoy. So the type and shape of the response must be validated, and the `User-Agent` header must not be changed lightly.
6. **The activation flag goes through the environment**, inherited by the app on desktop Linux. On a phone it is not: the test also accepts `--dart-define=RUN_LIVE_ROBOSATS_TEST=true`, a form that was **not tried**.
7. **A coordinator that is down must not turn the test red.** During the 9 runs, each unreachable coordinator failed its case, and all runs ended with "Some tests failed" because of lake testnet. After review, the test was changed: an unreachable coordinator is measured and reported without failing, a coordinator that answers with a wrong identity or a wrong shape fails, and a final case requires at least 3 mainnet coordinators and 1 testnet coordinator to have answered. Without the flag, all cases are skipped cleanly ("All tests skipped", checked by a run).

## What was checked in the preparation file

- The chain `locator<Tor>().embedded.sessions.open()` → `TorSession.endpoint` → `locator<TorHttpClientFactory>().create(endpoint)` → Dio exists as described and works.
- `http://<onion>/api/info/` without authentication: confirmed for the 6 online coordinators.
- The addresses and node keys of `frontend/static/federation.json` (RoboSats `ff1998c`) are correct for the 6 online coordinators.
- "Up to a minute cold": here 14 to 28 s. The 5 s hold is confirmed by the logs.
- Not checked here: the proxy's "onion only" policy (no clearnet request attempted).

## Code model to reuse in phase 1

**Where to put it.** Decision of 2026-11-09: the coordinator client lives in `packages/robosats` (pure Dart), the screens in `features/p2p`. But `packages/bull_tor` is a Flutter package: `packages/robosats` cannot import it. The split is therefore:

- `packages/robosats` defines a transport port (a function or an interface that runs an HTTP request to a coordinator) and everything that is protocol;
- `features/p2p` provides the Tor implementation of that port: it opens and closes the `TorSession`s, builds the client, and receives `Tor` by injection, following the model of `MempoolTorSessionAdapter` (`lib/core/mempool/interface_adapters/mempool_tor_session_adapter.dart`), without calling `locator` in the middle of the code.

**The sequence run by the test**, with real names only. Here the session is closed after one request; in the app, the adapter keeps it open as long as the screen needs it.

```dart
import 'dart:io';

import 'package:bull_tor/tor.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

final TorSession session = await tor.embedded.sessions.open();
try {
  final HttpClient client = torHttpClientFactory.create(session.endpoint);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://$onion',
      connectTimeout: torConnectDeadline,
      receiveTimeout: torConnectDeadline,
      sendTimeout: torConnectDeadline,
    ),
  );
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () => client;
  try {
    final response = await dio.get<Object?>('/api/info/');
    // Validate the type and the fields before use: see pitfall 5.
  } on DioException catch (e) {
    final Object? cause = e.error;
    final TorConnectFailure? reason = cause == null ? null : TorHttpClientFactory.classify(cause);
  } finally {
    client.close(force: true);
  }
} finally {
  await session.close();
}
```

`sessions.open()` starts Tor if needed. To show progress, listen to `tor.embedded.states`. `classify` is a public static method (`static TorConnectFailure classify(Object error)`, `packages/bull_tor/lib/src/data/tor_http_client_factory.dart`); the test itself goes through the `onConnectFailure` callback, so this direct call was not run.

**Not to copy from the test**: querying the coordinators one after the other, the lack of retry, classifying errors through a shared variable.

**To add in phase 1** (raised by the independent review):

- query the coordinators in parallel, like the official client, which gives each one 15 s at most before displaying;
- retry a failed first contact with a **new session**, hence a new circuit;
- set a total deadline per request: `receiveTimeout` does not protect against a response sent at a trickle;
- disable redirects, cap the size of responses, check that the response is JSON before decoding it;
- compare the `node_id` with the federation list loaded at runtime;
- never log text coming from a coordinator as is.

**Privacy, to be decided in phase 1**:

- One Tor session per (coordinator, robot) pair for authenticated calls, so that a coordinator cannot link together several robots of the same user; one session per coordinator is enough for public reads.
- The `User-Agent` header: Dart's HTTP client announces itself as such, the official Android client as `okhttp`, the website as a browser. As it stands, a coordinator recognizes a Troc user. Decide whether to imitate the official client, after checking that the coordinators accept it (see pitfall 5).

## What remains unknown

- **Android**: startup and first-contact times on a phone, on Wi-Fi and on a mobile network, in a release build.
- **Background**: Tor going to sleep when the app is no longer in the foreground, then waking up (the test does not start the lifecycle controller).
- **Parallel sessions**: the test queries the coordinators one after the other.
- **Without a VPN, or on a network that blocks Tor**: Snowflake fallback never triggered here.
- **External Tor proxy (Orbot)**: not tried.
- **Duration**: 29 minutes of observation; no data on a connection kept open for hours.
- **Authenticated routes, POST, WebSocket** (`/relay/`, chat): outside this spike.
- **Cause of the 60 s `timeout` and of the two `other` failures.**

## Rerunning the measurement

From the repository root, after `make deps`, `make build-runner` and `make translations`:

```sh
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; RUN_LIVE_ROBOSATS_TEST=true fvm flutter test integration_test/robosats_tor_test.dart -d linux --reporter=expanded'
```

The variable is passed on the command line, not with `export`: exported, it would stay active in the terminal and would make a `make integration-test` run afterwards a live one.

The measurements come out on `ROBOSATS_TOR_MEASURE {json}` lines. First run: about 13 minutes of compilation on this PC (Rust crates included), then about 1 minute before the tests start on later runs. A single test file runs directly, without going through the `all_test.dart` aggregator.
