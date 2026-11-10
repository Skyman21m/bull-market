# Troc

> **Prototype under development. Do not use with real funds.**
> Troc is not affiliated with Bull Bitcoin / Satoshi Portal or with RoboSats. "Troc" is a provisional name.

Troc is a fork of the [Bull Bitcoin Mobile](https://github.com/SatoshiPortal/bullbitcoin-mobile) wallet (Flutter) that aims to embed a [RoboSats](https://github.com/RoboSats/robosats) client in it: peer-to-peer bitcoin exchange, with no account, over Tor, straight from a self-custodial wallet.

## The idea

RoboSats lets you buy or sell bitcoin for fiat currency directly between two people: no account, no ID, a disposable identity (a "robot") for each trade, and communication with the coordinator goes over Tor. The other party still sees whatever the chosen payment method reveals. The trade's bitcoin and both parties' bonds are locked by Lightning hold invoices while the payment takes place.

Today, this usually takes two tools: RoboSats on one side (its website in Tor Browser, or its app), a Lightning wallet on the other, and invoices to pass from one to the other.

Troc wants to bring both together in a single app:

- a **P2P** tab in the wallet, next to the existing tabs;
- the **same flow as RoboSats**, step by step and with the same labels, styled like the rest of the wallet;
- the sats bought are **received in the wallet**, which prepares the receiving invoice itself (through its swap service: to be checked with RoboSats);
- the connection to the RoboSats coordinators goes through the **Tor already embedded** in the wallet.

These are goals: the "Project status" section says what actually exists.

## Preview (mock-up)

> These screens are a **mock-up**: they show the target, not the current app. Offers, amounts, nicknames and messages are made up. No P2P screen is in the app yet.

<table>
  <tr>
    <td align="center"><img src="docs/mockup/en-home.png" width="170" alt="Mock-up: wallet home with a P2P tab in the bottom bar"><br><sub>A P2P tab in the wallet</sub></td>
    <td align="center"><img src="docs/mockup/en-tor.png" width="170" alt="Mock-up: connecting to the Tor network"><br><sub>Connecting to Tor</sub></td>
    <td align="center"><img src="docs/mockup/en-robot.png" width="170" alt="Mock-up: the robot, its avatar and nickname"><br><sub>A robot: a disposable identity</sub></td>
    <td align="center"><img src="docs/mockup/en-order-book.png" width="170" alt="Mock-up: order book with filters and offers"><br><sub>The order book</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/mockup/en-order.png" width="170" alt="Mock-up: details of an offer"><br><sub>An offer's details</sub></td>
    <td align="center"><img src="docs/mockup/en-bond.png" width="170" alt="Mock-up: bond invoice to lock, with QR code"><br><sub>Locking the bond</sub></td>
    <td align="center"><img src="docs/mockup/en-chat.png" width="170" alt="Mock-up: encrypted chat with the seller"><br><sub>Encrypted chat with the seller</sub></td>
    <td align="center"><img src="docs/mockup/en-finished.png" width="170" alt="Mock-up: trade finished, summary and sats received"><br><sub>Trade finished</sub></td>
  </tr>
</table>

A few notes on what the mock-up shows:

- The "Pay with the wallet" button on the bond screen is a goal, not a given. The wallet has no Lightning node and pays through a swap service: whether it can settle a hold invoice, which stays locked for hours, is still to be checked ([#8](https://github.com/Skyman21m/troc/issues/8)). Paid that way, the bond would not stay in the wallet while it is locked, unlike what the RoboSats text under the QR code says ("This is a hold invoice, it will freeze in your wallet"): it would be held by the swap service. The QR code, to be paid with another wallet as in RoboSats, remains the baseline.
- The robot avatar is provisional ([#22](https://github.com/Skyman21m/troc/issues/22)). In the code, the nickname is already computed as in RoboSats; the ones in the mock-up are made up.
- The labels are those of RoboSats; the French translation is completed where it is missing, and a few texts specific to Troc are added.

<details>
<summary>Captures en français (maquette)</summary>

<br>

<table>
  <tr>
    <td align="center"><img src="docs/mockup/fr-home.png" width="170" alt="Maquette : accueil du portefeuille avec un onglet P2P dans la barre du bas"><br><sub>Un onglet P2P dans le portefeuille</sub></td>
    <td align="center"><img src="docs/mockup/fr-tor.png" width="170" alt="Maquette : connexion au réseau Tor"><br><sub>Connexion à Tor</sub></td>
    <td align="center"><img src="docs/mockup/fr-robot.png" width="170" alt="Maquette : présentation du robot, son avatar et son pseudo"><br><sub>Un robot : une identité jetable</sub></td>
    <td align="center"><img src="docs/mockup/fr-order-book.png" width="170" alt="Maquette : carnet d'ordres avec filtres et liste des offres"><br><sub>Le carnet d'ordres</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/mockup/fr-order.png" width="170" alt="Maquette : fiche détaillée d'une offre"><br><sub>La fiche d'une offre</sub></td>
    <td align="center"><img src="docs/mockup/fr-bond.png" width="170" alt="Maquette : facture de caution à bloquer, avec QR code"><br><sub>Bloquer la caution</sub></td>
    <td align="center"><img src="docs/mockup/fr-chat.png" width="170" alt="Maquette : chat chiffré avec le vendeur"><br><sub>Le chat chiffré avec le vendeur</sub></td>
    <td align="center"><img src="docs/mockup/fr-finished.png" width="170" alt="Maquette : échange terminé, résumé et sats reçus"><br><sub>Échange terminé</sub></td>
  </tr>
</table>

</details>

## How a trade works

The planned flow is the RoboSats one; none of this is usable in the app yet. Example for a buyer who takes an order:

1. **Tor.** The P2P tab connects to the Tor network; the wallet stays usable in the meantime.
2. **Robot.** The app creates a Garage Key, a master key from which it derives as many robots as needed. A robot is a disposable identity: a nickname, an avatar and its own keys.
3. **Order book.** Orders are read from the coordinators of the RoboSats federation, all reached at their `.onion` address.
4. **Bond.** To take an order, the buyer locks a small bond with a hold invoice: the sats are frozen, not spent, and come back to the buyer if they follow the steps and deadlines.
5. **Escrow.** The buyer says where to receive their sats and, in parallel, the seller locks the trade's bitcoin the same way.
6. **Payment.** The two parties talk in an end-to-end encrypted chat (their keys are relayed by the coordinator). The buyer sends the fiat currency by the agreed method, then confirms it.
7. **End.** The seller confirms receipt: the sats are sent to the buyer and the bonds are released. In case of disagreement, a dispute can be opened with the coordinator.

## Project status

Status as of November 10, 2026. The work is split into phases, tracked with [milestones](https://github.com/Skyman21m/troc/milestones) and [issues](https://github.com/Skyman21m/troc/issues).

| Phase | Scope | Status |
|---|---|---|
| 0 | Setup, continuous integration, technical checks (Tor to a coordinator, robot identity, PGP, hold invoices) | Partly done: Tor and robot identity verified; PGP verified offline, not yet against a coordinator ([#7](https://github.com/Skyman21m/troc/issues/7)); paying hold invoices not tried yet ([#8](https://github.com/Skyman21m/troc/issues/8)); end-of-phase decision still to be made ([#9](https://github.com/Skyman21m/troc/issues/9)) |
| 1 | Read-only foundation: order book, robots, list and detail screens | In progress |
| 2 | Taking an order (taker flow) | Upcoming |
| 3 | Creating an order (maker flow) | Upcoming |
| 4 | Comfort and robustness: Nostr chat, notifications, disputes | Upcoming |
| 5 | Polish, independent security audit, beta | Upcoming |

What already exists in the code, with no screen yet:

- **Robot identity**: Garage Key, tokens, ID, nickname, checked against reference values taken from RoboSats; the Nostr key is computed, but its formula is still to be confirmed against a coordinator ([#28](https://github.com/Skyman21m/troc/issues/28)) ([report](docs/spikes/robot-identity.md)).
- **Robot OpenPGP keys and messages**: robot key, signatures, chat encryption, checked both ways with GnuPG and OpenPGP.js, not yet tried against a coordinator ([report](docs/spikes/pgp.md)). This layer is written in Dart and is provisional: a proven Rust library must replace it before any release ([#25](https://github.com/Skyman21m/troc/issues/25)).
- **Reading the coordinators**: info, order book and limits of each coordinator in the federation, with a check of its identity and of everything it returns ([details](packages/robosats/README.md)).
- **A first contact over Tor**: a test reaches the real coordinators through the wallet's embedded Tor, on a PC for now, not yet on a phone ([measurements](docs/spikes/tor-robosats.md)).

In progress: wiring this reading to the wallet's Tor ([#27](https://github.com/Skyman21m/troc/issues/27)), then the first screens ([#29](https://github.com/Skyman21m/troc/issues/29), [#30](https://github.com/Skyman21m/troc/issues/30)).

Not done yet: any P2P screen, creating a robot with a coordinator, and any operation that involves money.

Android first. Nothing is released yet. At this stage, the app still shows Bull's name and logo in places: their removal is tracked in issues [#4](https://github.com/Skyman21m/troc/issues/4) and [#17](https://github.com/Skyman21m/troc/issues/17).

## How it is built

Troc adds one module to Bull's code, and a second one is being prepared; Troc touches the rest as little as possible, so that it can keep up with updates of the original wallet.

| Module | Role |
|---|---|
| [`packages/robosats`](packages/robosats/README.md) | Part of the RoboSats protocol in pure Dart, with no screen and no network access of its own: robot identity, OpenPGP, reading the coordinators. It talks to the network through an entry point that the app provides. |
| `features/p2p` | The app side: the transport over the wallet's Tor, then the screens of the P2P tab. Being prepared ([#27](https://github.com/Skyman21m/troc/issues/27)), not yet on `main`. |

Principles:

- **Tor only.** RoboSats coordinators are only reached at their `.onion` address.
- **Identities kept apart from the wallet.** Robot keys are disposable and are never derived from the wallet's recovery phrase. That phrase therefore does not restore them: the Garage Key needs its own backup.
- **Received data is treated as untrusted.** Coordinator responses and the other party's messages are bounded in size and checked before use. As in RoboSats, the coordinator must still be trusted for the escrow, disputes and relaying the other party's key.

The code has not been audited yet. An independent security audit is planned before any beta (phase 5).

The fork's own rules are in the "Troc (fork)" section of [AGENTS.md](AGENTS.md).

## The wallet

All the wallet features (Bitcoin, Liquid, Lightning through swaps, backups, hardware wallets, Payjoin, Tor) come from Bull Bitcoin Mobile and are described in the [original README](https://github.com/SatoshiPortal/bullbitcoin-mobile#readme). See also [FEATURES.md](FEATURES.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Building

The build toolchain is Bull's, unchanged: see [AGENTS.md](AGENTS.md) for the development commands (`make setup`, `make checks`) and [reproducibility/](reproducibility/README.md) for the reproducible build in a container. `make android debug` (a target of the [makefile](makefile)) produces a debug APK; it uses podman by default, or Docker with `CONTAINER=docker`.

Every pull request that touches code produces a debug APK, downloadable for 30 days from the [Actions](https://github.com/Skyman21m/troc/actions/workflows/build-android.yml) tab (GitHub account required). Its identifier has the `.debug` suffix: it installs alongside the official Bull app.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security vulnerabilities are reported privately: see [SECURITY.md](SECURITY.md).

## Branches

- `main`: Troc's branch, always buildable, changed only through pull requests.
- `develop`: mirror of the `develop` branch of Bull Bitcoin Mobile, never changed here.

## License

AGPL-3.0 for Troc ([LICENSE](LICENSE)). The original Bull Bitcoin Mobile code is under MIT, with its notice kept in [LICENSE-BULL](LICENSE-BULL). Details in [NOTICE.md](NOTICE.md).
