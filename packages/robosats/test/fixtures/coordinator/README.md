# Coordinator fixtures

## Recorded responses

Raw bodies of the public, unauthenticated endpoints of the RoboSats federation, recorded once on 2026-11-10 between 13:51 and 13:55 UTC, kept byte for byte and untrimmed.
They are public market data: no robot, no account, no money involved.

How: a throwaway `debian:trixie` container with the stock `tor` and `curl` packages, one `GET` per endpoint and coordinator, `curl --socks5-hostname 127.0.0.1:9050` with a browser `User-Agent` (`Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0`) and `Accept: application/json`, a 120 s limit and at most 3 attempts.
Every recorded answer had `Content-Type: application/json`.

| File | Coordinator | Network | Endpoint | HTTP status | Bytes |
|---|---|---|---|---|---|
| `temple-mainnet-info.json` | temple | mainnet | `/api/info/` | 200 | 1085 |
| `temple-mainnet-book.json` | temple | mainnet | `/api/book/` | 200 | 18549 |
| `temple-mainnet-limits.json` | temple | mainnet | `/api/limits/` | 200 | 7482 |
| `lake-mainnet-info.json` | lake | mainnet | `/api/info/` | 200 | 2317 |
| `lake-mainnet-book.json` | lake | mainnet | `/api/book/` | 200 | 27791 |
| `lake-mainnet-limits.json` | lake | mainnet | `/api/limits/` | 200 | 7262 |
| `bazaar-mainnet-info.json` | bazaar | mainnet | `/api/info/` | 200 (second attempt, the first timed out) | 1046 |
| `bazaar-mainnet-book.json` | bazaar | mainnet | `/api/book/` | 200 | 8979 |
| `bazaar-mainnet-limits.json` | bazaar | mainnet | `/api/limits/` | 200 | 7263 |
| `freeport-mainnet-info.json` | freeport | mainnet | `/api/info/` | 200 | 1007 |
| `freeport-mainnet-book.json` | freeport | mainnet | `/api/book/` | 404, `not_found`: no public order | 57 |
| `freeport-mainnet-limits.json` | freeport | mainnet | `/api/limits/` | 200 | 7319 |
| `ammanaya-mainnet-info.json` | ammanaya | mainnet | `/api/info/` | 200 | 1024 |
| `ammanaya-mainnet-book.json` | ammanaya | mainnet | `/api/book/` | 200 | 3392 |
| `ammanaya-mainnet-limits.json` | ammanaya | mainnet | `/api/limits/` | 200 | 7390 |
| `temple-testnet-info.json` | temple | testnet | `/api/info/` | 200 | 986 |
| `temple-testnet-book.json` | temple | testnet | `/api/book/` | 404, `not_found`: no public order | 57 |
| `temple-testnet-limits.json` | temple | testnet | `/api/limits/` | 200 | 7445 |

What they cover: 104 orders (temple 33, lake 49, bazaar 16, ammanaya 6), none priced in sats; payment methods with non-ASCII text in the lake book (`Depósito`, `lotérica`, `Itaú`); one order with a location in the temple book (order 99620, at 0.000000, 0.000000); dates in UTC and, in the ammanaya book, with a `+01:00` offset; a notice with HTML and line breaks (lake) and a severity spelled `Info` (temple mainnet); an older testnet coordinator (0.8.6) without `devfund`, `blossom_enabled` and `federation_hash`.
Everything else hostile or rare is built by the tests.

The `/api/book/` requests had no query parameter, as the official client sends them: every currency and both order types.
lake on testnet did not answer: 3 attempts per endpoint, each a SOCKS failure (`curl` exit code 97), between 13:54:22 and 13:55:51 UTC.

## Sources

`sources/` holds verbatim copies of the RoboSats files the constants of `lib/src/coordinator/` are generated from, at commit ff1998caed30888b2fb60e15022c29063a60f1ba, written by `tool/generate_coordinator_data.dart`: `federation.json`, `currencies.json` and `MethodList.ts`.
`test/coordinator/embedded_data_test.dart` checks that the constants equal them.
