# Spike 2: RoboSats robot identity in Dart

Written on 2026-11-10. Code: package `packages/robosats` (pure Dart, no Flutter, no network, no PGP). Reference: RoboSats at commit `ff1998c`.

## Summary

1. The computation that turns a Garage Key (`robo1…`) into a robot is reproduced in Dart end to end: token, value sent to the coordinator, public ID, nickname, Nostr key, `Authorization` header.
2. All the check values prepared before the spike are matched character for character, without exception: the 3 test robots of the RoboSats repository, the sample Garage Key, the 2 edge cases, the 200 nicknames and the sample header.
3. The nickname depends on a floating-point division: the port reproduces it exactly, including on 38 hashes built on purpose to hit the rounding cases that the 200 nicknames do not cover.
4. One question remains open, as expected: the formula of the robot's Nostr key. Both formulas are available and tested; the one in the current code of the official app is used by default. To be settled against a real coordinator before creating a real robot.
5. No new dependency: the `pubspec.lock` file has not changed.

## What is reproduced, and what it is checked against

The check values are in `packages/robosats/test/fixtures/robot-identity-vectors.json`, an exact copy of the spike's preparation file. Its `_avertissement` ("warning") and `_comment_chaque_valeur_est_produite` ("how each value is produced") fields, in French, say where each value comes from.

| Item | In the package | Checked against |
|---|---|---|
| Garage Key: generation (32 bytes, secure generator, injectable in tests), bech32 form `robo1…`, validation | `GarageKey.generate`, `GarageKey.parse`, `GarageKey.fromBytes` | sample key of `garageKey.test.ts` (RoboSats repository); round trip on 300 random keys; 500 keys altered in 1 to 4 characters, all rejected; wrong prefix, wrong length, mixed case, non-zero padding |
| Token of robot number `i`: SHA-512, BIP32 `m/44'/88'/i'/0`, 36 least significant base62 digits | `GarageKey.deriveToken` | tokens of indexes 0, 1 and 18 asserted by `garageKey.test.ts`; index 6 of the vectors; intermediate private key of the vectors; test vector 1 of the BIP32 specification; 25 random seeds and paths compared with the wallet's BIP32 library (`bip32_keys`) |
| Token entropy rule (bits > 128 and Shannon > 4) | `RobotToken.parse`, `RobotToken.measureEntropy` | the 8 tokens of the vectors; 9 boundary cases whose expected values come from RoboSats' `validateTokenEntropy` function, copied and run under Node |
| `tokenSHA256` in basE91 | `RobotIdentity.tokenSha256Base91` | `tests/robots/N/b91_token` files of the repository (3 robots); 5 other values of the vectors, including the 39-character case; round trip on 2,000 byte sequences |
| `hash_id` | `RobotIdentity.hashId`, `RobotHashId.parse` | 8 values of the vectors; user ID of the PGP key of test robot 1, read by GnuPG |
| Nickname | `RobotHashId.nickname`, `RobotIdentity.nickname` | 200 nicknames produced by the coordinator's Python code; `tests/robots/N/nickname` files; dictionaries recomputed identically (same SHA-256 fingerprint as the RoboSats files) |
| Robot Nostr key, formula of the current code | `identity.nostrKeyPair()` | vectors only (see the open question) |
| Robot Nostr key, formula of the test fixtures | `identity.nostrKeyPair(NostrKeyDerivation.repositoryFixtures)` | `tests/robots/N/nostr_pubkey` files of the repository (3 robots) |
| Nostr key of the Garage Key (current and legacy) | `GarageKey.recoveryNostrKeyPair`, `legacyRecoveryNostrKeyPair` | values asserted by `garageKey.test.ts` |
| `Authorization` header, short form and first contact | `authorizationHeader()`, `firstContactAuthorizationHeader(...)` | example of the vectors, rebuilt from the PGP keys of `tests/robots/1/`; `\r\n` and `\r` line endings; split into 4 pieces as the coordinator does |

Two points of method:

- **Floating-point arithmetic of the nickname.** The 200 reference nicknames do not tell a floating-point computation apart from an exact-integer one (checked: an exact-integer port passes them all). A second file, `nickname-float-boundaries.json`, holds 38 hashes placed on the boundaries: 8 where floating point and exact integers diverge, 8 where the rounding of the conversion matters, 15 cases of exact ties between two floats, 7 extreme values. The expected values come from Python arithmetic (same formula as RoboSats), not from running RoboSats' code.
- **Secret values.** Garage Key, token, hash sent to the coordinator and Nostr secret key never appear in `toString()`, nor in errors. An explicit call (`reveal…`) is needed to read them. The package writes no log.

## Open question: the robot's Nostr key

The RoboSats repository contains two formulas that give different keys:

- `sha256(sha512(token))`: the current code of the app (`frontend/src/models/Slot.model.ts:34-38`). It is the default choice (`NostrKeyDerivation.currentFrontend`). No file of the repository makes it possible to check its result for a token.
- `sha256(token)`: the formula that gives back the `tests/robots/N/nostr_pubkey` files and that `development/docs.md:80` describes (`NostrKeyDerivation.repositoryFixtures`).

The coordinator records the key only once, when the robot is created, without any check. A wrong formula produces no error: the robot would simply receive neither notifications nor Nostr chat in the official app. To be settled before the first real robot, by creating a robot with the official app on a test coordinator and reading `nostr_pubkey` in the response of `GET /api/robot/`.

## Findings and decisions

- **No disagreement found** between the preparation note (part A) and the RoboSats source code on the implemented points.
- **Case not reported by the note: a hash with no nickname.** When the hash is at least 2^256 − 2^202 (one chance in 2^54), the floating-point quotient rounds to 1.0 and RoboSats' Python code raises an index error: no coordinator can create this robot. The package then returns the `NicknameUnavailable` failure instead of crashing. This is useful above all for a `hash_id` received from a peer, which is untrusted data.
- **BIP32 written in the package** (about forty lines) rather than with `bip32_keys`: the repository's custody check (`make custody-check`) reserves that library's private derivation to `packages/secrets`. A Garage Key is not a wallet seed. The check, run on the package alone, reports nothing. `bip32_keys` is only used as a point of comparison in the tests. **This package handles key material (Garage Key, tokens, Nostr keys): to be flagged in the pull request.**
- **A token that is too weak is not a `RobotToken`.** `RobotToken.parse` rejects it (`TokenEntropyTooLow` failure), just as the official app refuses to contact a coordinator with it. `measureEntropy` remains available to guide input.
- **Strict `hash_id`**: 64 lowercase hexadecimal characters, nothing else.
- **Base-2 logarithm.** Dart has none; it is exact for powers of two, so both thresholds (128 bits, Shannon 4) behave as in JavaScript in those cases. For other values, the possible difference with JavaScript is in the last digits (tests within 10⁻¹²), with no effect on accepting a realistic token.
- **Added beyond the request**: the Nostr key of the Garage Key itself (used to find the index of the last robot), because the vectors contain it.
- **Not done, out of scope**: generating a random "legacy" token (without a Garage Key), avatar, PGP, network.
- **`FEATURES.md` not changed**: the rule (AGENTS.md, rule 13) targets adding a feature or a change in what a feature consumes. This package is not used by any feature yet, and the infrastructure packages in the same situation (`bull_pricer`, `bull_payjoin`) are not listed there. The entry is to be added with the first feature that uses it.
- **To be updated elsewhere**: `AGENTS.md` and `ARCHITECTURE.md` list the workspace members ("checked 2026-11-08"); `packages/robosats` is not there yet.

## Dependencies

The package declares `crypto` (SHA-256, SHA-512, HMAC), `pointycastle` (secp256k1 curve), `bech32`, `convert`, `meta` and `primitives` (`Result`, `Failure`); for tests only, `bip32_keys`. All were already in `pubspec.lock`: after `fvm flutter pub get`, the file is unchanged, and `make deps` (strict lockfile) passes. Only the root `pubspec.yaml` gains a line (`- packages/robosats`).

BasE91, base62, bech32 bit regrouping and BIP32 are written in `lib/src/`, with their tests. The nickname dictionaries (4,832 adjectives, 12,591 nouns) are copied from RoboSats (AGPL-3.0, like Troc), with a statement of origin at the top of the file.

## What could not be checked here

1. **Against the real libraries of the official app** (`base-ex`, `js-sha256`, `@scure/bip32`, `nostr-tools`, `robo-identities-wasm`): the vectors come from a re-implementation. This spike adds independent cross-checks (BIP32 against `bip32_keys` and the specification, Nostr public key computed by two different libraries), but not running the frontend.
2. **The robot's Nostr key, current formula**: see the open question.
3. **The nickname computed by the official app** (`generate_roboname`) is assumed to be identical to the coordinator's; only the coordinator's code served as the reference.
4. **RoboSats' Python code on the 38 boundary hashes**: running it was not allowed in this session. The expected values come from the same formula computed by Python, which validates the arithmetic but not the choice of words on those exact hashes.
5. **The checks of the whole project.** `make analyze`, `make unit-test` and `make custody-check` need the generated code, absent locally: they were not run. Their equivalents were run on the package alone (analysis, format, `dart fix`, custody check, tests) and are green. `make fix-check` on the whole project was run and fails locally: it suggests fixes in 70 existing files of the app and none in this package, probably for lack of generated code. To be confirmed by CI.
6. **No exchange with a coordinator**, and no timing measurement on a phone.

## Rerunning the tests

From the repository root, with the local tools image:

```
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools bash -c 'make deps && cd packages/robosats && fvm dart test --reporter=expanded'
```

Result of 2026-11-10 (Dart 3.12.2): 169 tests, all green.

In CI, `make unit-test` picks up the package automatically, since it is in the `workspace:` list.
