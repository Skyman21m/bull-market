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

> These screens are a **mock-up**: they show the target, not the current app. Offers, amounts, nicknames and messages are made up. Only the first screens exist in the app so far: see [Screens in the app](#screens-in-the-app) below.

<table>
  <tr>
    <td align="center"><img src="docs/mockup/en-home.png" width="170" alt="Mock-up: wallet home with a P2P tab in the bottom bar"><br><sub>A P2P tab in the wallet</sub></td>
    <td align="center"><img src="docs/mockup/en-tor.png" width="170" alt="Mock-up: connecting to the Tor network"><br><sub>Connecting to Tor</sub></td>
    <td align="center"><img src="docs/mockup/en-robot.png" width="170" alt="Mock-up: the robot, its avatar and nickname"><br><sub>A robot: a disposable identity</sub></td>
    <td align="center"><img src="docs/mockup/en-order-book.png" width="170" alt="Mock-up: order book with filters and offers"><br><sub>The order book</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/mockup/en-order.png" width="170" alt="Mock-up: details of an order"><br><sub>Order details</sub></td>
    <td align="center"><img src="docs/mockup/en-bond.png" width="170" alt="Mock-up: bond invoice to lock, with QR code"><br><sub>Locking the bond</sub></td>
    <td align="center"><img src="docs/mockup/en-chat.png" width="170" alt="Mock-up: encrypted chat with the seller"><br><sub>Encrypted chat with the seller</sub></td>
    <td align="center"><img src="docs/mockup/en-finished.png" width="170" alt="Mock-up: trade finished, summary and sats received"><br><sub>Trade finished</sub></td>
  </tr>
</table>

A few notes on what the mock-up shows:

- The "Pay with the wallet" button on the bond screen is a goal, not a given. The wallet has no Lightning node and pays through a swap service: whether it can settle a hold invoice, which stays locked for hours, is still to be checked ([#8](https://github.com/Skyman21m/troc/issues/8)). Paid that way, the bond would not stay in the wallet while it is locked, unlike what the RoboSats text under the QR code says ("This is a hold invoice, it will freeze in your wallet"): it would be held by the swap service. The QR code, to be paid with another wallet as in RoboSats, remains the baseline. The groundwork has started in the code: the P2P part can now be lent the balance of the wallet's Instant Payments wallet and a fee quote from the swap service ([#100](https://github.com/Skyman21m/troc/issues/100)), but nothing in the app shows or uses them yet, and nothing pays.
- The robot avatar is provisional ([#22](https://github.com/Skyman21m/troc/issues/22)). In the code, the nickname is already computed as in RoboSats; the ones in the mock-up are made up.
- The labels are those of RoboSats; the French translation is completed where it is missing, and a few texts specific to Troc are added.

<details>
<summary>Captures en français (maquette)</summary>

<br>

*Maquette uniquement : ces écrans montrent la cible, pas l'application actuelle. Les offres, les montants, les pseudos et les messages sont inventés.*

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

## Screens in the app

> These are **real screens**, rendered from the app's own code by a test: the order book screens with books recorded from the RoboSats coordinators on November 10, 2026 (Gumpellite, added to the app's coordinator list after that recording, shows as offline), but for the map, whose orders, places and robots are made up by the test since no recorded order has a location, and the Garage, on testnet, with the public example Garage Key of the RoboSats tests (the backup alert shows a throwaway key drawn by the test, kept hidden); its robot panel, on mainnet, with that key and coordinators played by the test, so nothing was sent anywhere. They are only visible when both superuser mode and developer mode are on. The order book screens but for the map, with the row of coordinators above the offers, and the Garage screens were tried on a phone with debug builds, sending a robot to a coordinator from the Garage once; the question asked for a pasted key and the PIN prompts have not been tried on a phone yet (see the status below).

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/en-tor-wait.png" width="170" alt="App screen: connecting to the Tor network"><br><sub>Connecting to Tor</sub></td>
    <td align="center"><img src="docs/screenshots/en-order-book.png" width="170" alt="App screen: order book filtered on buying with EUR"><br><sub>The order book</sub></td>
    <td align="center"><img src="docs/screenshots/en-depth-chart.png" width="170" alt="App screen: depth chart of the EUR orders on the premium axis, with one order shown under the finger"><br><sub>The depth chart</sub></td>
    <td align="center"><img src="docs/screenshots/en-map.png" width="170" alt="App screen: map of the world with the pins and groups of the orders that have a face to face location, one order shown under the finger"><br><sub>The map</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/en-search-order.png" width="170" alt="App screen: Search order dialog asking for an order URL"><br><sub>Search order</sub></td>
    <td align="center"><img src="docs/screenshots/en-order.png" width="170" alt="App screen: details of an order, with the Take Order button disabled"><br><sub>Order details</sub></td>
    <td align="center"><img src="docs/screenshots/en-reversible-payments.png" width="170" alt="App screen: warning about reversible payment methods"><br><sub>Reversible payments warning</sub></td>
    <td align="center"><img src="docs/screenshots/en-coordinator-details.png" width="170" alt="App screen: details of the coordinator that hosts the order"><br><sub>Coordinator details</sub></td>
  </tr>
</table>

What these screens do today, read-only: wait for Tor inside the tab, load the order book coordinator by coordinator, with a row of the coordinators above it that stays once the offers are shown (each one lit when its book has arrived, dimmed while it is still awaited, and marked offline, with "Retry", once it has not answered after a few attempts the app makes by itself; a tap opens its details), filter it (buy or sell, currency, payment method, host), draw its depth chart (premium or price axis, zoom; a long press shows an order, a tap opens it), show the orders that have a face to face location on a map of the world drawn by the app, with no map tiles and nothing downloaded (drag, pinch and buttons to zoom; nearby orders grouped with their count; a tap opens an order or zooms in on a group), show RoboSats' low-bond and reversible-payment warnings, the details of an order and of the coordinator that hosts it, and open an order of the public book from its URL ("Search order"; an order that is not in the public book needs a robot, which the app cannot use yet). "Take Order" is displayed but disabled. A coordinator's links and contacts are shown, never opened, so nothing leaves Tor. The robot avatars are provisional ([#22](https://github.com/Skyman21m/troc/issues/22)).

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/en-garage-welcome.png" width="170" alt="App screen: Garage welcome, with Start and Recovery"><br><sub>The Garage</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-backup-alert.png" width="170" alt="App screen: step 1 of the Garage, the backup alert with the Garage Key hidden"><br><sub>Back up the Garage Key</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-robot.png" width="170" alt="App screen: step 2 of the Garage, the first robot with its avatar and nickname"><br><sub>The first robot</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-profile.png" width="170" alt="App screen: Garage profile, the robot navigator and the Garage Key hidden"><br><sub>Profile, key hidden</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/en-garage-robot-panel.png" width="170" alt="App screen: Garage profile, the panel Coordinator that knows your robot, with no coordinator yet and the Select Host button"><br><sub>Which coordinator knows the robot</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-robot-history.png" width="170" alt="App screen: Robots from elsewhere, asked once before the first robot of a pasted Garage Key goes to a coordinator, with I understand and Cancel"><br><sub>A pasted key: asked once</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-select-host.png" width="170" alt="App screen: Select Host, the six coordinators of the list, one of them offline"><br><sub>Select Host</sub></td>
    <td align="center"><img src="docs/screenshots/en-garage-send-robot.png" width="170" alt="App screen: confirmation before the robot is sent to Temple of Sats"><br><sub>Confirm before sending</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/en-garage-robot-card.png" width="170" alt="App screen: what TheBigLake says of the robot: its last order, rewards and warnings"><br><sub>What the coordinator says</sub></td>
  </tr>
</table>

The Garage (RoboSats' name for the screen that holds the Garage Key and its robots) works on the device, but for its robot panel, which sends a robot to a coordinator, and the coordinator details its "Select Host" list opens, which read a coordinator's public information as the order page does. With no key stored, it generates a Garage Key or takes a pasted one, shows it for backup with RoboSats' alert, and shows the first robot derived from it; from the welcome screen, "Recovery" stores a pasted key. With a key stored, the user can browse the robots, show the key again behind the wallet's PIN (when one is set), and delete the key. Under each robot, a panel shows the coordinator that knows it, as RoboSats' profile does: a robot goes to a coordinator only when the user picks one with "Select Host" and confirms (RoboSats sends every robot it shows to every coordinator; here a robot lives on one coordinator only), and a robot already sent is read back from its coordinator each time it is shown (its orders, as plain text, and its rewards). Choosing a coordinator there is optional. For a Garage Key that was pasted in, or whose draw the app could not record, "Select Host" first says that its robots may already exist on coordinators, since RoboSats sends each robot it shows to every coordinator, and asks "I understand" once for that key and network; its other robots then go straight to the list, until the key is pasted again. The key is kept, one per network, in the wallet's secure storage on the device (`packages/secrets`, which also holds the seeds), never in a wallet backup: the user backs it up separately. The whole Garage asks for the wallet's screen-capture protection, as the seed screens do (on unless the user turned "Screen Privacy" off in the wallet's settings; on the phone of the third trial below, a screen capture was blocked in the Garage). Each visit starts again at robot 0.

<details>
<summary>Captures en français</summary>

<br>

*Écrans réels, rendus par le code de l'application dans un test : les écrans du carnet d'ordres (lecture seule) avec des carnets enregistrés le 10 novembre 2026 (Gumpellite, ajouté à la liste des coordinateurs de l'application après cet enregistrement, apparaît hors ligne), sauf la carte, dont les ordres, les lieux et les robots sont inventés par le test puisqu'aucun ordre enregistré n'a d'emplacement ; le Garage, sur testnet, avec la clé de garage d'exemple, publique, des tests de RoboSats (l'alerte de sauvegarde montre une clé jetable tirée par le test, masquée) ; son panneau du robot, sur mainnet, avec cette clé et des coordinateurs joués par le test : rien n'a été envoyé. Visibles uniquement en mode super-utilisateur et développeur. Les écrans du carnet, sauf la carte, avec la rangée des coordinateurs au-dessus des offres, et ceux du Garage ont été essayés sur un téléphone avec des versions de débogage, l'envoi d'un robot chez un coordinateur depuis le Garage une fois ; la question posée pour une clé collée et les demandes de PIN ne l'ont pas encore été.*

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-tor-wait.png" width="170" alt="Écran de l'application : connexion au réseau Tor"><br><sub>Connexion à Tor</sub></td>
    <td align="center"><img src="docs/screenshots/fr-order-book.png" width="170" alt="Écran de l'application : carnet d'ordres filtré sur l'achat en EUR"><br><sub>Le carnet d'ordres</sub></td>
    <td align="center"><img src="docs/screenshots/fr-depth-chart.png" width="170" alt="Écran de l'application : graphique de profondeur des ordres en EUR sur l'axe de la prime, un ordre affiché sous le doigt"><br><sub>Le graphique de profondeur</sub></td>
    <td align="center"><img src="docs/screenshots/fr-map.png" width="170" alt="Écran de l'application : carte du monde avec les épingles et les groupes des ordres qui ont un emplacement face à face, un ordre affiché sous le doigt"><br><sub>La carte</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-search-order.png" width="170" alt="Écran de l'application : fenêtre « Rechercher un ordre » qui demande l'URL d'un ordre"><br><sub>Rechercher un ordre</sub></td>
    <td align="center"><img src="docs/screenshots/fr-order.png" width="170" alt="Écran de l'application : fiche d'un ordre, bouton « Prendre l'ordre » inactif"><br><sub>La fiche d'un ordre</sub></td>
    <td align="center"><img src="docs/screenshots/fr-reversible-payments.png" width="170" alt="Écran de l'application : avertissement sur les paiements réversibles"><br><sub>Avertissement « Paiements réversibles »</sub></td>
    <td align="center"><img src="docs/screenshots/fr-coordinator-details.png" width="170" alt="Écran de l'application : fiche du coordinateur qui héberge l'ordre"><br><sub>La fiche du coordinateur</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-garage-welcome.png" width="170" alt="Écran de l'application : accueil du Garage, avec « Commencer » et « Récupération »"><br><sub>Le Garage</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-backup-alert.png" width="170" alt="Écran de l'application : étape 1 du Garage, l'alerte de sauvegarde, clé de garage masquée"><br><sub>Sauvegarder la clé de garage</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-robot.png" width="170" alt="Écran de l'application : étape 2 du Garage, le premier robot avec son avatar et son pseudo"><br><sub>Le premier robot</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-profile.png" width="170" alt="Écran de l'application : profil du Garage, navigation entre robots et clé de garage masquée"><br><sub>Le profil, clé masquée</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-garage-robot-panel.png" width="170" alt="Écran de l'application : profil du Garage, le panneau « Coordinateur qui connaît votre robot », sans coordinateur, avec le bouton « Sélectionner l'hôte »"><br><sub>Le coordinateur du robot</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-robot-history.png" width="170" alt="Écran de l'application : « Robots venus d'ailleurs », demandé une fois avant que le premier robot d'une clé de garage collée aille chez un coordinateur, avec « Je comprends » et « Annuler »"><br><sub>Une clé collée : une seule demande</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-select-host.png" width="170" alt="Écran de l'application : « Sélectionner l'hôte », les six coordinateurs de la liste, dont un hors ligne"><br><sub>Sélectionner l'hôte</sub></td>
    <td align="center"><img src="docs/screenshots/fr-garage-send-robot.png" width="170" alt="Écran de l'application : confirmation avant d'envoyer le robot chez Temple of Sats"><br><sub>Confirmer l'envoi</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-garage-robot-card.png" width="170" alt="Écran de l'application : ce que TheBigLake dit du robot : son dernier ordre, ses compensations et des avertissements"><br><sub>Ce que dit le coordinateur</sub></td>
  </tr>
</table>

</details>

## How a trade works

The planned flow is the RoboSats one; only the first three steps exist in the app so far (a robot can be sent to one coordinator from the Garage), and no order can be taken yet. Example for a buyer who takes an order:

1. **Tor.** The P2P tab connects to the Tor network; the wallet stays usable in the meantime.
2. **Robot.** The app creates a Garage Key, a master key from which it derives as many robots as needed. A robot is a disposable identity: a nickname, an avatar and its own keys.
3. **Order book.** Orders are read from the coordinators of the RoboSats federation, all reached at their `.onion` address.
4. **Bond.** To take an order, the buyer locks a small bond with a hold invoice: the sats are frozen, not spent, and come back to the buyer if they follow the steps and deadlines.
5. **Escrow.** The buyer says where to receive their sats and, in parallel, the seller locks the trade's bitcoin the same way.
6. **Payment.** The two parties talk in an end-to-end encrypted chat (their keys are relayed by the coordinator). The buyer sends the fiat currency by the agreed method, then confirms it.
7. **End.** The seller confirms receipt: the sats are sent to the buyer and the bonds are released. In case of disagreement, a dispute can be opened with the coordinator.

## Project status

Status as of November 13, 2026. The work is split into phases, tracked with [milestones](https://github.com/Skyman21m/troc/milestones) and [issues](https://github.com/Skyman21m/troc/issues).

| Phase | Scope | Status |
|---|---|---|
| 0 | Setup, continuous integration, technical checks (Tor to a coordinator, robot identity, PGP, hold invoices) | Partly done: Tor and robot identity verified; a testnet coordinator accepted a robot and its OpenPGP key pair, while signatures and chat encryption are verified offline only, since they need an order ([#7](https://github.com/Skyman21m/troc/issues/7)); paying hold invoices not tried yet ([#8](https://github.com/Skyman21m/troc/issues/8)); end-of-phase decision still to be made ([#9](https://github.com/Skyman21m/troc/issues/9)) |
| 1 | Read-only foundation: order book, robots, list and detail screens | Done but for the pass over the texts ([#31](https://github.com/Skyman21m/troc/issues/31)) |
| 2 | Taking an order (taker flow) | Started: the protocol calls of a taker, which nothing in the app calls yet ([#84](https://github.com/Skyman21m/troc/issues/84)) |
| 3 | Creating an order (maker flow) | Upcoming |
| 4 | Comfort and robustness: Nostr chat, notifications, disputes | Upcoming |
| 5 | Polish, independent security audit, beta | Upcoming |

What already exists in the code:

- **Robot identity**: Garage Key, tokens, ID, nickname, checked against reference values taken from RoboSats; the Nostr key follows the formula of the current official client ([report](docs/spikes/robot-identity.md)).
- **Robot OpenPGP keys and messages**: robot key, signatures, chat encryption, checked both ways with GnuPG and OpenPGP.js; a testnet coordinator has accepted key pairs made by this code when creating a robot, but no signature or chat message has been tried against one yet ([report](docs/spikes/pgp.md)). This layer is written in Dart and is provisional: a proven Rust library must replace it before any release ([#25](https://github.com/Skyman21m/troc/issues/25)).
- **Reading the coordinators**: info, order book and limits of each coordinator in the federation, with a check of its identity and of everything it returns ([details](packages/robosats/README.md)).
- **The protocol calls of a taker** (phase 2, [#84](https://github.com/Skyman21m/troc/issues/84)): reading an order as a robot sees it, taking it and cancelling it, with everything the coordinator returns checked, and an action never sent twice ([details](packages/robosats/README.md)). Nothing in the app calls them yet, so no order can be taken and no money can move; they have only been run against answers built by the tests, never against a coordinator.
- **A first contact over Tor**: a test reaches the real coordinators through the wallet's embedded Tor, on a PC ([measurements](docs/spikes/tor-robosats.md)).
- **Reading the coordinators over the wallet's Tor**: the `features/p2p` module plugs this reading into the wallet's embedded Tor ([#27](https://github.com/Skyman21m/troc/issues/27)). Its own live test ran once, on a desktop PC behind a VPN, before the review fixes ([report](docs/spikes/tor-transport.md)); the robot test and the phone trials below have since gone through the corrected transport live, without targeting the fixed paths.
- **The order book screens of the P2P tab**: Tor wait, order book, its depth chart and its map, order details, the details of a coordinator and the search of an order by its URL, read-only, behind superuser and developer mode ([#29](https://github.com/Skyman21m/troc/issues/29), [#30](https://github.com/Skyman21m/troc/issues/30)). Tested with recorded order books.
- **A robot on a coordinator**: the code creates a robot on a coordinator and reads it back, over a Tor session of its own, and refuses any answer that is not this device's robot, with the key pair this device sent or one that the robot's own token proves. A test did it six times on one testnet coordinator, from a desktop build, on November 11, 2026 ([#39](https://github.com/Skyman21m/troc/pull/39), [report](docs/spikes/robot-coordinator.md)); taking back a key pair proven by the token was added after those runs ([#67](https://github.com/Skyman21m/troc/pull/67)), and the test has not been run since. The Garage's robot panel uses it ([#28](https://github.com/Skyman21m/troc/issues/28), [#29](https://github.com/Skyman21m/troc/issues/29)); the panel is tested with coordinators played by the tests, and was run once against a real coordinator, from a phone (sixth trial below).
- **The Garage Key kept in the wallet's secure storage**: one per network (mainnet and testnet), random, never derived from the wallet's seed and never part of its backup; the P2P module can generate, import, find, delete it and derive its robots, only in the app in the foreground, and the custody checks limit which files may read it ([#28](https://github.com/Skyman21m/troc/issues/28)).
- **The Garage screens**: generate or paste a Garage Key, back it up, meet the first robot, the profile with the key behind the wallet's PIN (when one is set), robot recovery from a pasted key, deleting the key, and the robot panel, which sends a robot to the coordinator the user picks and confirms, then reads it back, after a one-time acknowledgement for a Garage Key that was pasted in or whose draw could not be recorded ([#29](https://github.com/Skyman21m/troc/issues/29)). The whole Garage asks for the wallet's screen-capture protection, as the seed screens do (on unless the user turned "Screen Privacy" off in the wallet's settings; a screen capture was blocked in the Garage in the third trial below). Tested over an in-memory stand-in for the secure storage, and tried on a phone (below). Before any release, a copied key is to be flagged as sensitive to Android, and a key typed into the app is to be kept away from the system keyboard ([#56](https://github.com/Skyman21m/troc/issues/56)).
- **A first trial on a phone** (November 11, 2026, one Android phone, debug build): the P2P tab appeared, Tor connected in about 30 seconds, the six coordinators of the mainnet list all ended up answering, some later than others, and the order book, its filters (which ones were tried was not recorded), pull to refresh, the order details and the reversible-payment warning worked. This is what the tester saw; nothing was measured. Not checked on the phone: the low-bond warning, the testnet banner, the Tor error and its retry, an offline coordinator, the English texts.
- **A second trial on a phone** (later on November 11, 2026, debug build of `main` at `55ba5139c`): the tester reported that everything tried worked as expected, the coordinator details, the Search entry and the depth chart included; what exactly was tried on each screen was not recorded. That build came before the Garage screens.
- **A third trial on a phone** (November 12, 2026, in the morning, debug build): the Garage screens that need no network: the wizard that creates a key, the recovery screen where one is pasted, the backup step, the robot, the profile and the deletion of the key. What exactly was tried on each step was not recorded, apart from the screen capture, which is blocked in the Garage.
- **A fourth trial on a phone** (later on November 12, 2026, debug build): the coordinators' images and the loading waits.
- **A fifth trial on a phone** (in the evening of November 12, 2026, debug build): the new launcher icon and the Tor wait with its percentage and its phrases; the tester's verdict: "everything looks right". The tester also reported that on a first load after a cold start of Tor, several coordinators showed as offline until "Retry" had been pressed a few times, which [#76](https://github.com/Skyman21m/troc/pull/76) addresses: the app now asks again by itself a coordinator that did not answer, and shows the row of coordinators above the offers.
- **A sixth trial on a phone** (November 13, 2026, debug build of [#75](https://github.com/Skyman21m/troc/pull/75)): from the Garage, a robot of a Garage Key drawn in the app was sent to a coordinator on the wallet's network, and its card came back with "No existing orders found". It is the first run of the robot panel against a real coordinator.
- **A seventh trial on a phone** (November 13, 2026, debug build of [#76](https://github.com/Skyman21m/troc/pull/76)): the row of coordinators works, each coordinator lighting up as its book arrives, and on a start from cold the coordinators came in without "Retry" being pressed, with fewer failures than before. One coordinator stayed offline however often "Retry" was pressed, and it did not synchronise in the official RoboSats client on the same phone either, so the trouble lay with that coordinator, not with the app.
- **Not tried on a phone yet**: the map view of the order book ([#82](https://github.com/Skyman21m/troc/pull/82)), the question asked before the robots of a pasted key go to a coordinator ([#77](https://github.com/Skyman21m/troc/pull/77)), and the PIN prompts (to show the key, before a delete). Sending a robot from the Garage has been tried once, with a key drawn in the app.

Left in phase 1: the pass over the texts ([#31](https://github.com/Skyman21m/troc/issues/31)).

The Garage's flow for pasted keys is being redesigned ([#79](https://github.com/Skyman21m/troc/issues/79)): after the sixth trial, the robots of a pasted key are to be looked up on every coordinator automatically, and a robot is to be bound when an order is made or taken. A design study is open on deriving Garage Keys from the wallet's seed ([#81](https://github.com/Skyman21m/troc/issues/81)). Neither is decided in detail nor written yet.

Next: taking an order (phase 2, [#12](https://github.com/Skyman21m/troc/issues/12)). Its design is written ([design note](docs/design/phase-2-taking-an-order.md)), and its first piece is in the code: a rule that keeps every call that can lock, move or release funds in the trade use cases, and keeps automated tests away from money on real coordinators ([#83](https://github.com/Skyman21m/troc/issues/83)). The protocol calls of a taker (reading an order, taking it, cancelling it) are in the code too ([#84](https://github.com/Skyman21m/troc/issues/84)), but nothing in the app calls them. So are the records that will let a trade survive the app being killed, each with a fresh robot that is never used for a second trade ([#85](https://github.com/Skyman21m/troc/issues/85)). Nothing in the app can take an order or write a trade yet. The first build that can will also offer to pay the bond with this wallet, whose behaviour with such a locked payment is measured in the owner's first trials ([#8](https://github.com/Skyman21m/troc/issues/8), [#9](https://github.com/Skyman21m/troc/issues/9)).

Not done yet: taking or creating an order, the chat, and any operation that involves money: nothing in the P2P tab moves money.

Android first. Nothing is released yet. At this stage, the app still shows Bull's name and logo in places: their removal is tracked in issue [#17](https://github.com/Skyman21m/troc/issues/17).

## How it is built

Troc adds two modules to Bull's code; Troc touches the rest as little as possible, so that it can keep up with updates of the original wallet. Outside them, the main changes to Bull's own code are in `packages/secrets`, which now also keeps the Garage Keys apart from the seeds, under its custody checks ([#45](https://github.com/Skyman21m/troc/pull/45), [#58](https://github.com/Skyman21m/troc/pull/58)), and in the shell that mounts the P2P tab and hands it that storage (`lib/router.dart`, `lib/locator.dart`).

| Module | Role |
|---|---|
| [`packages/robosats`](packages/robosats/README.md) | Part of the RoboSats protocol in pure Dart, with no screen and no network access of its own: robot identity, OpenPGP, reading the coordinators, creating a robot on a coordinator and reading it back, and the calls of a taker on an order (read, take, cancel), which nothing calls yet. It talks to the network through an entry point that the app provides. |
| `features/p2p` | The app side: the transport over the wallet's Tor and its facade ([#27](https://github.com/Skyman21m/troc/issues/27)), the module's own database, which binds each robot to a single coordinator before any request (`p2p.sqlite`, [#28](https://github.com/Skyman21m/troc/issues/28)), the limiter that bounds and spaces the robot requests to each coordinator ([#29](https://github.com/Skyman21m/troc/issues/29)), and the screens of the P2P tab, shown only in superuser and developer mode: the order book and its views (list, depth chart, and a map drawn over a public-domain world map bundled with the app), read-only ([#30](https://github.com/Skyman21m/troc/issues/30)), and the Garage, whose robot panel is the only screen that sends a robot to a coordinator ([#29](https://github.com/Skyman21m/troc/issues/29)), whose Garage Key is kept in the wallet's secure storage (`packages/secrets`). |

Principles:

- **Tor only.** RoboSats coordinators are only reached at their `.onion` address.
- **Identities kept apart from the wallet.** Robot keys are disposable and are never derived from the wallet's recovery phrase. The Garage Key is kept in the wallet's secure storage on the device, never in a wallet backup: neither the recovery phrase nor an Encrypted Vault backup restores it, so it needs its own backup.
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
