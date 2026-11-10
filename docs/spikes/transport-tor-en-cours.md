# Ticket #27 — note de travail (à supprimer au dernier commit)

Branche `feat/p2p-transport-tor`, worktree `troc-tor`, basée sur la PR #32.

## Plan
1. Lire AGENTS.md, ARCHITECTURE.md, features/logs, packages/bull_tor, le port `CoordinatorTransport`, `docs/spikes/tor-robosats.md`, le test d'intégration du spike. FAIT
2. Créer `features/p2p` (pubspec workspace, analysis_options, façade `lib/p2p.dart`, `lib/src/`, setup API), l'ajouter au `workspace:` racine et au locator de la coquille. FAIT (commit wip b39bd297f)
3. Adaptateur Tor `CoordinatorTransport` : `lib/src/data/tor_coordinator_transport.dart`. FAIT (à valider par les tests)
4. Service mince : use cases `RequestFederationBooksUsecase` (Map coordinateur → Future), `FetchCoordinatorInfoUsecase`, `WatchP2pTorStateUsecase`, `CloseCoordinatorSessionsUsecase` (port `CoordinatorSessionsPort`), façade `P2pFacade`. FAIT
5. Tests unitaires : `test/tor_coordinator_transport_test.dart`, `test/request_federation_books_usecase_test.dart`, `test/p2p_feature_test.dart`. ÉCRITS, premier passage en cours.
6. Test d'intégration opt-in `integration_test/p2p_book_tor_test.dart`. À FAIRE
7. Portes : build-runner, translations, analyze, format-check, fix-check, custody-check, tests robosats. À FAIRE
8. Exécution réelle du test d'intégration (conteneur détaché `troc-p2p-run1`, puis sans le drapeau). À FAIRE
9. `docs/spikes/transport-tor.md`, suppression de cette note. À FAIRE

## Décisions
- Pas de `User-Agent` (décision projet), `HttpClient.userAgent = null`, et un `User-Agent` présent dans les en-têtes de la requête est retiré.
- `autoUncompress = false` : pas d'`Accept-Encoding`, pas de décompression, donc le plafond compte les octets reçus (une bombe gzip ne peut pas gonfler en mémoire).
- Échéance totale par requête = `torConnectDeadline * 2` (132 s), session Tor comprise ; délais Dio par tentative = `torConnectDeadline`.
- Échec « de connexion » = échec avant tout en-tête de réponse, ni délai, ni annulation, ni `Error` : session retirée, GET réessayé 2 fois max sur nouvelle session. Raison Tor via `TorHttpClientFactory.classify(DioException.error)`.
- `Error` (bug) n'est pas attrapé (règle 11), comme `CoordinatorClient`.
- `closeSessions()` non terminal (le transport est un singleton GetIt) ; appelé aussi par le `dispose` de GetIt.
- Pas de famille `P2pFailure` : toutes les erreurs sont des `CoordinatorFailure` de `packages/robosats`, réexportées par la façade.
- Lockfile inchangé (`make deps --enforce-lockfile` passe) ; dépendances déjà verrouillées : bull_logger, bull_tor, dio, get_it, meta, primitives, robosats ; dev : flutter_test, lints, socks5_proxy, test.

## Résultats à garder
- (aucun encore)
