# Spike 3: RoboSats robot PGP in Dart

Written on 2026-11-10, updated the same day after the security review, and on 2026-11-11 for the first exchange with a coordinator (status line "Real coordinator" of the interoperability matrix). Since the review of that exchange, a key that is read (`PgpPublicKey.parse`, `RobotPgpKey.parse`) holds the canonical armor of its packets, as a generated key always did: armor headers are accepted and dropped. What the package writes is unchanged byte for byte, so the cross-check with GnuPG and OpenPGP.js was not rerun. Code: package `packages/robosats` (pure Dart, no Flutter, no network). Reference: RoboSats at commit `ff1998c`. Preparation note: `preparation-identite-et-pgp.md`, part B (project folder).

## Summary

1. The package can create a robot's PGP key, read it back, sign an invoice or an address, and encrypt, sign, decrypt and verify a chat message.
2. **GnuPG 2.4.4, the coordinators' engine, and OpenPGP.js 5.11.3, the official app's library, accept everything the code produces, and the code reads everything they produce.** This is checked both ways by a rerunnable script, and by two independent security reviews on 1,000 to 1,500 messages each way.
3. The key produced and the chat messages have exactly the same structure as those of the official app: a coordinator cannot tell Troc from the official app by their form.
4. After the security review of 2026-11-10, **`dart_pg` is entirely removed**: all the OpenPGP that RoboSats needs is written in the package, on top of existing primitives (`pinenacl`, `pointycastle`, `crypto`). Owner's decision: this Dart layer is provisional, a Rust library will replace it before any release.
5. Everything the package reads is bounded in size and cost: no message, no key, no signature coming from a coordinator or a peer can crash the app or throw an exception.
6. Nothing was sent to a coordinator during this spike. Since then (2026-11-11, issue #28) a testnet coordinator accepted a key pair made by this code at the creation of a robot: see the interoperability matrix.

## Library

**Why `dart_pg` 2.0.0 was removed.** Findings made by running it, then by the security review:

1. **Denial of service without any key.** Its packet reader decompresses recursively while reading, before any authentication: a 415-character message (4 GiB once decompressed) killed the process.
2. **A mark in every signature**: a random `salt@notations.dart-pg.org` notation, which cannot be disabled (`lib/src/packet/signature.dart:188-192`), and which would single out Troc to the coordinator.
3. **Randomness not injectable** (`lib/src/common/helpers.dart:24`): no deterministic test possible.
4. **Two errors with leading zeros**: one Ed25519 key in 256 unreadable, about one valid signature in 100 rejected.
5. **Untyped exceptions on a hostile peer key** (altered KDF parameters); self-signature different from that of OpenPGP.js; armor headers; key reading dependent on the clock.

**What replaces it.** `lib/src/pgp/` (1,891 lines, comments included) contains the armor, the packets, the keys, the signatures, the ECDH key exchange (RFC 6637) with the AES key wrap (RFC 3394), the encrypted block with integrity protection and the bounded reading of messages. `lib/src/robot_pgp_key.dart` (520 lines) is the public interface. The primitives come from `pinenacl` (Ed25519, X25519), `pointycastle` (AES) and `crypto` (SHA); decompression comes from `dart:io`. No type from these libraries leaves the package.

**Other options in the note.** `openpgp` (Go binaries) and `pgp_dart` (Sequoia, 0.0.1) have no settable creation date: ruled out. The Rust library (rPGP or Sequoia) is the target before release.

## Parameters reproduced

| Item | Value | RoboSats source | In the package |
|---|---|---|---|
| Key type | v4, "legacy" EdDSA ed25519 primary (algo 22), ECDH cv25519 subkey (algo 18, parameters `03 01 08 07`) | `frontend/src/pgp/index.ts:23-25`; `tests/robots/3/enc_priv_key` | `RobotPgpKey.generate` |
| User ID | `RoboSats ID <hash_id>` | `pgp/index.ts:26` | `RobotIdentity.pgpUserId` |
| Passphrase | the token | `pgp/index.ts:27` | `generate`, `unlock` |
| Creation date | now minus one day | `pgp/index.ts:29` | exactly 24 h (see "Deviations") |
| Private key protection | usage 254, AES-256 CFB, iterated and salted S2K SHA-256, count 224 (16 MiB), SHA-1 check | `tests/robots/3/enc_priv_key` | `ProtectedSecret.lock` |
| Self-signature | type 0x10, SHA-512, subpackets 2\*, 11 (9 7 8), 16\*, 21 (8 10), 22 (0 2 1), 25, 27\* (03), 30 (01), 33; \* = critical | same | `selfCertification` |
| Subkey binding | type 0x18, **SHA-512**, subpackets 2\*, 16\*, 27\* (0C), 33 | same | `subkeyBinding` |
| Armor | no header, 60-character lines, CRC line, `\n` | `tests/robots/*/enc_priv_key` | `armorEncode` |
| Shape check of the public key | mandatory blank line, base64 lines | `api/utils.py:496-518` | test "passes the shape check of the coordinator" |
| Minimum key age | 12 hours | `api/utils.py:582-594` | key dated 24 h back |
| Cleartext signature | type 0x01, SHA-512, primary key, dated now | `pgp/index.ts:102-119` | `signCleartext` |
| Required header | `-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n` | `api/utils.py:642-644` | `cleartextEncode` |
| Required signer | fingerprint of the primary key | `api/utils.py:641` | signature by the primary key |
| Chat message | encrypted to self then to the peer, signed, signature dated the day before | `pgp/index.ts:39-62` | `encryptChatMessage` |
| Reading the chat | text returned even if the signature is invalid | `pgp/index.ts:70-99` | `decryptChatMessage` |
| Refusal to send one's own token | message blocked | `EncryptedApiChat/index.tsx:210-214` | `PgpPlaintextContainsToken` failure |
| First-contact header | line breaks replaced by `\` | `frontend/src/models/Robot.model.ts:82-83`; `robosats/middleware.py:53-59`, `122-125`; `api/utils.py:525-526` | `firstContactAuthorizationHeader`, `pgpArmorToWire` |

Content of the chat message produced, as seen by GnuPG: two v3 session key packets (ECDH), one v1 encrypted block with integrity protection, AES-256, no compression; inside, a "one-pass" signature, literal data in `u` format and the signature.

### Chat over REST (`/api/chat/`)

- `GET /api/chat/?order_id=<id>&offset=<n>` (`chat/views.py:40-113`): response `{"peer_connected", "peer_pubkey", "messages": [{"index", "time", "message", "nick"}]}`. `message` is the `PGP MESSAGE` block. Order statuses 9, 10, 11 and 16.
- `POST /api/chat/` (`chat/views.py:116-218`, `chat/serializers.py:61-84`): body `{"PGP_message", "order_id", "offset"}`. Statuses 9 and 10. With `offset`, same response as the `GET`; otherwise `{}`.
- In `PGP_message`, each line break becomes a `\` (`EncryptedChat/index.tsx:263`); the app restores them when reading (`EncryptedApiChat/index.tsx:141` and `166`). Functions `pgpArmorToWire` and `pgpArmorFromWire`; the package's readers accept both forms.
- The plaintext never leaves the device. The coordinator only stores the encrypted block (`chat/models.py:87`). The robot reads its own messages back by decrypting them, since each message is also encrypted to it.
- The author of a message is deduced from the returned nickname: its own, hence its own public key, otherwise the peer's (`EncryptedApiChat/index.tsx:156`). This is the `sender` parameter of `decryptChatMessage`.
- The official app polls every 5 seconds (`EncryptedApiChat/index.tsx:53`).

## Interoperability matrix

| Direction | Status | How |
|---|---|---|
| Dart → GnuPG 2.4.4 | **proven** | `tool/pgp_interop.sh`: import of the public key (`imported: 1`), date and user ID read, re-export, import of the private key without the passphrase (`secret keys imported: 1`), `--list-packets` identical to `tests/robots/3/enc_priv_key` apart from key-specific values, signed invoice verified (`VALIDSIG`, EdDSA, SHA-512, primary fingerprint), text extracted by the coordinator's Python code, signature by GnuPG with our key and the token, chat decrypted by the peer and by our key (`DECRYPTION_OKAY`, `GOODMDC`, signature dated the day before). Second review: 1,000 messages out of 1,000 |
| GnuPG 2.4.4 → Dart | **proven** | same script: key re-exported by GnuPG, ed25519/cv25519 key generated by GnuPG, text clear-signed by GnuPG, message compressed, encrypted and signed by GnuPG, long message with partial lengths, private key protected by GnuPG (S2K count 255, SHA-1, AES-128); plus `tests/robots/1/signed_message` of the repository. **Measured after the fix: 400 real messages out of 400** (identical text and valid signature), from 0 to 9,500 characters, 100 per mode (file, standard input, no compression, text mode), 344 of them with partial lengths. Before the fix, the second review counted 541 out of 1,000 |
| Dart → OpenPGP.js 5.11.3 | **proven** | same script, with the calls of `frontend/src/pgp/index.ts`: key unlocked by the token and validated, blocks identical to the byte after a round trip, signed invoice verified, chat decrypted as peer and as sender with a valid signature, text signed by our code with an OpenPGP.js key verified. Security reviews: 1,500 then 1,000 messages, read as recipient and as sender, 0 failures |
| OpenPGP.js 5.11.3 → Dart | **proven** | same script: key generated by OpenPGP.js read and unlocked, two clear-signed texts (one of them with dashes, trailing whitespace and several lines) rendered exactly as OpenPGP.js renders them, signed and unsigned chat decrypted. Security reviews: 1,500 then 1,000 messages, in both roles, 0 failures. Plus the `tests/robots/{1,2,3}` keys of the repository |
| Structure | **identical** | `gpg --list-packets`: our key against `tests/robots/3` and against an OpenPGP.js key; our chat message against an OpenPGP.js message (two v3 session keys, v1 encrypted block, "one-pass" signature, literal `u`, signature with subpackets 2, 16, 33, no compression) |
| GnuPG 2.2 (official coordinator image) | **not run** | no Debian bookworm image locally |
| Real python-gnupg | **not run** | not installed; its command lines are reproduced from memory in the script |
| Real coordinator | **proven for the creation of a robot; not run for signatures and chat** | 2026-11-11, temple on testnet (RoboSats 0.8.6), over the embedded Tor: a first contact carrying a key pair generated by `RobotPgpKey.generate` was accepted, so the public key passed the shape check and the GnuPG import of the coordinator and the private key its import without passphrase; the coordinator returned the public key re-exported by GnuPG, one character shorter, with the fingerprints of the primary key and of the subkey unchanged, and the private key byte for byte. No order was made: `update_invoice`, the chat and the reward withdrawal, so clear-signing and encryption, are still untested against a coordinator. Details: [robot-coordinator.md](robot-coordinator.md) |

The artifacts of the script's last run are in `packages/robosats/test/fixtures/pgp_interop/`, with what GnuPG and OpenPGP.js printed (`transcript.txt`). Generation, signing and, with fixed randomness, encryption are deterministic: on every run, the tests check that the code still writes, byte for byte, the key, the invoice and the message that GnuPG and OpenPGP.js accepted, and that it still reads what they wrote.

## Bounds and rejections

Everything is in `lib/src/pgp/limits.dart`. Beyond them, the failure is `PgpInputTooLarge` or a typed rejection, never an exception.

| Bound | Value | For comparison |
|---|---|---|
| Armored key block | 20,000 characters, 32 packets | a robot key: 1,000 characters, 5 packets |
| Clear-signed text | 20,000 characters, 8 signatures | the coordinator accepts 15,000 characters |
| Armored chat message | 65,536 characters; 30,000-byte text when sending | |
| Session keys per message | 8 | the official app: 2 |
| Signatures per message | 8 | the official app: 1 |
| Decompression | 262,144 bytes, a single layer | the official app does not compress |
| S2K hashing of a private key | 65 MiB, the maximum the format can encode | OpenPGP.js: 16 MiB; GnuPG 2.4.4 on this machine: 65 MiB |

A chat message is only read if it is made of session keys followed by a single v1 encrypted block, nothing else. The block may be split into "partial lengths": GnuPG does so from about 500 bytes, and the first fixed version wrongly rejected these messages (459 real messages out of 1,000). Session key padding is accepted up to 40 bytes in total, as RFC 6637 allows, each byte being checked. Nothing is decompressed or interpreted before the integrity check (SHA-1 of the block). Inside: "one-pass" signatures, a single text, signatures, directly or in a single compressed packet. This is stricter than OpenPGP.js, which tolerates packets around the encrypted block.

A peer key is rejected (`PgpKeyUnsupported`) if its KDF parameters are not SHA-256/384/512 with AES, or if its X25519 point has low order (zero shared secret).

## Date rules

They follow OpenPGP.js 5, with no tolerance, against an injectable clock (`now`):

- a signature dated after the clock is rejected ("Signature creation time is in the future");
- an expired signature is rejected;
- a signature older than the key is rejected ("Key is newer than the signature"), as is a signature made while the key was expired or before its self-signature;
- we do not encrypt to a key dated in the future, expired, or with an expired self-signature (`PgpKeyOutOfDate`).

**Date ordering constraint.** The official app dates its chat signatures one day back and rejects a signature older than its author's key. Our key is dated 24 h before its creation and our signatures 24 h before sending: the order is always respected, and if the clock goes back, the signature is dated like the key, never before it. The official app, for its part, subtracts one calendar day: 23 h or 25 h on the two days when the clocks change. On such a day, it may refuse, for an hour at most, to encrypt to a brand-new key, including one of its own; nothing to fix on our side.

**Property inherent to RoboSats.** A chat signature and a "cleartext" signature are the same object (text signature by the primary key). A signature made for a chat message is therefore valid as a cleartext signature of the same text, and vice versa. Never have a text signed in the chat if it would be an invoice or an address of one's own.

## What the security review asked for, and what was replayed

**The reviewer's denial-of-service inputs**, read by `decryptChatMessage` (compiled executable, on this machine): all rejected with a typed failure.

| Input | Armored size | Before | Now |
|---|---|---|---|
| 3 layers of compression, 4 GiB | 415 characters | process killed (more than 1.5 GiB) | `PgpMessageUndecryptable`, 0.09 ms, 12 MiB |
| 3 layers of compression, 256 MiB | 366 characters | peak of 1,038 MiB | `PgpMessageUndecryptable`, 0.08 ms, 12 MiB |
| 2,000 nested compressed packets | 5,495 characters | | `PgpMessageUndecryptable`, 0.4 ms, 11 MiB |
| 10,000 nested compressed packets | 27,186 characters | | `PgpMessageUndecryptable`, 1.6 ms, 11 MiB |
| 50,000 nested compressed packets | 135,628 characters | 690 MiB | `PgpInputTooLarge`, 0.02 ms, 11 MiB |
| empty packets, 50 to 400 kB | 69,467 to 555,300 characters | up to 26 s | `PgpInputTooLarge`, 0.02 ms, 13 MiB at most |

The memory shown is that of the whole process, including 12 MiB before the call. The two compression bombs are test fixtures of the package (`test/fixtures/pgp_hostile/`); the other inputs are rebuilt by the tests. A bomb placed inside a message correctly encrypted by a peer (16 MiB of zeros) is rejected in the same way: decompression stops at 256 KiB.

**Hostile keys**: each of the reviewer's variants (empty KDF field, truncated, with an unknown hash or cipher, MD5 and 3DES, 200 bytes, zero point) is now rejected on reading with `PgpKeyUnsupported`, along with the seven known low-order X25519 points. SHA-512 with AES-256 and SHA-384 with AES-192 are accepted and tested in a round trip. Changing one byte, at each position, of a public key, a private key, a clear-signed text and a chat message never throws an exception (4 tests).

**Mutants.** 75 alterations of the code of `lib/src/pgp/` and of `robot_pgp_key.dart` (the reviewer's security-related ones, adapted to the new code, plus 36 on the new code: integrity check, key wrap, bounds, dates, KDF, zero shared secret) were applied one by one, with the test suite rerun each time. 73 make at least one test fail. The 2 that pass have no observable effect:

- accepting text after the `-----END …-----` line: no observable effect, since the `END` line then ends up in the body, which is no longer valid base64, and the block is still rejected (confirmed by the second review on 8 inputs);
- no longer checking that a subkey packet is of the right kind: observable effect but harmless. A private block that also contains a public subkey packet is read by the real code, which ignores that packet, and rejected by the mutant.

The second review reran 42 mutants on the new code and found 9 without a test: `D3 14` header of the integrity check, padding bytes, session key checksum, agreement between cipher and key length, decompression cap to the byte (262,144 accepted, 262,145 rejected), extra bytes in the session key packet, minimum lengths of the encrypted block and of the wrapped key, KDF parameters. Each one now has its test (`test/pgp/hostile_message_test.dart`, group "a message written by hand"), built on an ECDH rewritten in the tests from the text of the RFC, hence independent of the code under test.

The 18 survivors reported by the review each have their test, with packets actually re-signed (`test/support/craft.dart`).

**Second review, no new security defect**: about 190 hostile cases and 722 bit flips without any escaped exception; denial-of-service inputs rejected in less than 2 ms; 45 MiB bomb in a valid message rejected in 20 ms.

**Clock out of range.** With a clock, or a `now`, outside 1970–2106, all operations return the `PgpClockOutOfRange` failure instead of throwing an exception; `RobotPgpKey.generate` therefore returns a `Result`.

**Stricter verification**: signature expired, dated in the future, older than the key, without a `Hash:` header: rejected; whitespace added at the end of lines: the returned text is the signed text, without it.

## Deviations

From the preparation note:

- **Subkey binding in SHA-512, not SHA-256.** The note (B1.3) describes test robot 1, from 2023. Robot 3, from February 2025, and a key made by OpenPGP.js 5.11.3 have a SHA-512 binding. The package does the same.
- `dart_pg`, recommended by the note, is removed (see "Library").

From the initial request:

- **Backdating by exactly 24 h**, and not by one calendar day (see "Date rules").
- **Guardrails added**: `signCleartext` refuses a text that the coordinator's splitting would not return intact; `encryptChatMessage` refuses a text containing the token.
- **Accepted limits**: only v4 ed25519 + cv25519 keys are accepted (a peer that provided an RSA key through the API would be unreadable); revocation is not evaluated (a coordinator keeps a robot's first key).

Interface changes due to the fixes:

- `RobotPgpKey.generate(identity)` returns a `Result` (`PgpClockOutOfRange` failure) and no longer accepts a clock or a source of randomness; the test variant is `generateWith`, marked `@visibleForTesting`. Same for `encryptChatMessageWith` and `GarageKey.generateWith`. Weak randomness can no longer be passed in production without an analyzer warning.
- `signCleartext` and `encryptChatMessage` now return any `PgpFailure`; `verifyCleartext` and `decryptChatMessage` accept `now`; three new failures: `PgpInputTooLarge`, `PgpKeyOutOfDate`, `PgpClockOutOfRange`.
- `verifyCleartext` returns the text actually signed (without trailing whitespace) and requires the `Hash:` header.

## Risks

| Risk | Mitigation |
|---|---|
| Hand-written security code (1,891 lines) | provisional, to be replaced by a Rust library before release; cross-checked against GnuPG and OpenPGP.js both ways; independent security review; mutation tests; the custody check does not see it: same scrutiny as for `packages/secrets` |
| `pinenacl` 0.6.0: TweetNaCl port, no known audit | RFC 8032 and RFC 7748 vectors in the tests |
| No Dart code is constant-time | inherent to pure Dart; the encrypted private key is with the coordinator anyway |
| Secrets in memory | **partial** wiping, not to be overestimated. Zeroed: the buffers the package allocates itself (key derived from the token, byte copies of the token, decrypted secrets, session key, ECDH shared secret, plaintext before encryption). Not wiped: the token itself (a Dart string, immutable), the seed and the scalar as long as `UnlockedRobotPgpKey` exists, the internal copies of `pinenacl`, `pointycastle` and `crypto` (expanded keys, digests), the garbage collector's copies, the decrypted text returned to the caller. Nothing is written or logged; `toString()` and failures carry no secret |
| Unlock duration (32 MiB of SHA-256 for a key from the official app, up to 130 MiB for a key protected by GnuPG) | 0.3 s measured on this machine for 32 MiB; phone not measured; to be called off the UI thread, once per batch of messages |
| Malicious peer key supplied by the coordinator | inherent to RoboSats: the coordinator distributes the keys |
| Phone clock off by more than 24 h | the official app's signatures look like they come "from the future" and are marked invalid; the official app behaves the same way |

## Dependencies

`pubspec.lock`: compared with `main`, a single package added, `pinenacl` 0.6.0 (MIT, pure Dart, TweetNaCl port). `dart_pg` 2.0.0, `sign_dart` 1.0.0 and `sha3` 0.2.1, added at the start of the spike, were removed by `fvm flutter pub get`. `make deps` (strict lockfile) passes.

## Still to test

1. **Against a test coordinator**: `update_invoice` with a signed invoice, sending and reading back a chat message, restoring the robot with the token alone. Creating the robot with a Troc key is done (2026-11-11, [robot-coordinator.md](robot-coordinator.md)).
2. GnuPG 2.2.x and the real python-gnupg: rerun `tool/pgp_interop.sh` on Debian bookworm.
3. Key generation and unlock times on a mid-range Android phone.
4. Size limit of `PGP_message`: the model announces 5,000 characters (`chat/models.py:87`), with no check visible in the serializer.
5. The checks of the whole project (`make analyze`, `make unit-test`, `make custody-check`) need the generated code, absent locally: only their equivalents on the package were run.

## Rerunning

Package tests, from the repository root:

```bash
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools \
  bash -c 'make deps && cd packages/robosats && fvm dart test'
```

Cross-check with GnuPG and OpenPGP.js, on a machine that has GnuPG and the `bull-tools` image (temporary keyrings, never the user's own; the OpenPGP.js steps only run if `OPENPGPJS` points to a local copy, nothing is downloaded):

```bash
OPENPGPJS=/path/to/openpgp.min.js packages/robosats/tool/pgp_interop.sh                    # checks
OPENPGPJS=/path/to/openpgp.min.js packages/robosats/tool/pgp_interop.sh --update-fixtures  # checks and replaces test/fixtures/pgp_interop/
```
