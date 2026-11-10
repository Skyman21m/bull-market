# Ticket #27 — note de travail (à supprimer au dernier commit)

Branche `feat/p2p-transport-tor`, worktree `troc-tor`, basée sur la PR #32.

## Plan
1. Lire AGENTS.md, ARCHITECTURE.md, features/logs, packages/bull_tor, le port `CoordinatorTransport`, `docs/spikes/tor-robosats.md`, le test d'intégration du spike.
2. Créer `features/p2p` (pubspec workspace, analysis_options, façade `lib/p2p.dart`, `lib/src/`, setup API), l'ajouter au `workspace:` racine et au locator de la coquille.
3. Adaptateur Tor `CoordinatorTransport` (sessions par origine, Dio sans redirection, plafond en flux, échéance totale, nouvel essai sur nouvelle session pour GET, pas de User-Agent).
4. Service mince : carnets de la fédération en parallèle (`FederationBookReader.requestAll`), `fetchInfo` avec vérification d'identité, état Tor.
5. Tests unitaires (serveur local 127.0.0.1), test d'intégration opt-in `integration_test/p2p_book_tor_test.dart`.
6. Portes : analyze, format, fix, custody, tests robosats ; exécution réelle du test d'intégration.
7. `docs/spikes/transport-tor.md`, FEATURES.md, suppression de cette note.

## Fait
- (rien encore)

## En cours
- Lecture du code existant.

## Reste
- Tout le reste du plan.

## Décisions
- Pas de `User-Agent` (décision projet), `HttpClient.userAgent = null`.

## Résultats à garder
- (aucun)
