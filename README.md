# Troc

> **Prototype en cours de développement. Ne pas utiliser avec des fonds réels.**
> Troc n'est affilié ni à Bull Bitcoin / Satoshi Portal ni à RoboSats. « Troc » est un nom provisoire.

Troc est un fork du portefeuille [Bull Bitcoin Mobile](https://github.com/SatoshiPortal/bullbitcoin-mobile) (Flutter) qui vise à y intégrer un client [RoboSats](https://github.com/RoboSats/robosats) : l'échange de bitcoin de pair à pair, sans compte, via Tor, directement depuis un portefeuille en auto-garde.

*Troc is a fork of Bull Bitcoin Mobile that aims to embed a RoboSats client (peer-to-peer bitcoin exchange over Tor) inside a self-custodial wallet. Early prototype, not affiliated with Bull Bitcoin or RoboSats, do not use with real funds.*

## Où en est le projet

Le travail est découpé en phases, suivies par des [jalons](https://github.com/Skyman21m/troc/milestones) et un [tableau de projet](https://github.com/users/Skyman21m/projects/1).

| Phase | Contenu |
|---|---|
| 0 | Mise en place, intégration continue, vérifications techniques (Tor vers un coordinateur, identité robot, PGP, factures « hold ») |
| 1 | Socle en lecture seule : carnet d'ordres, robots, écrans liste et détail |
| 2 | Prendre une offre (parcours « taker ») |
| 3 | Créer une offre (parcours « maker ») |
| 4 | Confort et robustesse : chat Nostr, notifications, litiges |
| 5 | Finition, audit de sécurité indépendant, bêta |

Android d'abord. Rien n'est encore publié.

## Le portefeuille

Toutes les fonctions du portefeuille (Bitcoin, Liquid, Lightning par swaps, sauvegardes, portefeuilles matériels, Payjoin, Tor) viennent de Bull Bitcoin Mobile et sont décrites dans le [README d'origine](https://github.com/SatoshiPortal/bullbitcoin-mobile#readme). Voir aussi [FEATURES.md](FEATURES.md) et [ARCHITECTURE.md](ARCHITECTURE.md).

## Compiler

La chaîne de compilation est celle de Bull, inchangée : voir [AGENTS.md](AGENTS.md) pour les commandes (`make setup`, `make checks`, `make android debug`) et [reproducibility/](reproducibility/README.md) pour la compilation reproductible en conteneur.

Chaque pull request produit un APK de debug, téléchargeable depuis l'onglet [Actions](https://github.com/Skyman21m/troc/actions/workflows/build-android.yml). Son identifiant porte le suffixe `.debug` : il s'installe à côté de l'application Bull officielle.

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Les failles de sécurité se signalent en privé : voir [SECURITY.md](SECURITY.md).

## Branches

- `main` : la branche de Troc, toujours compilable, modifiée uniquement par pull request.
- `develop` : miroir de la branche `develop` de Bull Bitcoin Mobile, jamais modifiée ici.

## Licence

AGPL-3.0 pour Troc ([LICENSE](LICENSE)). Le code d'origine de Bull Bitcoin Mobile est sous MIT, notice conservée dans [LICENSE-BULL](LICENSE-BULL). Détails dans [NOTICE.md](NOTICE.md).
