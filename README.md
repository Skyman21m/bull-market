# Bull Market

> **Prototype under development. Do not use with real funds.**
> Bull Market is not affiliated with Bull Bitcoin / Satoshi Portal or with RoboSats.

> The app was called "Troc" until November 13, 2026, when it was renamed Bull Market ([#105](https://github.com/Skyman21m/bull-market/issues/105)); the repository was renamed the same day, and some documents and internal names still carry the old name. With that change ([#107](https://github.com/Skyman21m/bull-market/pull/107)), the Android application id went from `io.github.skyman21m.troc` to `io.github.skyman21m.bullmarket`, so a newer build installs next to an earlier one instead of replacing it, and starts empty. To keep a wallet, restore it from its recovery phrase. The Garage Key is not part of that backup: copy it from the earlier build's Garage before uninstalling that build.

Bull Market is a fork of the [Bull Bitcoin Mobile](https://github.com/SatoshiPortal/bullbitcoin-mobile) wallet (Flutter) that aims to embed a [RoboSats](https://github.com/RoboSats/robosats) client in it: peer-to-peer bitcoin exchange, with no account, over Tor, straight from a self-custodial wallet.

## The idea

RoboSats lets you buy or sell bitcoin for fiat currency directly between two people: no account, no ID, a disposable identity (a "robot") for each trade, and communication with the coordinator goes over Tor. The other party still sees whatever the chosen payment method reveals. The trade's bitcoin and both parties' bonds are locked by Lightning hold invoices while the payment takes place.

Today, this usually takes two tools: RoboSats on one side (its website in Tor Browser, or its app), a Lightning wallet on the other, and invoices to pass from one to the other.

Bull Market wants to bring both together in a single app:

- a **P2P** tab in the wallet, next to the existing tabs;
- the **same flow as RoboSats**, step by step and with the same labels, styled like the rest of the wallet;
- the sats bought are **received in the wallet**, which prepares the receiving invoice itself (through its swap service: to be checked with RoboSats);
- the connection to the RoboSats coordinators goes through the **Tor already embedded** in the wallet.

These are goals: the "Project status" section says what actually exists.

## Preview (mock-up)

> These screens are a **mock-up**: they show the target, not the current app. Offers, amounts, nicknames and messages are made up. The app has since grown past its first screens: [Project status](#project-status) says what it does today, and [Screens in the app](#screens-in-the-app) shows real ones.

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

- The "Pay with the wallet" button of the mock-up exists in the app since [#100](https://github.com/Skyman21m/bull-market/issues/100), for a taker's bond, a maker's bond and a seller's collateral. The wallet has no Lightning node and pays through a swap service. In the tester's trials on mainnet (see the status below), bonds and a seller's collateral were paid that way; what is not measured is how long the swap service takes to give back a payment whose trade is cancelled, which can be hours ([#8](https://github.com/Skyman21m/bull-market/issues/8) stays open). Paid that way, the bond does not stay in the wallet while it is locked, unlike what the RoboSats text under the QR code says ("This is a hold invoice, it will freeze in your wallet"): it is held by the swap service, and the confirmation says so. The QR code, to be paid with another wallet as in RoboSats, remains.
- The robot avatar is provisional ([#22](https://github.com/Skyman21m/bull-market/issues/22)). In the code, the nickname is already computed as in RoboSats; the ones in the mock-up are made up.
- The labels are those of RoboSats; the French translation is completed where it is missing, and a few texts specific to Bull Market are added.

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

> These are **real screens**, rendered from the app's own code by a test: the order book screens with books recorded from the RoboSats coordinators on November 10, 2026 (Gumpellite, added to the app's coordinator list after that recording, shows as offline), but for the map, whose orders, places and robots are made up by the test since no recorded order has a location, and the Garage, on testnet, with the public example Garage Key of the RoboSats tests (the backup alert shows a throwaway key drawn by the test, kept hidden); its robot panel, on mainnet, with that key and coordinators played by the test, so nothing was sent anywhere. The trade screens, on mainnet, with a Garage Key drawn by the test and Temple of Sats played by the test (its invoices made by the test), so no order was taken and no money moved. They are only visible when both superuser mode and developer mode are on. The order book screens but for the map, with the row of coordinators above the offers, and the Garage screens were tried on a phone with debug builds, sending a robot to a coordinator from the Garage once; the question asked for a pasted key and the PIN prompts have not been tried on a phone yet (see the status below).

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/en-tor-wait.png" width="170" alt="App screen: connecting to the Tor network"><br><sub>Connecting to Tor</sub></td>
    <td align="center"><img src="docs/screenshots/en-order-book.png" width="170" alt="App screen: order book filtered on buying with EUR"><br><sub>The order book</sub></td>
    <td align="center"><img src="docs/screenshots/en-depth-chart.png" width="170" alt="App screen: depth chart of the EUR orders on the premium axis, with one order shown under the finger"><br><sub>The depth chart</sub></td>
    <td align="center"><img src="docs/screenshots/en-map.png" width="170" alt="App screen: map of the world with the pins and groups of the orders that have a face to face location, one order shown under the finger"><br><sub>The map</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/en-search-order.png" width="170" alt="App screen: Search order dialog asking for an order URL"><br><sub>Search order</sub></td>
    <td align="center"><img src="docs/screenshots/en-order.png" width="170" alt="App screen: details of a range order, with the amount field of Take Order"><br><sub>Order details</sub></td>
    <td align="center"><img src="docs/screenshots/en-reversible-payments.png" width="170" alt="App screen: warning about reversible payment methods"><br><sub>Reversible payments warning</sub></td>
    <td align="center"><img src="docs/screenshots/en-coordinator-details.png" width="170" alt="App screen: details of the coordinator that hosts the order"><br><sub>Coordinator details</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/en-trade-bond.png" width="170" alt="App screen: the trade after a take, Lock 3,207 Sats to TAKE order, with the QR code of the bond invoice under Pay with another wallet"><br><sub>The bond to lock</sub></td>
    <td align="center"><img src="docs/screenshots/en-trade-bond-locked.png" width="170" alt="App screen: the trade once the bond is locked, Submit payout info, with the Lightning and Onchain tabs of the payout form"><br><sub>The bond locked</sub></td>
    <td align="center"><img src="docs/screenshots/en-pay-bond.png" width="170" alt="App screen: the confirmation of Pay with this wallet, with the swap fees, the network fee, the total, what stays in Instant payments, the hold invoice sentence of RoboSats, Go back and Pay"><br><sub>Paying the bond from this wallet</sub></td>
  </tr>
</table>

What these screens do today without a robot: wait for Tor inside the tab, load the order book coordinator by coordinator, with a row of the coordinators above it that stays once the offers are shown (each one lit when its book has arrived, dimmed while it is still awaited, and marked offline, with "Retry", once it has not answered after a few attempts the app makes by itself; a tap opens its details), filter it (buy or sell, then one or several currencies, payment methods and hosts, each choice named while nothing is chosen: "Any currency"), draw its depth chart (premium or price axis, zoom; a long press shows an order, a tap opens it), show the orders that have a face to face location on a map of the world drawn by the app, with no map tiles and nothing downloaded (drag, pinch and buttons to zoom; nearby orders grouped with their count; a tap opens an order or zooms in on a group), show RoboSats' low-bond and reversible-payment warnings, the details of an order and of the coordinator that hosts it, and open an order of the public book from its URL ("Search order", which waits for the book of the order's coordinator when it has not arrived yet; for an order that is not in the public book, "Coordinator offline" when that book could not be had, RoboSats' "You do not have a Garage Key" when no Garage Key is stored, and its "This order is not available" otherwise, since the app cannot read such an order with a robot yet). "Take Order" now takes a sell order (see the bullet "Taking an order as buyer" below). A coordinator's links and contacts are shown, never opened, so nothing leaves Tor. The robot avatars are provisional ([#22](https://github.com/Skyman21m/bull-market/issues/22)).

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

*Écrans réels, rendus par le code de l'application dans un test : les écrans du carnet d'ordres (lecture seule) avec des carnets enregistrés le 10 novembre 2026 (Gumpellite, ajouté à la liste des coordinateurs de l'application après cet enregistrement, apparaît hors ligne), sauf la carte, dont les ordres, les lieux et les robots sont inventés par le test puisqu'aucun ordre enregistré n'a d'emplacement ; le Garage, sur testnet, avec la clé de garage d'exemple, publique, des tests de RoboSats (l'alerte de sauvegarde montre une clé jetable tirée par le test, masquée) ; son panneau du robot, sur mainnet, avec cette clé et des coordinateurs joués par le test : rien n'a été envoyé. Les écrans de l'échange, sur mainnet, avec une clé de garage tirée par le test et Temple of Sats joué par le test (ses factures faites par le test) : aucun ordre n'a été pris, aucun argent n'a bougé. Visibles uniquement en mode super-utilisateur et développeur. Les écrans du carnet, sauf la carte, avec la rangée des coordinateurs au-dessus des offres, et ceux du Garage ont été essayés sur un téléphone avec des versions de débogage, l'envoi d'un robot chez un coordinateur depuis le Garage une fois ; la question posée pour une clé collée et les demandes de PIN ne l'ont pas encore été.*

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-tor-wait.png" width="170" alt="Écran de l'application : connexion au réseau Tor"><br><sub>Connexion à Tor</sub></td>
    <td align="center"><img src="docs/screenshots/fr-order-book.png" width="170" alt="Écran de l'application : carnet d'ordres filtré sur l'achat en EUR"><br><sub>Le carnet d'ordres</sub></td>
    <td align="center"><img src="docs/screenshots/fr-depth-chart.png" width="170" alt="Écran de l'application : graphique de profondeur des ordres en EUR sur l'axe de la prime, un ordre affiché sous le doigt"><br><sub>Le graphique de profondeur</sub></td>
    <td align="center"><img src="docs/screenshots/fr-map.png" width="170" alt="Écran de l'application : carte du monde avec les épingles et les groupes des ordres qui ont un emplacement face à face, un ordre affiché sous le doigt"><br><sub>La carte</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-search-order.png" width="170" alt="Écran de l'application : fenêtre « Rechercher un ordre » qui demande l'URL d'un ordre"><br><sub>Rechercher un ordre</sub></td>
    <td align="center"><img src="docs/screenshots/fr-order.png" width="170" alt="Écran de l'application : fiche d'un ordre à fourchette, avec le champ du montant de « Prendre l'ordre »"><br><sub>La fiche d'un ordre</sub></td>
    <td align="center"><img src="docs/screenshots/fr-reversible-payments.png" width="170" alt="Écran de l'application : avertissement sur les paiements réversibles"><br><sub>Avertissement « Paiements réversibles »</sub></td>
    <td align="center"><img src="docs/screenshots/fr-coordinator-details.png" width="170" alt="Écran de l'application : fiche du coordinateur qui héberge l'ordre"><br><sub>La fiche du coordinateur</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/fr-trade-bond.png" width="170" alt="Écran de l'application : l'échange après la prise de l'ordre, « Bloquez 3 207 sats pour PRENDRE l'ordre », le QR code de la facture de caution sous « Payer avec un autre portefeuille »"><br><sub>La caution à bloquer</sub></td>
    <td align="center"><img src="docs/screenshots/fr-trade-bond-locked.png" width="170" alt="Écran de l'application : l'échange une fois la caution bloquée, « Indiquez où recevoir les sats », avec les onglets Lightning et Onchain du formulaire de réception"><br><sub>La caution bloquée</sub></td>
    <td align="center"><img src="docs/screenshots/fr-pay-bond.png" width="170" alt="Écran de l'application : la confirmation de « Payer avec ce portefeuille », avec les frais d'échange, les frais de réseau, le total, ce qui reste dans Paiements instantanés, la phrase de RoboSats sur la facture en attente, « Retour » et « Payer »"><br><sub>Payer la caution avec ce portefeuille</sub></td>
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

The flow is the RoboSats one, and the app now runs it to its end, for the one who takes an order and for the one who makes it, buying or selling (see the status below for what is tried and what is not). Example for a buyer who takes an order:

1. **Tor.** The P2P tab connects to the Tor network; the wallet stays usable in the meantime.
2. **Robot.** The app creates a Garage Key, a master key from which it derives as many robots as needed. A robot is a disposable identity: a nickname, an avatar and its own keys.
3. **Order book.** Orders are read from the coordinators of the RoboSats federation, all reached at their `.onion` address.
4. **Bond.** To take an order, the buyer locks a small bond with a hold invoice: the sats are frozen, not spent, and come back to the buyer if they follow the steps and deadlines.
5. **Escrow.** The buyer says where to receive their sats and, in parallel, the seller locks the trade's bitcoin the same way.
6. **Payment.** The two parties talk in an end-to-end encrypted chat (their keys are relayed by the coordinator). The buyer sends the fiat currency by the agreed method, then confirms it.
7. **End.** The seller confirms receipt: the sats are sent to the buyer and the bonds are released. In case of disagreement, a dispute can be opened with the coordinator.

## Project status

Status as of November 22, 2026. The work is split into phases, tracked with [milestones](https://github.com/Skyman21m/bull-market/milestones) and [issues](https://github.com/Skyman21m/bull-market/issues).

| Phase | Scope | Status |
|---|---|---|
| 0 | Setup, continuous integration, technical checks (Tor to a coordinator, robot identity, PGP, hold invoices) | Partly done: Tor and robot identity verified; a testnet coordinator accepted a robot and its OpenPGP key pair, while signatures and chat encryption are verified offline only, since they need an order ([#7](https://github.com/Skyman21m/bull-market/issues/7)); paying hold invoices through the swap service done in the tester's real trades, its refund delays not measured ([#8](https://github.com/Skyman21m/bull-market/issues/8)); end-of-phase decision still to be made ([#9](https://github.com/Skyman21m/bull-market/issues/9)) |
| 1 | Read-only foundation: order book, robots, list and detail screens | Done but for the pass over the texts ([#31](https://github.com/Skyman21m/bull-market/issues/31)) |
| 2 | Taking an order (taker flow) | In the code, and used in the tester's real trades on a phone (which steps each trial covered was not recorded): an order taken as buyer or as seller, the bond and the collateral paid from this wallet or from another, the payout invoice or address made by this wallet, the encrypted chat (through the coordinator and, as the reference, over Nostr), the cancel and the collaborative cancel, opening a dispute, the rating and the trade summary. Left: an order protected by a password, taken by its URL, is in the code and not tried yet ([#248](https://github.com/Skyman21m/bull-market/pull/248)); the follow-ups of the reviews ([#12](https://github.com/Skyman21m/bull-market/issues/12)) |
| 3 | Creating an order (maker flow) | In the code, and used in the tester's real trades on a phone (which options each trial covered was not recorded): a buy or a sell order, a fixed amount or a range, the reference's advanced options, a password, a face-to-face location, pause, renewal, the book's matching orders, and the maker's bond and a seller's collateral paid from this wallet after a comparison with the wallet's own price. Left: leaner confirmation screens ([#250](https://github.com/Skyman21m/bull-market/issues/250)), the detailed map ([#246](https://github.com/Skyman21m/bull-market/issues/246)), the same price comparison for an order taken ([#249](https://github.com/Skyman21m/bull-market/issues/249)), a fresh robot after each trade ([#251](https://github.com/Skyman21m/bull-market/issues/251)), a history of the orders ([#253](https://github.com/Skyman21m/bull-market/issues/253)) |
| 4 | Comfort and robustness: Nostr chat, notifications, disputes | Upcoming, but for the chat messages, which already go to the Nostr relays too ([#158](https://github.com/Skyman21m/bull-market/pull/158)). Notifications, a dispute's statement, the claims of a dispute won and of a robot's compensations ([#252](https://github.com/Skyman21m/bull-market/issues/252)) are not written |
| 5 | Polish, independent security audit, beta | Upcoming |

What already exists in the code:

- **Robot identity**: Garage Key, tokens, ID, nickname, checked against reference values taken from RoboSats; the Nostr key follows the formula of the current official client ([report](docs/spikes/robot-identity.md)).
- **Robot OpenPGP keys and messages**: robot key, signatures, chat encryption, checked both ways with GnuPG and OpenPGP.js; a testnet coordinator has accepted key pairs made by this code when creating a robot, but no signature or chat message has been tried against one yet ([report](docs/spikes/pgp.md)). This layer is written in Dart and is provisional: a proven Rust library must replace it before any release ([#25](https://github.com/Skyman21m/bull-market/issues/25)).
- **Reading the coordinators**: info, order book and limits of each coordinator in the federation, with a check of its identity and of everything it returns ([details](packages/robosats/README.md)).
- **The protocol calls of a taker** (phase 2, [#84](https://github.com/Skyman21m/bull-market/issues/84)): reading an order as a robot sees it, taking it and cancelling it, with everything the coordinator returns checked, and an action never sent twice ([details](packages/robosats/README.md)). Since [#88](https://github.com/Skyman21m/bull-market/issues/88), the take, the reads of the trade and the cancel are called from the trade screen; they have only been run against answers built by the tests, never against a coordinator.
- **A first contact over Tor**: a test reaches the real coordinators through the wallet's embedded Tor, on a PC ([measurements](docs/spikes/tor-robosats.md)).
- **Reading the coordinators over the wallet's Tor**: the `features/p2p` module plugs this reading into the wallet's embedded Tor ([#27](https://github.com/Skyman21m/bull-market/issues/27)). Its own live test ran once, on a desktop PC behind a VPN, before the review fixes ([report](docs/spikes/tor-transport.md)); the robot test and the phone trials below have since gone through the corrected transport live, without targeting the fixed paths.
- **The order book screens of the P2P tab**: Tor wait, order book, its depth chart and its map, order details, the details of a coordinator and the search of an order by its URL, read-only, behind superuser and developer mode ([#29](https://github.com/Skyman21m/bull-market/issues/29), [#30](https://github.com/Skyman21m/bull-market/issues/30)). Tested with recorded order books.
- **A robot on a coordinator**: the code creates a robot on a coordinator and reads it back, over a Tor session of its own, and refuses any answer that is not this device's robot, with the key pair this device sent or one that the robot's own token proves. A test did it six times on one testnet coordinator, from a desktop build, on November 11, 2026 ([#39](https://github.com/Skyman21m/bull-market/pull/39), [report](docs/spikes/robot-coordinator.md)); taking back a key pair proven by the token was added after those runs ([#67](https://github.com/Skyman21m/bull-market/pull/67)), and the test has not been run since. The Garage's robot panel uses it ([#28](https://github.com/Skyman21m/bull-market/issues/28), [#29](https://github.com/Skyman21m/bull-market/issues/29)); the panel is tested with coordinators played by the tests, and was run once against a real coordinator, from a phone (sixth trial below).
- **The Garage Key kept in the wallet's secure storage**: one per network (mainnet and testnet), random, never derived from the wallet's seed and never part of its backup; the P2P module can generate, import, find, delete it and derive its robots, only in the app in the foreground, and the custody checks limit which files may read it ([#28](https://github.com/Skyman21m/bull-market/issues/28)).
- **The Garage screens**: generate or paste a Garage Key, back it up, meet the first robot, the profile with the key behind the wallet's PIN (when one is set), robot recovery from a pasted key, deleting the key, and the robot panel, which sends a robot to the coordinator the user picks and confirms, then reads it back, after a one-time acknowledgement for a Garage Key that was pasted in or whose draw could not be recorded ([#29](https://github.com/Skyman21m/bull-market/issues/29)). The whole Garage asks for the wallet's screen-capture protection, as the seed screens do (on unless the user turned "Screen Privacy" off in the wallet's settings; a screen capture was blocked in the Garage in the third trial below). Tested over an in-memory stand-in for the secure storage, and tried on a phone (below). Before any release, a copied key is to be flagged as sensitive to Android, and a key typed into the app is to be kept away from the system keyboard ([#56](https://github.com/Skyman21m/bull-market/issues/56)).
- **Taking an order as buyer** ([#88](https://github.com/Skyman21m/bull-market/issues/88), tried on a phone in the tester's real trades since; no request is ever sent to a coordinator by the tests): on the details of a sell order, "Take Order" (with the amount first for an order with a range, "Too low" / "Too high" and "You will receive … Sats (Approx)" as in RoboSats) makes a fresh robot of the Garage Key read the order, which can take a minute over Tor, each step said under the button ([#119](https://github.com/Skyman21m/bull-market/issues/119)); the order details then show the maker's description and the figures that robot read, with "Continue" or "Go back"; "Continue" opens RoboSats' reminder "Store your garage key" (without the key, which the app shows only in the Garage, behind the PIN), and its "Done" takes the order. The trade then opens, as RoboSats' order page, with the tabs "Order" and "Contract": "Lock N Sats to TAKE order" with the QR code of the bond invoice, "Copy to clipboard" and what the app read from the invoice (amount, expiry time, network, description) under "Pay with another wallet", and above it "Pay with this wallet" ([#100](https://github.com/Skyman21m/bull-market/issues/100)): the Instant payments balance, the swap fees asked only on that tap, one confirmation with the amount, the fees, the total, what stays and RoboSats' sentence on a hold invoice, then the payment followed; the statuses that follow as RoboSats titles them ("Submit payout info", "Your info looks good!", "The order has expired"…), "Cancel" with RoboSats' dialogs (free while the bond is not locked, the bond lost after, with "Confirm Cancel"), and the ends (cancelled, not available, public again, when "Take Order" takes it anew with another fresh robot, as RoboSats offers it). The "Order" tab shows the order as RoboSats does, with the coordinator's fees, the maker and "You receive … Sats (Approx)" until the coordinator gives the figure. The trade is read again as often as RoboSats does while its screen is shown, and not at all while the app is in the background. The P2P tab's "Create" becomes "Order" while a trade runs. Once the bond is locked, the buyer gives where to receive the sats, as RoboSats' « Submit payout info » asks ([#91](https://github.com/Skyman21m/bull-market/issues/91)): a Lightning invoice pasted from another wallet, for exactly the amount shown (with RoboSats' routing budget as an advanced option), or a Bitcoin address, paid by the coordinator's swap with its fees and the final amount shown; what the app read of it is shown before « Submit », each wait says what it waits for, and the robot's key, read back from the coordinator, signs exactly what was shown, once; after a failed Lightning payment, the next attempt's countdown, then a new invoice. This has only run against coordinators played by the tests. At the chat step ([#95](https://github.com/Skyman21m/bull-market/issues/95)), the buyer sees RoboSats' prompt and "⚠️ Beware scams", then "Confirm … sent" with RoboSats' dialog ("This action cannot be undone!"), sent once, each wait saying what it waits for; then "Wait for the seller to confirm they have received the payment." with "Payment failed?" (RoboSats' long warning and its 60-second wait), "Attempting Lightning Payment" while the coordinator pays, and "Trade finished!"; behind "…", "Collaborative Cancel" asks the peer or accepts its ask, with RoboSats' dialog and alerts; "Open Dispute", also behind "…", from 18 hours before the end of the chat's time (until then off, with RoboSats' "To open a dispute you need to wait …" counting down), with RoboSats' dialog. A dispute is then shown read-only, with RoboSats' texts and the coordinator's contacts: the statement and the claim of a dispute won are not in the app yet, and the screen says to contact the coordinator. This has only run against coordinators played by the tests. What does not work yet: a buy order (taking it would make the robot a seller: shown disabled), an invoice or address made by this wallet for the payout, the chat itself, the rating and the trade summary (done in the official RoboSats app for now), and notifications.
- **A first trial on a phone** (November 11, 2026, one Android phone, debug build): the P2P tab appeared, Tor connected in about 30 seconds, the six coordinators of the mainnet list all ended up answering, some later than others, and the order book, its filters (which ones were tried was not recorded), pull to refresh, the order details and the reversible-payment warning worked. This is what the tester saw; nothing was measured. Not checked on the phone: the low-bond warning, the testnet banner, the Tor error and its retry, an offline coordinator, the English texts.
- **A second trial on a phone** (later on November 11, 2026, debug build of `main` at `55ba5139c`): the tester reported that everything tried worked as expected, the coordinator details, the Search entry and the depth chart included; what exactly was tried on each screen was not recorded. That build came before the Garage screens.
- **A third trial on a phone** (November 12, 2026, in the morning, debug build): the Garage screens that need no network: the wizard that creates a key, the recovery screen where one is pasted, the backup step, the robot, the profile and the deletion of the key. What exactly was tried on each step was not recorded, apart from the screen capture, which is blocked in the Garage.
- **A fourth trial on a phone** (later on November 12, 2026, debug build): the coordinators' images and the loading waits.
- **A fifth trial on a phone** (in the evening of November 12, 2026, debug build): the new launcher icon and the Tor wait with its percentage and its phrases; the tester's verdict: "everything looks right". The tester also reported that on a first load after a cold start of Tor, several coordinators showed as offline until "Retry" had been pressed a few times, which [#76](https://github.com/Skyman21m/bull-market/pull/76) addresses: the app now asks again by itself a coordinator that did not answer, and shows the row of coordinators above the offers.
- **A sixth trial on a phone** (November 13, 2026, debug build of [#75](https://github.com/Skyman21m/bull-market/pull/75)): from the Garage, a robot of a Garage Key drawn in the app was sent to a coordinator on the wallet's network, and its card came back with "No existing orders found". It is the first run of the robot panel against a real coordinator.
- **A seventh trial on a phone** (November 13, 2026, debug build of [#76](https://github.com/Skyman21m/bull-market/pull/76)): the row of coordinators works, each coordinator lighting up as its book arrives, and on a start from cold the coordinators came in without "Retry" being pressed, with fewer failures than before. One coordinator stayed offline however often "Retry" was pressed, and it did not synchronise in the official RoboSats client on the same phone either, so the trouble lay with that coordinator, not with the app.
- **The rest of a taker's trade** (November 14 to 16): the payout invoice or address made by this wallet ([#150](https://github.com/Skyman21m/bull-market/pull/150), [#155](https://github.com/Skyman21m/bull-market/pull/155)), "Confirm fiat sent", its undo and the collaborative cancel ([#140](https://github.com/Skyman21m/bull-market/pull/140), [#145](https://github.com/Skyman21m/bull-market/pull/145)), the chat of the trade ([#146](https://github.com/Skyman21m/bull-market/pull/146)), sent to the Nostr relays too as the reference does ([#158](https://github.com/Skyman21m/bull-market/pull/158)), with "Audit Chat" and "Export" ([#161](https://github.com/Skyman21m/bull-market/pull/161)), opening a dispute and its statuses, read-only ([#156](https://github.com/Skyman21m/bull-market/pull/156)), the rating, "Rate your host" and the trade summary ([#167](https://github.com/Skyman21m/bull-market/pull/167), [#169](https://github.com/Skyman21m/bull-market/pull/169)), and an order taken as seller, with its collateral and "Confirm received" ([#170](https://github.com/Skyman21m/bull-market/pull/170), [#172](https://github.com/Skyman21m/bull-market/pull/172)).
- **Making an order** (November 16 to 21, [design note](docs/design/phase-3-making-an-order.md)): a buy order at a fixed amount, its bond paid from this wallet, its panels and its cancel ([#199](https://github.com/Skyman21m/bull-market/pull/199), [#201](https://github.com/Skyman21m/bull-market/pull/201), [#203](https://github.com/Skyman21m/bull-market/pull/203)); the reference's advanced options and a range ([#210](https://github.com/Skyman21m/bull-market/pull/210)); pause and resume ([#213](https://github.com/Skyman21m/bull-market/pull/213)); renewing an expired or finished order ([#215](https://github.com/Skyman21m/bull-market/pull/215)); the book's matching orders shown before creating one ([#218](https://github.com/Skyman21m/bull-market/pull/218), [#240](https://github.com/Skyman21m/bull-market/pull/240)); a sell order, with each collateral of an order taken again followed apart ([#223](https://github.com/Skyman21m/bull-market/pull/223), [#232](https://github.com/Skyman21m/bull-market/pull/232)); a password, sent as its SHA-256 and never kept, and a face-to-face location, moved at random as the reference moves it, with nothing of the device's position read ([#241](https://github.com/Skyman21m/bull-market/pull/241)); and "Search order" opening an order the book does not hold, a password-protected one included, to take it ([#248](https://github.com/Skyman21m/bull-market/pull/248)).
- **The wallet's own price as a check** (the owner's rule of November 17): a maker's bond, a maker seller's collateral and a maker buyer's payout are compared with the Bull wallet's price of a bitcoin and the order's premium; more than 10 % on the unfavourable side raises a warning with the two amounts, a rate that could not be read is said as "rate not checked". It informs and never blocks: the user stays free to pay. Nothing compares an order *taken* with that price yet ([#249](https://github.com/Skyman21m/bull-market/issues/249)): a taker is protected by the order read again by their robot and compared with what they saw.
- **The module's database at schema 9** ([#243](https://github.com/Skyman21m/bull-market/pull/243)): it now keeps what each payment took out of the wallet, where the payout of each contract came from, and a trace of terms a coordinator showed otherwise then put back. The step from schema 8 only adds to the file; it has run in tests only, not on a phone yet.
- **Trials on a phone since** (November 14 to 21, debug builds of pull requests, on mainnet coordinators, with small amounts of the tester's own): orders taken; on November 18 a buy order made in the app and run to its end; on November 20 a sell order made in the app, and an order protected by a password made in the app then taken with the official RoboSats client. The tester reported no major problem with the last two builds; what each trial covered step by step was not recorded. His remarks became issues: confirmation screens too heavy to read ([#250](https://github.com/Skyman21m/bull-market/issues/250)), a map too coarse to pin a place ([#246](https://github.com/Skyman21m/bull-market/issues/246)), no way to take a protected order (since written, [#248](https://github.com/Skyman21m/bull-market/pull/248)), a Garage hard to read when an order ended while its page was closed ([#251](https://github.com/Skyman21m/bull-market/issues/251), [#253](https://github.com/Skyman21m/bull-market/issues/253)).
- **Not tried on a phone yet**: the map view of the order book ([#82](https://github.com/Skyman21m/bull-market/pull/82)), the question asked before the robots of a pasted key go to a coordinator ([#77](https://github.com/Skyman21m/bull-market/pull/77)), and the PIN prompts (to show the key, before a delete). Sending a robot from the Garage has been tried once, with a key drawn in the app. Since then: the step of the module's database to schema 9, and an order taken by its URL ([#248](https://github.com/Skyman21m/bull-market/pull/248)).

Left in phase 1: the pass over the texts ([#31](https://github.com/Skyman21m/bull-market/issues/31)).

The Garage's flow for pasted keys is being redesigned ([#79](https://github.com/Skyman21m/bull-market/issues/79)): after the sixth trial, the robots of a pasted key are to be looked up on every coordinator automatically, and a robot is to be bound when an order is made or taken. A design study is open on deriving Garage Keys from the wallet's seed ([#81](https://github.com/Skyman21m/bull-market/issues/81)). Both are planned between phases 3 and 4, with the Nostr backups the reference has; neither is written yet.

Next, to close phase 3: the leaner confirmation screens and their wording ([#250](https://github.com/Skyman21m/bull-market/issues/250)), the detailed map as the reference offers it ([#246](https://github.com/Skyman21m/bull-market/issues/246)), the wallet's price compared for an order taken too ([#249](https://github.com/Skyman21m/bull-market/issues/249)), a fresh robot after each trade ([#251](https://github.com/Skyman21m/bull-market/issues/251)) and a history of the last orders ([#253](https://github.com/Skyman21m/bull-market/issues/253)). Then the Garage Keys derived from the wallet's seed and the Nostr backups ([#81](https://github.com/Skyman21m/bull-market/issues/81), [#79](https://github.com/Skyman21m/bull-market/issues/79)), then phase 4. The design of each phase is written before its code ([taking an order](docs/design/phase-2-taking-an-order.md), [making an order](docs/design/phase-3-making-an-order.md)); a rule keeps every call that can lock, move or release funds in the trade use cases, and keeps automated tests away from money on real coordinators ([#83](https://github.com/Skyman21m/bull-market/issues/83)).

Not done yet: notifications (the app follows a trade only while its screen is open, so whoever makes an order must keep it open or watch with the official client), a dispute's statement and the claim of a dispute won, the claim of a robot's compensations ([#252](https://github.com/Skyman21m/bull-market/issues/252)), the detailed map, and a history beyond the last finished orders. The P2P tab moves no money by itself: every payment is confirmed by the user, and its warnings inform without blocking.

Android first. Nothing is released yet. At this stage, the app still shows Bull's name and logo in places: their removal is tracked in issue [#17](https://github.com/Skyman21m/bull-market/issues/17).

## How it is built

Bull Market adds two modules to Bull's code and touches the rest as little as possible, so that it can keep up with updates of the original wallet. Outside them, the main changes to Bull's own code are in `packages/secrets`, which now also keeps the Garage Keys apart from the seeds, under its custody checks ([#45](https://github.com/Skyman21m/bull-market/pull/45), [#58](https://github.com/Skyman21m/bull-market/pull/58)), and in the shell that mounts the P2P tab and hands it that storage (`lib/router.dart`, `lib/locator.dart`).

| Module | Role |
|---|---|
| [`packages/robosats`](packages/robosats/README.md) | Part of the RoboSats protocol in pure Dart, with no screen and no network access of its own: robot identity, OpenPGP, reading the coordinators, creating a robot on a coordinator and reading it back, and the calls of a taker on an order (read, take, cancel), which nothing calls yet. It talks to the network through an entry point that the app provides. |
| `features/p2p` | The app side: the transport over the wallet's Tor and its facade ([#27](https://github.com/Skyman21m/bull-market/issues/27)), the module's own database, which binds each robot to a single coordinator before any request (`p2p.sqlite`, [#28](https://github.com/Skyman21m/bull-market/issues/28)), the limiter that bounds and spaces the robot requests to each coordinator ([#29](https://github.com/Skyman21m/bull-market/issues/29)), and the screens of the P2P tab, shown only in superuser and developer mode: the order book and its views (list, depth chart, and a map drawn over a public-domain world map bundled with the app), read-only ([#30](https://github.com/Skyman21m/bull-market/issues/30)), and the Garage, whose robot panel is the only screen that sends a robot to a coordinator ([#29](https://github.com/Skyman21m/bull-market/issues/29)), whose Garage Key is kept in the wallet's secure storage (`packages/secrets`). |

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

Every pull request that touches code produces a debug APK, downloadable for 30 days from the [Actions](https://github.com/Skyman21m/bull-market/actions/workflows/build-android.yml) tab (GitHub account required). Its identifier has the `.debug` suffix: it installs alongside the official Bull app.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security vulnerabilities are reported privately: see [SECURITY.md](SECURITY.md).

## Branches

- `main`: this fork's branch, always buildable, changed only through pull requests.
- `develop`: mirror of the `develop` branch of Bull Bitcoin Mobile, never changed here.

## License

AGPL-3.0 for this fork ([LICENSE](LICENSE)). The original Bull Bitcoin Mobile code is under MIT, with its notice kept in [LICENSE-BULL](LICENSE-BULL). Details in [NOTICE.md](NOTICE.md).
