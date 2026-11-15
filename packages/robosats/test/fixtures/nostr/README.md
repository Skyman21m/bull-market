# Nostr test vectors

Public test vectors, copied unchanged; no key in them belongs to anyone.

- `nip44.vectors.json`: the official NIP-44 vectors, `nip44.vectors.json` of https://github.com/paulmillr/nip44 (fetched on 2026-11-15). Its SHA-256, `269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040`, is the checksum the NIP-44 text publishes for it (`44.md` of https://github.com/nostr-protocol/nips, section « Tests »). Licence: neither repository has a licence file (GitHub reports none); the README of paulmillr/nip44 lists its TypeScript / JavaScript implementation, beside which the file lives, as public domain. Test data published by the specification for every implementation to check against.
- `bip340-test-vectors.csv`: the official BIP-340 vectors, `bip-0340/test-vectors.csv` of https://github.com/bitcoin/bips (master, fetched on 2026-11-15, SHA-256 `34c9d1d9c3a88d524bc80778540dc43f8306ec249a7485293063c376db851c2d`). Licence of BIP-340: BSD-2-Clause (its header, « License: BSD-2-Clause »). Vectors 15 to 18 sign messages that are not 32 bytes long, which Nostr never signs: the tests check that they are exactly those four and play the other fifteen.
