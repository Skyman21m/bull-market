# Tor transport of the RoboSats client (issue #27)

Branch `feat/p2p-transport-tor`, 2026-11-10. Follow-up to the spike [tor-robosats.md](tor-robosats.md), whose recommendations this issue applies.

## What was built

- **The `features/p2p` package** (Dart name `p2p`), a workspace member, added to the `workspace:` list and to the app's dependencies. No screen, no route, no tab: the feature is not visible yet (issue #29).
- **The public facade** `lib/p2p.dart`: `P2pFeature.setup(locator)`, called by the shell in `lib/locator.dart` right after the logs, and `P2pFacade`, which the shell and the future screens use. It re-exports the `packages/robosats` types that appear in its signatures and in the fields of those types (order, amount, premium, payment methods, coordinator, info), so that a screen does not have to import `robosats`.
- **The `TorCoordinatorTransport` adapter** (`lib/src/data/tor_coordinator_transport.dart`), which implements the `CoordinatorTransport` port of `packages/robosats` over the embedded Tor: the chain `tor.embedded.sessions.open()` → `TorSession.endpoint` → `TorHttpClientFactory.create` → Dio, as in the spike.
- **The service**, a thin one: `requestBooks(network)` starts reading the order book of every coordinator of the network at the same time (`FederationBookReader.requestAll`) and returns one future per coordinator; `fetchInfo(coordinator, network)` reads `/api/info/` with the identity check; `watchTorState()` gives the Tor state in four steps (not started, starting, ready, failed), taken from `tor.embedded.states`; `closeSessions()` closes all sessions. All the parsing of responses stays in `packages/robosats`.

## Decisions

- **No `User-Agent` header** (project decision): `HttpClient.userAgent = null`, and a `User-Agent` present in the request is removed. The header is the same for all Troc users, who therefore cannot be told apart from each other; Troc does not imitate the official client.
- **`Accept-Encoding: identity`** for all requests, and no decompression. Found by the tests: `dart:io` asks for `gzip` by default, even when automatic decompression is turned off; a compressed response would then have arrived unreadable. With `identity`, the size cap counts the bytes actually received: a small compressed response cannot inflate in memory. A coordinator that compressed anyway would see its response rejected as "not JSON".
- **Total deadline of 132 s per request** (`torConnectDeadline` × 2), Tor session and retries included. Dio timeouts per attempt: `torConnectDeadline` (66 s), so that the reason given by Tor arrives first. **Once Tor is ready**, a first contact that fails at the end of Tor's connection budget (60 s) still leaves a full budget for a retry. **Cold, this is not true**: Tor startup counts toward the deadline; in the measurement below it took 62 s, and only about 10 s were left for the retry. Screens must therefore wait for the "ready" state (`watchTorState`) before asking for the order books.
- **Deadline passed before the headers**: the session is replaced as after a connection failure. Closing its client also cancels a connection still in progress, which would otherwise have waited for the attempt's timeout (up to 66 s).
- **Retry**: a connection failure is a SOCKS or socket error before any response header, or a connection closed before the headers (which is also what a kept-alive connection that has died gives). The session is then closed and replaced, and a `GET` request is retried at most 2 times, each time on a new session (new circuits). Other methods are never retried. **A response that is not valid HTTP** (anything in place of the status line, a negative or duplicate `Content-Length`, a NUL character in a header, headers that never end) means that the coordinator answered: `CoordinatorTransportFailed` failure right away, with no retry, so that a coordinator that answers badly does not pass for offline and does not cost three sessions (fixed after the review). The Tor reason (`timeout`, `hostUnreachable`…) comes from `TorHttpClientFactory.classify(DioException.error)`, with no shared variable; it only appears in the development console (`log.info`).
- **One Tor session per coordinator origin** for public reads, opened on the first request and shared by concurrent requests to that coordinator. One session per robot for authenticated calls is still to be done (#28).
- **`closeSessions()` is not final**: the transport is a singleton; after closing, the next request reopens a session. GetIt also calls it when the singleton is disposed.
- **No `P2pFailure` family** for now: all errors are the `CoordinatorFailure`s of `packages/robosats`, re-exported by the facade. Their translation for the user will come with the screens.
- **Rule 11 of `AGENTS.md`, precisely**: every `Exception` becomes a typed failure. An `Error` (programming bug) thrown by the adapter itself, or by the session opener or the client factory it receives, propagates to the caller, as in `CoordinatorClient`, after the session concerned has been closed (session leak fixed after the review). An `Error` thrown inside Dio arrives wrapped in a `DioException` and becomes `CoordinatorTransportFailed`. A session or a client that fails to close with an exception is dropped silently.
- **Only `http` to a `.onion` host**: any other address (`https`, `file:`, a web name or IP address, an address carrying a username and password) fails with `CoordinatorTransportFailed` before any session, so nothing is sent. A `Coordinator` can be built freely and the facade re-exports it: the transport checks for itself. The tests target `127.0.0.1` through a test-only parameter.

## Guarantees against the port contract

| Contract clause | How | Test (`features/p2p/test/tor_coordinator_transport_test.dart`) |
|---|---|---|
| Always complete with `Ok` or `Err`, never throw an exception | A `Completer` filled by whichever arrives first: the response or the deadline timer; all exceptions are converted; an `Error` propagates (rule 11) | group `never throws` (Tor without a session, client factory that throws, non-HTTP URL); group `programming errors` (an `Error` reaches the caller, the session is closed) |
| Never hang | The total deadline timer answers `CoordinatorTimedOut` whatever happens, and cancels the attempt in progress; before the headers, the session is also replaced, which cancels a connection in progress as soon as the other requests of that session are done | `cuts a Tor session that never opens`, `cuts a coordinator that never sends its headers, and drops the connection` (the server sees the connection closed), `cancels a connection still being made` |
| Total deadline, body included | Same timer; it cancels reading the body through Dio's `CancelToken` | `cuts a body sent a byte at a time, and drops the connection` (the server sees the connection closed) |
| Stop at the size cap, without keeping more | Body read as a stream (`ResponseType.stream`); at the first chunk that goes over, the request is canceled and the chunk discarded; immediate refusal if `Content-Length` announces too much | `accepts a body of exactly the cap`, `refuses a body announced larger than the cap`, `refuses at once a body announced too large, and drops the connection` (no body sent: only the header can trigger the refusal; the server sees the connection closed), `stops reading a chunked body one byte over the cap`, `stops reading a body that never ends and drops the connection` (the server sees the connection closed) |
| No decompression that would get around the cap | `Accept-Encoding: identity`, `autoUncompress = false` | `neither asks for nor inflates a compressed body` |
| Lowercase header names | Rewritten in lowercase, multiple values joined | `gives the status, the body and lowercase header names` |
| Do not follow redirects | `followRedirects: false`, `maxRedirects: 0`; a `3xx` is returned as is to the client, which rejects it | `returns a redirect as it is, without following it`, `lets the coordinator client reject a redirect` |
| Everything else as a `CoordinatorTransportFailure` | Connection failure → `CoordinatorUnreachable`; connection cut during the body → `CoordinatorUnreachable`; timeout → `CoordinatorTimedOut`; response that is not HTTP, and the rest → `CoordinatorTransportFailed` | `gives up after two retries…`, `retries a refused TCP connection`, `retries a connection closed before the headers`, `reports a connection lost in the middle of the body`, group `answers that are not HTTP fail at once, without retry` (a single session opened) |
| Concurrent calls | One session per origin, shared; a user counter closes a retired session when, and only when, its last request ends | `reuses one session per origin, even for concurrent requests`, `closes a replaced session only when its last request ends` |
| Retry on a new session, GET only | See "Decisions" | `retries a GET on a new session after a SOCKS refusal`, `never retries a request that is not a GET` |
| No `User-Agent` | `userAgent = null`, request header removed | `sends no User-Agent and asks for no compression` |
| Onion services only | `http` scheme and `.onion` host checked before any session | group `only reaches onion services` (production default: `https://….onion`, `http://example.com`, `http://127.0.0.1`, `file:` refused, no session opened) |
| Closing | `closeSessions` closes sessions and clients; a request in progress fails without reopening; a session that finishes opening afterwards is closed at once, without being used | group `closeSessions` (the server receives no connection from the late session) |

On the service side (`request_federation_books_usecase_test.dart`, `p2p_feature_test.dart`): all requests go out before the first response; a coordinator that does not answer neither delays nor hides the others, and its failure arrives afterwards; Tor without a session gives one failure per coordinator, without an exception; the Tor state is correctly translated into four steps.

## Real measurements

**All these measurements come from a single cold run, on a desktop PC behind a VPN**: orders of magnitude, not guarantees. It took place on 2026-11-10 between 18:20:03 and 18:22:27 UTC, with `integration_test/p2p_book_tor_test.dart`, on the version from before the review (`ec0631a07`). The fixes made afterwards (classification of responses that are not HTTP, session replaced when the deadline passes before the headers, onion addresses only) touch none of the paths taken during this run, except the end of lake testnet, cut by the deadline, whose session would now also be closed; the test was not rerun. The 18 raw measurement lines are versioned in [tor-transport-measurements.jsonl](tor-transport-measurements.jsonl); the times and the retries cited below come from the run's console, which is not versioned.

**Conditions**: app built for desktop Linux in debug mode, run headless (Xvfb) in a Docker container, on the project's PC (AMD Ryzen 7 5700U). **The PC is behind a Mullvad VPN.** Cold start: no Tor state on disk, Tor started by the test's first requests, as the first display of the order book will do. A single run, a single time slot: orders of magnitude, not guarantees.

**Result: test green.** The 5 coordinators of the main network (mainnet) gave a verified identity and an order book that was read; on the test network, temple answered, lake did not (as during most of the previous spike).

**Tor startup**: 62.3 s between the first requests and the "ready" state (measured, `tor_state` line of the jsonl). The 57.3 s of Arti followed by Bull's 5 s hold are **deduced** from the console times ("Starting embedded Tor" at 18:20:03.18, "readiness ready" at 18:21:00.46), not measured by the test. That is more than the 14 to 28 s of the spike: cause not established.

**State flicker at startup**: the first four `tor_state` lines give `notStarted` (19 ms), `connecting` (22 ms), `notStarted` (26 ms), `connecting` (26 ms). Bull's Tor briefly goes through `TorStopped`, which `P2pTorState.of` translates into `notStarted` (`p2p_tor_state.dart`). To be handled with the screens (#29), for example by not showing "not started" once a connection has begun.

**Cold load**: the 14 requests (info and order book of 7 coordinators) go out at the same time. Times in seconds since the start; in parentheses, since Tor became ready.

| Coordinator | Network | Info | Order book | Orders kept | Orders dropped | Truncated |
|---|---|---|---|---|---|---|
| bazaar | mainnet | 66.2 (3.9) | 66.7 (4.3) | 18 | 0 | no |
| ammanaya | mainnet | 78.6 (16.3) | 79.3 (16.9) | 10 | 0 | no |
| lake | mainnet | 79.1 (16.8) | 80.3 (17.9) | 37 | 0 | no |
| temple | mainnet | 85.2 (22.9) | 85.6 (23.2) | 32 | 0 | no |
| freeport | mainnet | 130.7 | 130.6 | 0 (empty book) | 0 | no |
| temple | testnet | 77.6 (15.2) | 77.9 (15.6) | 0 (empty book) | 0 | no |
| lake | testnet | `CoordinatorTimedOut` failure at 132.0 | `CoordinatorTimedOut` failure at 132.0 | — | — | — |

- **The retry was useful** (read in the console, not in the jsonl: the `log.info` lines do not name the coordinator): at 18:22:05, 60.1 s after Tor became ready, four first attempts failed when Tor's connection budget expired (`timeout`, 60 s) and were restarted on a new session. The only requests still in progress at that moment, according to the jsonl times, were the two of freeport and the two of lake testnet: this is a deduction. freeport then answered in about 8 s; lake testnet did not answer in the 9.6 s left before the total deadline.
- **The total deadline holds**: the full load took 132.0 s, exactly the deadline of the slowest request (lake testnet), under the test's 3-minute bound.
- **First contacts slower than in the spike**: 3.9 to 23.2 s after Tor became ready, against 2 to 13 s one at a time in the spike. Here 7 sessions open at the same time just after Tor starts; the specific effect of parallelism is not isolated.
- **No order dropped** by the `robosats` package out of 97 orders received, no order book truncated.
- **No refusal linked to the headers**: without `User-Agent` and with `Accept-Encoding: identity`, the 6 coordinators reached answered with valid JSON (the decoy sent to `curl` did not appear).

**Warm load** (the 5 mainnet order books read again right afterwards, on the sessions already open): 0.8 to 4.3 s per coordinator, 4.3 s in total, 5 out of 5.

**Consequence for the screens (#29)**: cold, the total deadline runs during Tor startup. Here Tor took 62 s out of 132: a first contact that fails at the end of Tor's 60 s budget leaves only about 10 s for the retry. Screens must wait for the "ready" state (`watchTorState`) before starting the order books; retrying the failed coordinators afterwards remains an option.

## What is not verified

- **Android**: nothing was run on a phone; all measurements come from a PC.
- **Background and Tor sleep**: the behavior of sessions when Tor goes to sleep and then wakes up is not tested. A dead session should be detected as a connection failure (`proxyUnreachable`) and replaced, but this is only demonstrated with a fake Tor.
- **One session per robot** for authenticated calls: outside this issue (#28).
- **Snowflake, Orbot, network without VPN**: not tried.
- **The `--dart-define=RUN_LIVE_ROBOSATS_TEST=true` form** of the flag, intended for a phone: not tried.
- **The effect of `Accept-Encoding: identity` on the coordinators** beyond this measurement: no refusal seen, but a single run.
- **Canceling a SOCKS connection in progress when the deadline passes**: the transport then closes the session's client, which cancels the `dart:io` connection task (checked with a fake connection: `cancels a connection still being made`). With the real factory of `bull_tor`, canceling only destroys the socket once the SOCKS reply has arrived, so the local connection to the SOCKS port can last up to Tor's budget (60 s), bounded and with no lasting leak; the Tor session is closed right after, but its effect on a SOCKS connection in progress is not verified.
- **The fixes made after the review** were only verified by the unit tests: the real test was not rerun.

## Rerunning the measurement

From the repository root, after `make deps`, `make build-runner` and `make translations`:

```sh
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; RUN_LIVE_ROBOSATS_TEST=true fvm flutter test integration_test/p2p_book_tor_test.dart -d linux --reporter=expanded'
```

The measurements come out on `P2P_BOOK_MEASURE {json}` lines: one per coordinator and per network (order book, info, durations in milliseconds since the start of the load), one per coordinator for the second "warm" load of the main network, and a summary. Without the flag, the test is skipped.
