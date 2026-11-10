# Ticket #27 — note de travail (à supprimer au dernier commit)

Branche `feat/p2p-transport-tor`, worktree `troc-tor`, basée sur la PR #32.

## Plan
1. Lire AGENTS.md, ARCHITECTURE.md, features/logs, packages/bull_tor, le port `CoordinatorTransport`, `docs/spikes/tor-robosats.md`, le test d'intégration du spike. FAIT
2. Créer `features/p2p` (pubspec workspace, analysis_options, façade `lib/p2p.dart`, `lib/src/`, setup API), l'ajouter au `workspace:` racine et au locator de la coquille. FAIT (commit wip b39bd297f)
3. Adaptateur Tor `CoordinatorTransport` : `lib/src/data/tor_coordinator_transport.dart`. FAIT (à valider par les tests)
4. Service mince : use cases `RequestFederationBooksUsecase` (Map coordinateur → Future), `FetchCoordinatorInfoUsecase`, `WatchP2pTorStateUsecase`, `CloseCoordinatorSessionsUsecase` (port `CoordinatorSessionsPort`), façade `P2pFacade`. FAIT
5. Tests unitaires : 32 tests verts (`fvm flutter test` dans features/p2p). FAIT
6. Test d'intégration opt-in `integration_test/p2p_book_tor_test.dart`. ÉCRIT (commit 7db8b1745)
7. Portes (1er passage) : build-runner OK, translations OK, format-check OK, custody-check OK (2032 fichiers, 0 violation), robosats 520 tests OK ; analyze et fix-check KO sur une accolade du test d'intégration, corrigée, à relancer.
8. Exécution réelle : conteneur `troc-p2p-run1` lancé à 18:05:42 UTC, en cours. Puis lancement sans le drapeau. À FAIRE
9. `docs/spikes/transport-tor.md` : rédigé, mesures à compléter. Suppression de cette note au dernier commit.

## Décisions
- Pas de `User-Agent` (décision projet), `HttpClient.userAgent = null`, et un `User-Agent` présent dans les en-têtes de la requête est retiré.
- `Accept-Encoding: identity` (dart:io envoie `gzip` d'office même avec `autoUncompress = false`, constaté par test) et pas de décompression : le plafond compte les octets reçus.
- Échéance totale par requête = `torConnectDeadline * 2` (132 s), session Tor comprise ; délais Dio par tentative = `torConnectDeadline`.
- Échec « de connexion » = échec avant tout en-tête de réponse, ni délai, ni annulation, ni `Error` : session retirée, GET réessayé 2 fois max sur nouvelle session. Raison Tor via `TorHttpClientFactory.classify(DioException.error)`.
- `Error` (bug) n'est pas attrapé (règle 11), comme `CoordinatorClient`.
- `closeSessions()` non terminal (le transport est un singleton GetIt) ; appelé aussi par le `dispose` de GetIt.
- Pas de famille `P2pFailure` : toutes les erreurs sont des `CoordinatorFailure` de `packages/robosats`, réexportées par la façade.
- Lockfile inchangé (`make deps --enforce-lockfile` passe) ; dépendances déjà verrouillées : bull_logger, bull_tor, dio, get_it, meta, primitives, robosats ; dev : flutter_test, lints, socks5_proxy, test.

## Résultats à garder
- Le test « corps sans fin » avec `HttpServer` ne prouvait rien (HttpServer avale l'erreur d'écriture) : remplacé par un serveur sur socket brute, qui voit bien la connexion fermée par le client.
