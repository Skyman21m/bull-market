# A robot on a coordinator (issue #28, first half)

Branch `feat/p2p-robot-coordinator`, 2026-11-11, revised the same day after the independent review of the pull request. Follow-up to [robot-identity.md](robot-identity.md), [pgp.md](pgp.md) and [tor-transport.md](tor-transport.md). Reference: RoboSats at commit `ff1998c` (v0.8.8) of 2026-11-06, so after the per-coordinator token of 2026-10-06 and its revert of 2026-10-15 described below.

This half makes a robot known to a coordinator and reads it back. It stores no key, shows no screen and moves no money: the Garage Key and the robots of the live runs were random, lived in memory only, and are gone.

## Summary

1. **A robot made by Troc exists on a real coordinator.** On 2026-11-11, temple on testnet (RoboSats 0.8.6) created robots from a first contact sent by this code over the embedded Tor, and returned the hash id and the nickname this device had computed, the OpenPGP key pair it had generated, and the Nostr key it had sent. Four runs, eight throwaway robots, every step with the expected outcome.
2. **The coordinator accepts our OpenPGP key.** It returns the public key re-exported by GnuPG, with the same fingerprints, and the encrypted private key byte for byte. This closes the "Real coordinator" line of [pgp.md](pgp.md) for the creation of a robot, not for signatures and chat.
3. **The Nostr key question is settled.** The coordinator of the 0.8.8 source checks no link between the Nostr key and the token, and the one coordinator reached, which runs 0.8.6, stored the key of either formula as sent and kept the first one when the other came later. Two keys on one coordinator: no other key and no other coordinator was tried. Troc sends the formula of the official client since July 2025, `sha256(sha512(token))`. The other one, `sha256(token)`, must never be sent: that secret key is the token hash itself, which the coordinator receives on every request.
4. **A coordinator keeps the first keys it received, for good**, and the official client adopts whatever comes back. This package compares instead: another hash id, nickname or key pair is a typed failure. Seen live: a first contact with a second key pair for the same token gets the first key pair back, reported as `RobotPgpKeyMismatch`.
5. **Each robot has its own Tor session per coordinator**, apart from the anonymous sessions of the book. At most 32 robot sessions exist at a time, all coordinators together, and they are closed with the others or robot by robot.
6. **A Garage Key index whose token fails the entropy rule is skipped.** The official client has no such rule: the robot stays loading and its automatic choice moves on. The effect is the same.
7. **Not verified**: a second coordinator (lake on testnet never answered), mainnet (out of bounds), anything that needs an order (invoice, chat, reward), a phone, and the errors 7000, 7002 and 7004 on a live coordinator.
8. **A rule to enforce before any robot goes to a second coordinator, and before any order: one robot, one coordinator.** The token hash is the same credential on every coordinator, and the official client sends it to all of them at once. A coordinator that holds it can act as the robot on another coordinator in everything that needs the bearer alone, which includes confirming that fiat was received: that settles the robot's escrow there. It is a loss of funds, not a privacy nuisance. RoboSats changed that on 2026-10-06, in commits named after a security advisory, and reverted the change on 2026-10-15; its own notes for agents still describe the scheme. See "The shared token hash".

## What was built

- **`packages/robosats`**: `CoordinatorClient.fetchRobot` (first-contact header, creates or reads) and `fetchKnownRobot` (short header, never creates), the `CoordinatorRobot` they return, the `CoordinatorRobotFailure` family, `GarageKey.firstUsableRobot` with `GarageRobot`, and `RobotSessionKey`, which every authenticated `CoordinatorRequest` carries.
- **`features/p2p`**: `TorCoordinatorTransport` keeps one Tor session per coordinator for the anonymous reads and one per coordinator and robot for the requests of a robot; `FetchRobotUsecase` and `CloseRobotSessionsUsecase` are registered inside the feature, for its coming Garage screens. No screen calls them, and the app-facing library `package:p2p/p2p.dart` has no robot method and exports no type that makes, holds or reveals a robot: shell code cannot generate or reveal a Garage Key through it.
- **Tests**: offline in both packages, and the opt-in live test `integration_test/p2p_robot_tor_test.dart`.

## The exchange

One endpoint, `GET /api/robot/`, and two forms of the `Authorization` header. Their structure, never their values:

| Form | Header value | Sent by |
|---|---|---|
| First contact | `Token <A> \| Public <B> \| Private <C> \| Nostr <D>` | `fetchRobot` |
| Short | `Token <A>` | `fetchKnownRobot` |

- `<A>`: the basE91 form of the SHA-256 of the robot token, 39 or 40 characters. It is the credential of the robot on every coordinator.
- `<B>` and `<C>`: the armored OpenPGP public key and the armored private key locked by the token, each on one line, every line break replaced by a backslash.
- `<D>`: the Nostr public key of the robot, 64 lowercase hexadecimal characters.
- The parts are separated by space, pipe, space; a coordinator requires exactly four parts or treats the whole value as the token hash (`robosats/middleware.py:51-59`).
- The other request headers are `Accept: application/json` and the transport's `Accept-Encoding: identity`; no `User-Agent`, no cookie, no body, no query.

What a coordinator does (`robosats/middleware.py:62-178`, `api/views.py:697-743`, `api/utils.py:496-669`):

| Situation | Answer |
|---|---|
| `<A>` is not 39 or 40 basE91 characters | HTTP 400, `{"error_code": 7000, "bad_request": …}` |
| `<A>` is unknown and the header is the short one, or a key is missing | HTTP 400, error 7001: nothing is created |
| `<A>` is unknown and a PGP key is refused | HTTP 400, error 7002, whose message holds the key error: 1034 (GnuPG or the shape check refuses a key), 1055 (public key already used by another robot), 1056 (key less than 12 hours old) |
| `<A>` is unknown, the keys are accepted, the nickname already exists | HTTP 409, error 7004 |
| `<A>` is unknown and everything is accepted | the robot is created with the hash id and nickname the coordinator computes from `<A>`, the public key as GnuPG re-exports it, the private key and the Nostr key as received; then HTTP 200 |
| `<A>` is known | `<B>`, `<C>` and `<D>` are ignored, whichever header is sent; HTTP 200 with the keys of the first contact |

Seen on the live coordinator: the short header on an unknown robot (error 7001), the creation, and a known robot under both headers. The errors 7000, 7002 and 7004 are read from the source and tested offline only.

The `200` body is the same in every case: `nickname`, `hash_id`, `public_key`, `encrypted_private_key`, `earned_rewards`, `wants_stealth`, `nostr_pubkey`, `webhook_url`, `webhook_enabled`, `webhook_api_key`, `last_login`, `tg_enabled`, `tg_token`, `tg_bot_name`, then `active_order_id` or `last_order_id` when the robot has one, and `found: true` once the robot is more than five minutes old. Nothing else tells a robot that was just created from one the coordinator already knew.

What the official client does with it (`frontend/src/models/Robot.model.ts:88-147`, `Slot.model.ts:40-101`): it sends the first-contact form every time, to every coordinator of the federation at once, with the same token hash and the same PGP key pair, and it replaces its local keys with the ones of the answer without any check.

## What this package does differently, on purpose

- **It checks the answer against this device.** The `hash_id` and the `nickname` must be the ones derived from the token (`RobotHashIdMismatch`, `RobotNicknameMismatch`), and they are compared before any key of the answer is parsed. The `public_key` must have the fingerprints, primary key and encryption subkey, of the local key, and the `encrypted_private_key` must hold the packets of the local one, whatever its armor (`RobotPgpKeyMismatch`). A coordinator that returned another key pair would otherwise become the reader of the robot's chat without a sign.
- **It never adopts a key.** The second device of a restored Garage Key generates its own key pair; the coordinator ignores it and returns the first one, which is a `RobotPgpKeyMismatch` here. Taking that robot over is a separate, explicit step that does not exist yet: see "What the next steps need to know".
- **It sends canonical armor only.** A key object holds the canonical armor of its packets, base64 between the two fixed lines, as the official client writes it, whatever armor it was read from. An armor header such as `Comment`, which may hold any text, is accepted when reading and never kept, so it cannot add a fifth part to the first-contact header or put in it a character an HTTP header cannot carry. Refusing armor headers was the other option; it would have made the keys GnuPG writes with a `Version` or `Comment` line unreadable.
- **It checks a taken nickname before reporting it.** A coordinator that receives the same first contact twice at once creates the robot for one copy and answers the other with error 7004; the transport can cause that when it retries a request whose connection broke after it was sent. After a 7004, one request with the short header tells whether the coordinator knows this very robot. Tested offline only, and not airtight: see "What the next steps need to know".
- **It reads less.** The Telegram and webhook fields are ignored: Troc uses neither, and `tg_token` and `webhook_api_key` are credentials.
- **It contacts one coordinator per call.** Nothing sends a robot to the whole federation.

## Token entropy rule

The official client has no rule that skips an index (commit `ff1998c`). `Robot.fetch` returns before any request when the token fails `validateTokenEntropy` (`Robot.model.ts:99`) and never resets `loading`, so the robot stays "loading" for ever; `Slot.isReusable()` is `false` while loading, so `Garage.ensureReusableSlot` and `findNextUnusedAccount`, which looks at 100 indexes at most, move on to the next index. `Order.make` has no entropy check of its own.

`GarageKey.firstUsableRobot(fromIndex)` follows the net effect: it skips an index whose token fails the rule, over 100 indexes at most. It also skips an index whose hash id has no nickname (once in 2^54), a robot no coordinator can create; this second skip is Troc's own. A token that fails the rule cannot become a `RobotToken`, so no request of this package can carry one, as in the official client. No Garage Key is known that has such an index: the skip is tested through an injected derivation.

## The robot's Nostr key

**Answer: a coordinator expects neither formula. The coordinator of the 0.8.8 source takes any 64 hexadecimal characters, stores them at the first contact and changes them afterwards in one case only, a stored placeholder made of zeros. The one live coordinator reached, which runs 0.8.6, stored each of the two keys tried. Troc sends `sha256(sha512(utf8(token)))`, `NostrKeyDerivation.currentFrontend`, and must not send the other one.**

What "accepts any key" rests on, exactly: the source of one version, and two keys, the two formulas, on one coordinator of another version. No arbitrary key was sent, and no other coordinator answered.

Evidence, in three layers:

1. **The coordinator's code** (`robosats/middleware.py:29-37`, `:98-107`, `:126-172`): the key is whatever matches `[0-9a-fA-F]{64}` in the fourth part of the header, lowercased, stored when the robot is created. No signature is asked, and nothing relates it to the token hash or to the PGP key. For a known robot the received key is ignored, with one exception: when the stored one is the placeholder `000…0`, which the coordinator uses for a key it lost, the key of a later request replaces it (`:98-107`, at most every two minutes). That exception was not seen live.
2. **The coordinator's answers** (temple, testnet, every run):

   | Robot | Nostr key sent at the first contact | `nostr_pubkey` returned | Read back with the short header |
   |---|---|---|---|
   | A | `currentFrontend` | the same key | the same key |
   | A, already known | `repositoryFixtures` | still the `currentFrontend` key | |
   | B | `repositoryFixtures` | the same key | the same key |

   A coordinator that expected one formula would have refused or replaced one of the two. The only formula it could check is `repositoryFixtures`, whose secret it can compute; this one accepted the other without a word.
3. **The history of the official client** (public GitHub API, read on 2026-11-11): the Nostr key came with commit `e78d86feba` of 2025-04-27 ("nostr pubkey for Robot") as `sha256(token)`; commit `a71173abe3` of 2025-07-09 ("Simplify nostr key generation") changed it to `sha256(sha512(token))`, which is still the code at `ff1998c`. `tests/robots/1/nostr_pubkey` was last changed on 2025-05-31 (`ceead5315d`), before that change, and `development/docs.md:80` was never updated. So the fixtures carry the first formula, which the official client used for about ten weeks.

Why the first formula must not be used. Its secret key is `sha256(utf8(token))`: exactly the 32 bytes whose basE91 form is the `<A>` of every request. Any coordinator the robot contacts can compute that Nostr secret key, sign as the robot and read what is sent to it. The current formula hashes the token again through SHA-512 first, which a coordinator cannot reproduce from `<A>`.

What the choice changes in practice: the coordinator gives the stored key to the trade peer (`maker_nostr_pubkey`, `taker_nostr_pubkey`) and sends its notifications to it, and the robot reads them with the secret key its own client derives. A robot shared between Troc and the official client reads the same messages in both only with `currentFrontend`. `CoordinatorRobot.nostrKeyDerivation` says which key a coordinator holds for a robot, `null` when it is neither: a robot first created by a client of spring 2025, or one whose key the coordinator replaced by the placeholder.

Left in the code: `repositoryFixtures` stays in `NostrKeyDerivation`, to recognise such a key and for the test vectors. `CoordinatorClient.fetchRobot` still takes the formula as a parameter, for the live test; `FetchRobotUsecase`, through which the feature will make its first contacts, does not, so the app can only send `currentFrontend`.

Not verified: the current formula's output was not compared with the official client running. It is computed from the same specification by two independent implementations (the Dart code and the Node script of the vectors), and that is all.

## Does a real coordinator accept our identity and our PGP key?

**Yes, for the creation of a robot.** temple on testnet accepted every first contact this code sent: eight robots over four runs, each with a key pair made by `RobotPgpKey.generate` minutes earlier and dated 24 hours back.

| What the coordinator checked or returned | Result |
|---|---|
| Token hash: 39 or 40 basE91 characters | accepted |
| Header split into four parts, keys with backslashes for line breaks, about 2 KB, sent by `dart:io` through the SOCKS port of the embedded Tor | accepted: the keys arrived intact |
| Public key: shape check, GnuPG import, age | accepted (the 12-hour rule is in the source at `ff1998c`; whether 0.8.6 already has it is not known) |
| Encrypted private key: GnuPG import without passphrase | accepted |
| `hash_id` computed by the coordinator from the token hash | equal to `RobotIdentity.hashId` |
| `nickname` computed by the coordinator's generator | equal to `RobotIdentity.nickname`, for eight different robots |
| `public_key` returned | not the text sent: 693 characters for 694 sent, the re-export by GnuPG; same fingerprint of the primary key and of the encryption subkey, and `PgpPublicKey.parse` verified its self-certification and its subkey binding |
| `encrypted_private_key` returned | byte for byte the text sent, 923 characters |
| `nostr_pubkey` returned | the key sent |
| Short header before the first contact | error 7001, read as `RobotUnknown` |
| Short header after the first contact | the same robot |
| First contact again | the same robot |
| First contact with a second key pair for the same token | the first key pair comes back: `RobotPgpKeyMismatch` |
| Short header five minutes and twenty seconds after the creation | the same robot, now with `found: true` (runs 2 to 4) |

The answer has 14 fields, in this order: `nickname`, `hash_id`, `public_key`, `encrypted_private_key`, `earned_rewards` (integer), `wants_stealth` (boolean), `nostr_pubkey`, `webhook_url` (empty string), `webhook_enabled` (boolean), `webhook_api_key` (`null`), `last_login` (`YYYY-MM-DDTHH:MM:SS.ffffffZ`), `tg_enabled` (boolean), `tg_token` (15 characters), `tg_bot_name` (24 characters). It weighs about 2.1 KB and comes as `application/json`. The offline tests build their answers on this shape, with the values of the public test robot of the RoboSats repository; no live answer is stored anywhere.

What this does not prove: that a coordinator accepts a clear-signed invoice or a chat message made by this code. Both need an order, which is outside this half.

## Tor sessions

- Anonymous requests keep one session per coordinator origin, as before. A request made for a robot uses a session kept for that robot on that coordinator, with its own HTTP client, so its own connections: no circuit and no connection is shared with another robot, with the same robot on another coordinator, or with the anonymous reads of the book.
- The guarantees of the transport are unchanged and apply to both kinds, since they share the code path: total deadline of 132 s, size cap, `http` to `.onion` hosts only, no redirect followed, no `User-Agent`, `Accept-Encoding: identity`, a `GET` retried at most twice on a new session of the same robot after a connection failure. `GET /api/robot/` creates the robot at most once, so a retry reads it back.
- At most 32 robot sessions exist at a time (`maxRobotSessions`), all coordinators together. The bound counts every robot session that is opening, open or closing, the ones a connection failure replaced while a request still uses them included. Beyond it, a new session takes the place of one that is closing, or else of the least recently used one that no request is using or about to use, and opens only once that one is closed. When every place is taken by a session in use, the request fails with `CoordinatorTransportFailed`, a retry after a connection failure included. The anonymous sessions are neither counted nor closed by this.
- `closeRobotSessions` closes the sessions of one robot to every coordinator, and `closeSessions` closes everything, in both cases the sessions that a connection failure replaced while a request was still on them too. A request that was running fails instead of opening a new session, whichever session it was on, and a session that finishes opening afterwards is closed unused. The review of the pull request found the gap this closes: a request left on a replaced session survived `closeRobotSessions`, and sent the credential again on a new session after a later connection failure.
- Header names and values are checked before any session opens: an HTTP token for the name, printable ASCII for the value. Anything else fails with `CoordinatorTransportFailed`, as does a request `dart:io` refuses to write, without a retry: its exception would quote the header value.
- A request that carries an `Authorization` header without naming its robot is refused before any session opens, and the client of `packages/robosats` cannot build one. The guard looks at that header only: the chat websocket will carry the token hash in a query parameter, and the guard must be extended when it arrives.
- The log line of a retry gives the Tor reason and two counters only. It names neither the coordinator nor the robot, and a test reads what is printed to keep it so.
- **Not verified**: that two Tor sessions of the embedded Tor really use distinct circuits is a property of `bull_tor` and Arti that the tests take as given; the tests prove that the transport asks for distinct sessions and never mixes their connections.

## Measurements

**Four runs on 2026-11-11, one machine, one coordinator: orders of magnitude, not guarantees.** The 79 raw lines are versioned in [robot-coordinator-measurements.jsonl](robot-coordinator-measurements.jsonl), each with its run number; they hold labels, numbers and booleans only. The retry lines and the Tor start come from the console of each run, which is not versioned.

**Conditions**: the app built for Linux desktop in debug mode, run headless (Xvfb) in the `troc-integration` container, on the project's PC (AMD Ryzen 7 5700U) behind a Mullvad VPN. Tor starts cold in every run. Each run draws a new random Garage Key and uses its robots 0 (robot A) and 1 (robot B).

| | Run 1 | Run 2 | Run 3 | Run 4 |
|---|---|---|---|---|
| Time (UTC) | 00:59 to 01:04 | 01:06 to 01:13 | 01:16 to 01:22 | 01:31 to 01:37 |
| Commit | `4e906cf46` (see below) | `58d10da32` | `865b149b4` | `7b32ab28d`, the last code commit |
| Embedded Tor ready | 16 s | 14 s | 13 s | 25 s |
| `/api/info/` of temple, cold, Tor start included | 27.2 s | 34.5 s | 23.3 s | 32.4 s |
| Robot A, short header before the first contact (opens the session of robot A): `RobotUnknown` | 74.9 s | 6.0 s | 6.3 s | 7.0 s |
| Robot A, first contact: created | 1.4 s | 1.6 s | 1.6 s | 1.1 s |
| Robot A, short header | 0.7 s | 1.1 s | 0.7 s | 0.7 s |
| Robot A, first contact again | 0.7 s | 1.2 s | 0.8 s | 0.7 s |
| Robot A, first contact with a second key pair: `RobotPgpKeyMismatch` | 0.7 s | 1.1 s | 0.7 s | 0.7 s |
| Robot A, first contact with the other Nostr key: first key kept | 1.0 s | 1.0 s | 0.8 s | 0.9 s |
| Robot B, first contact with the other Nostr key (opens the session of robot B): created, key stored | 4.3 s | 6.1 s | 5.7 s | 7.1 s |
| Robot B, short header | 0.7 s | 1.2 s | 0.7 s | 1.4 s |
| Robot A, short header 5 min 20 s after its creation | not in this run | 2.4 s, `found: true` | 1.7 s, `found: true` | 1.6 s, `found: true` |
| Size of the answer | 2,116 bytes | 2,118 bytes | 2,118 bytes | 2,119 bytes |
| lake on testnet, `/api/info/`, three attempts | unreachable | unreachable | unreachable | unreachable |
| Generating a key pair (three per run) | 0.67, 0.43, 0.42 s | 0.64, 0.41, 0.39 s | 0.63, 0.41, 0.39 s | 0.66, 0.41, 0.39 s |
| Whole test | 307 s | 366 s | 354 s | 364 s |

- **Every step gave the same outcome in the four runs**, and no step needed a second attempt at the level of the test.
- **Run 1 and its commit**: the application was building while the nickname check of commit `763630461` was being written in the same worktree, so run 1 ran `4e906cf46` with or without that change. The steps it took do not go through it. Run 1 also asked the facade for the books to list the coordinators, which started two anonymous book requests next to the measured ones. Run 4 is the reference: it ran the code as delivered.
- **The first request of a robot pays for its session.** It took 6 to 7 s in runs 2 to 4, and 4 to 7 s for robot B, against about 1 s for the requests that follow on the same session. That matches a new Tor session with new circuits to the onion service for each robot, which is the intent; it does not prove that the circuits differ.
- **The 74.9 s of run 1**: the console shows a retry line with the reason `timeout` exactly 60 s after that step began, which is Tor's connection budget, and the step ended 15 s later. The first session of robot A seems to have failed to connect, and the retry on a new session to have succeeded: a deduction, the retry lines do not name their request. The transport's retry was useful here.
- **lake on testnet** did not answer `/api/info/` in twelve attempts, each ended by `CoordinatorUnreachable` after two retries (reason `hostUnreachable`, once `timeout`). It was already down during the spikes of 2026-11-10.
- **No secret in the logs**: the four consoles were searched for a Garage Key, an armored block, an `Authorization` header and long hexadecimal strings before the lines were copied.

## The shared token hash

**The fact.** `<A>`, the token hash, is the whole credential of a robot, and it is the same on every coordinator. At `ff1998c` (2026-11-06) the official client computes one `tokenSHA256` per robot (`frontend/src/models/Slot.model.ts:32`) and sends it to every coordinator of the federation at once (`Slot.model.ts:40-53` and `:89-101`).

**The consequence.** A coordinator that has received `<A>`, because the robot was sent to it, can present it to any other coordinator where the same robot exists, and is then that robot there for everything that asks for the bearer alone. On an order (`api/views.py:557-690`, all under `TokenAuthentication`) that is every action but the two that carry a PGP-signed text, `update_invoice` and `update_address`:

- `confirm`: when the robot is the seller and the buyer has marked the fiat as sent, it settles the seller's escrow and pays the buyer (`api/logics.py:1686-1736`, "KEY LINE - SETTLES THE TRADE ESCROW"). A dishonest coordinator working with the buyer takes the seller's sats without any fiat being paid.
- `cancel`, which can forfeit the robot's bond or cancel its trade, `dispute`, `submit_statement`, `undo_confirm`, `pause`, `take` and the ratings, and `POST /api/make/` for a new order.
- It also reads the robot (`GET /api/robot/`, the encrypted private key included, which stays locked by the token), its orders and the ciphertexts of its chat.

So this is a loss of funds for a robot that trades on one coordinator and was also sent to another, not a privacy nuisance. It is read from the source; it was not reproduced, and nothing here tests it.

**The evidence that upstream knows.** Read on 2026-11-11, in the clone and through the public GitHub API, the clone being shallow:

- Commits `551e228cc1` and `ec24f301c0` of 2026-10-06, both titled "Fix GHSA-22q8-9ghc-jg3h", made Garage Key robots send a distinct token hash per coordinator, "so that a compromised coordinator cannot replay the token at another one". Commit `51a65ef700` of 2026-10-15, "Revert fix", removed it. The advisory itself is not published.
- The reference clone postdates both: `ff1998c` is of 2026-11-06. Its code has no per-coordinator token (`deriveCoordinatorToken` appears in no source file), but its notes for agents still describe the reverted scheme as if it were in place: `frontend/src/models/AGENTS.md:36-47` gives the bearer as `sha256("robosats-coordinator-token:" + shortAlias + "|" + baseToken)` and states the property, "a malicious/compromised coordinator only ever sees its own `tokenSHA256`", "blocking the bearer-replay / escrow-settlement attack", and `frontend/src/utils/AGENTS.md:22` and `:184` still list `deriveCoordinatorToken` and forbid changing its prefix. Upstream named the attack, wrote the fix, and ships without it.

**What this client cannot fix by itself.** A coordinator cannot tell a replayed bearer from the robot. Troc could apply the reverted scheme on its own, but the hash id and the nickname come from the token hash: a robot made so would be a different robot on each coordinator, and no longer the one the official client derives from the same Garage Key index. That is a product decision, not taken here.

**The rule, to enforce before any robot goes to more than one coordinator and before any order: one robot index is bound to one coordinator.** The coordinator is recorded at the first contact of that index, and every later request for that robot is checked against it in code, not left to the screens. A robot that has no other coordinator has given its bearer to nobody who could replay it. The record needs storage, so the rule comes with the second half of #28; until then nothing in the app can make a first contact, since no screen and no app-facing method reaches the robot calls. The cost is that Troc does not offer what the official client does, one robot visible on the whole federation: an order on another coordinator takes the next index.

## Also found in the public RoboSats history

- The two Nostr formulas and their dates: see "The robot's Nostr key".

## Limits

- One machine, a desktop PC behind a VPN, a Linux desktop build in a container; nothing was run on a phone.
- Testnet only, and one coordinator only: temple, which runs RoboSats 0.8.6 while the source read here is 0.8.8; lake on testnet did not answer `/api/info/` in any run.
- A new robot only: no order, no invoice, no chat, no reward, so the signature and chat paths of [pgp.md](pgp.md) are still unverified against a coordinator.
- Errors 7000, 7002 and 7004 were not provoked on a live coordinator; their handling is tested offline from the coordinator's source.
- `found: true` was seen in runs 2 to 4, on robots five minutes old; nothing older was read.
- Nothing in the code restricts an authenticated call to testnet: only the live test does. The use case inside the feature would create a robot on a mainnet coordinator if a screen asked; nothing outside the feature can reach it.

## What the next steps need to know

**Storage (second half of #28)**

- **The coordinator of each robot index.** The rule of "The shared token hash" needs, per Garage Key index, the one coordinator the robot was sent to, written before the first contact leaves and read before every request. It is the first thing the storage must hold, and the check belongs in the use case, so that no screen can skip it.
- A robot needs, per Garage Key index: the token (derivable from the Garage Key) and its PGP key pair. The key pair is random, not derived from the token: it must be stored, or recovered from a coordinator. A coordinator keeps the first key pair it received for good, so a robot whose key pair is lost can never get a new one on that coordinator.
- The encrypted private key is only as secret as the token, and every coordinator the robot contacted holds a copy.
- Recovery on a new device is not written. It needs: the short header, the answer's `encrypted_private_key` proven by unlocking it with the token (the only proof that the key was made by a holder of the token), then adopting that pair for that coordinator. Until then such a robot gives `RobotPgpKeyMismatch`.
- A key pair is dated 24 hours back and a coordinator refuses one younger than 12 hours for its own clock: a device whose clock is more than 12 hours ahead gets `RobotKeysRefused(keyTooRecent)`.
- Generating a key pair hashes 32 MiB of SHA-256, 0.4 to 0.7 s on this PC in debug mode: off the UI isolate.

**Garage screens (#30)**

- One robot, one coordinator: see "The shared token hash". The Garage screens must not offer the official client's robot on every coordinator; an order on another coordinator takes another index.
- `fetchRobot` creates an account on a third-party server that this client cannot delete.
- `found` is the only hint that a robot existed before; `activeOrderId` and `lastOrderId` say whether it can be reused.
- An unusable index is answered by the next robot of the Garage Key, `firstUsableRobot(index + 1)`.
- `RobotNicknameTaken` must not be answered that way at once. The client already asks once with the short header, but the reference coordinator creates the user (`robosats/middleware.py:152`) before the token (`:163`): a follow-up that lands between the two gets error 7001, and the failure is reported although the robot is being created for this device. So, before giving up an index, ask again with the short header a little later (`fetchKnownRobot`): if the robot is there, keep it. And a coordinator can answer 7004 for ever: cap how many indexes one coordinator can make the user give up, or it burns through the Garage Key.
- The failures need their own texts: today `CoordinatorRobotFailure` falls back on the generic book error in `p2p_failure_l10n.dart`.
- Close the sessions of a robot that is no longer used (`CloseRobotSessionsUsecase`), and expect `CoordinatorTransportFailed` if more than 32 robot sessions, all coordinators together, are in use at once.
- Creating a robot is always explicit: `FetchRobotUsecase.execute` has no default for `createIfUnknown`.

## Rerunning

Offline:

```sh
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools bash -c 'make deps && (cd packages/robosats && fvm dart test) && (cd features/p2p && fvm flutter test)'
```

Live, on testnet coordinators only, in the `troc-integration` image, after `make deps`, `make build-runner` and `make translations`:

```sh
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; RUN_LIVE_ROBOSATS_TEST=true fvm flutter test integration_test/p2p_robot_tor_test.dart -d linux --reporter=expanded'
```

The measurements come out on `P2P_ROBOT_MEASURE {json}` lines: labels of this app, numbers and booleans only. A field name of the answer is printed only when it is one the reference source sends, the others are counted; the content type and the form of the date are reduced to a boolean and a fixed label. Without the flag, the test is skipped. Each run creates two throwaway robots on every testnet coordinator it reaches. The test drives the client of `packages/robosats` over the real transport of the app, which `package:p2p/testing.dart` hands out to tests only.
