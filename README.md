# Troc

> **Prototype en cours de développement. Ne pas utiliser avec des fonds réels.**
> Troc n'est affilié ni à Bull Bitcoin / Satoshi Portal ni à RoboSats. « Troc » est un nom provisoire.

Troc est un fork du portefeuille [Bull Bitcoin Mobile](https://github.com/SatoshiPortal/bullbitcoin-mobile) (Flutter) qui vise à y intégrer un client [RoboSats](https://github.com/RoboSats/robosats) : l'échange de bitcoin de pair à pair, sans compte, via Tor, directement depuis un portefeuille en auto-garde.

*Troc is a fork of Bull Bitcoin Mobile that aims to embed a RoboSats client (peer-to-peer bitcoin exchange over Tor) inside a self-custodial wallet. Early prototype, not affiliated with Bull Bitcoin or RoboSats, do not use with real funds.*

## Où en est le projet

Le travail est découpé en phases, suivies par des [jalons](https://github.com/Skyman21m/troc/milestones) et des [tickets](https://github.com/Skyman21m/troc/issues).

| Phase | Contenu |
|---|---|
| 0 | Mise en place, intégration continue, vérifications techniques (Tor vers un coordinateur, identité robot, PGP, factures « hold ») |
| 1 | Socle en lecture seule : carnet d'ordres, robots, écrans liste et détail |
| 2 | Prendre une offre (parcours « taker ») |
| 3 | Créer une offre (parcours « maker ») |
| 4 | Confort et robustesse : chat Nostr, notifications, litiges |
| 5 | Finition, audit de sécurité indépendant, bêta |

Android d'abord. Rien n'est encore publié. À ce stade, l'application affiche encore par endroits le nom et le logo de Bull : leur retrait est suivi dans les tickets [#4](https://github.com/Skyman21m/troc/issues/4) et [#17](https://github.com/Skyman21m/troc/issues/17).

## Le portefeuille

Toutes les fonctions du portefeuille (Bitcoin, Liquid, Lightning par swaps, sauvegardes, portefeuilles matériels, Payjoin, Tor) viennent de Bull Bitcoin Mobile et sont décrites dans le [README d'origine](https://github.com/SatoshiPortal/bullbitcoin-mobile#readme). Voir aussi [FEATURES.md](FEATURES.md) et [ARCHITECTURE.md](ARCHITECTURE.md).

## Compiler

La chaîne de compilation est celle de Bull, inchangée : voir [AGENTS.md](AGENTS.md) pour les commandes de développement (`make setup`, `make checks`) et [reproducibility/](reproducibility/README.md) pour la compilation reproductible en conteneur. `make android debug` (cible du [makefile](makefile)) produit un APK de debug ; elle utilise podman par défaut, ou Docker avec `CONTAINER=docker`.

Chaque pull request qui touche au code produit un APK de debug, téléchargeable pendant 30 jours depuis l'onglet [Actions](https://github.com/Skyman21m/troc/actions/workflows/build-android.yml) (compte GitHub requis). Son identifiant porte le suffixe `.debug` : il s'installe à côté de l'application Bull officielle.

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Les failles de sécurité se signalent en privé : voir [SECURITY.md](SECURITY.md).

## Branches

- `main` : la branche de Troc, toujours compilable, modifiée uniquement par pull request.
- `develop` : miroir de la branche `develop` de Bull Bitcoin Mobile, jamais modifiée ici.

## Licence

AGPL-3.0 pour Troc ([LICENSE](LICENSE)). Le code d'origine de Bull Bitcoin Mobile est sous MIT, notice conservée dans [LICENSE-BULL](LICENSE-BULL). Détails dans [NOTICE.md](NOTICE.md).
