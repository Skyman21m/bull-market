# Client de lecture des coordinateurs (#26) — note de passation

Note temporaire de la branche `feat/p2p-client-lecture`, à supprimer au dernier commit.

## État : terminé, tout est commité

- 531 tests verts dans `packages/robosats` (402 avant ce ticket… en fait 401 + 130 nouveaux), `fvm dart analyze --fatal-warnings --fatal-infos packages/robosats` propre, `dart format` 0 changement, `dart fix --dry-run` « Nothing to fix! », gate custody limitée au paquet : 42 fichiers, 0 violation (10/11/2026 ~18:15 UTC).
- Reste seulement : supprimer cette note, puis le rapport à l'orchestrateur. Pas de push, pas de PR.
- Aucun hook pre-commit n'est installé dans ce worktree (pas de `core.hooksPath`) : les contrôles ont été lancés à la main, limités au paquet. `make analyze` sur tout le projet n'a pas été lancé (il faut la génération de code de l'app).

## Fixtures réelles

Enregistrées le 10/11/2026 13:51–13:55 UTC (Debian trixie, tor + curl, UA navigateur) : info, book, limits de temple, lake, bazaar, freeport, ammanaya (mainnet) et temple (testnet). lake testnet injoignable (curl 97, 3 essais par point d'accès). freeport mainnet et temple testnet : book 404 `not_found`. Détail : `packages/robosats/test/fixtures/coordinator/README.md`. Copies des sources RoboSats dans `test/fixtures/coordinator/sources/`.

## API publique (exportée par `lib/robosats.dart`)

- `RobosatsNetwork` (mainnet, testnet) ; `Federation.robosats`, `Federation(list)`, `byAlias`, `on(network)` ; `Coordinator` (+ `CoordinatorOrigins`, `CoordinatorContact`, `CoordinatorBadges`, `origins`, `nodesPubkeys`, `isOn`, `establishedOn`, `verifyIdentity(info, network)`).
- `RobosatsCurrency` (`all`, `fromId`, `fromCode`, `isBitcoin`).
- Port : `CoordinatorTransport.send(CoordinatorRequest) → Future<Result<CoordinatorResponse, CoordinatorTransportFailure>>`, `CoordinatorHttpMethod`.
- `CoordinatorClient(transport)` : `fetchInfo` (vérifie l'identité), `fetchBook({currency, type})`, `fetchLimits`.
- `FederationBookReader(transport)` : `requestAll` (une future par coordinateur), `read` ; `FederationBook.merge`, `CoordinatorBookOutcome`.
- Modèles : `CoordinatorInfo`, `CoordinatorVersion`, `NoticeSeverity`, `OrderBook`, `PublicOrder`, `OrderType`, `MakerActivity`, `FiatAmount`, `OrderAmount` (`FixedOrderAmount`, `RangeOrderAmount`), `Premium`, `BondSize`, `OrderLocation`, `PaymentMethods`, `PaymentMethodInfo`, `CurrencyLimits`, `CurrencyLimit`, `CoordinatorReadBounds`.
- Échecs (dans `lib/src/robosats_failure.dart`) : `CoordinatorFailure` → `CoordinatorNotOnNetwork`, `CoordinatorTransportFailure` (`CoordinatorUnreachable`, `CoordinatorTimedOut`, `CoordinatorResponseTooLarge`, `CoordinatorTransportFailed`), `CoordinatorUnexpectedStatus(statusCode)`, `CoordinatorNotJson`, `CoordinatorResponseMalformed(field)`, `CoordinatorTooManyOrders`, `CoordinatorIdentityFailure` (`CoordinatorNetworkMismatch`, `CoordinatorNodeIdMismatch`).

## Fichiers

`lib/src/coordinator/` : coordinator.dart, coordinator_client.dart, coordinator_info.dart, coordinator_transport.dart, currency_limits.dart, federation.dart, federation_book.dart, json_fields.dart (interne), order_book.dart, order_values.dart, payment_methods.dart, public_order.dart, read_bounds.dart, robosats_currency.dart, robosats_network.dart, et les générés federation_data.dart, currency_data.dart, payment_method_data.dart (`tool/generate_coordinator_data.dart <checkout robosats> <commit>`). Tests : `test/coordinator/*`, `test/support/coordinator.dart` (faux transport). Docs : `packages/robosats/README.md`, puce « Troc (fork) » d'AGENTS.md, description du pubspec.

## Rejeter la réponse ou écarter l'ordre

- Toute réponse : statut ≠ 200 (sauf book 404 + `not_found` = carnet vide), type de contenu non JSON, UTF-8 ou JSON invalide, corps > borne (info et limits 64 Kio, book 1 Mio), racine du mauvais type → échec de ce coordinateur et de cette requête seulement. Une exception du transport → `CoordinatorTransportFailed`.
- `/api/info/` : un champ requis absent, de mauvais type ou hors bornes rejette toute la réponse (compteurs ≥ 0, sats ≤ 21 M BTC, frais 0–1, caution 0–100, min ≤ max taille d'ordre, `node_id` 66 hex en 02/03, version entière). Champs récents absents → null (`devfund`, `blossom_enabled`, `federation_hash`, `current_swap_fee_rate`, versions LND/CLN, commit, site alternatif, `market_price_apis`, `notice_message` → ''). `network` inconnu → null puis échec d'identité. `notice_severity` inconnu → info (temple envoie « Info »). `federation_hash` mal formé → null. Champs en plus ignorés.
- `/api/book/` : ordre invalide écarté seul et compté (`droppedOrders`) : id, dates (avec fuseau, fin après début), type, devise connue, montant fixe > 0 ou fourchette min ≤ max, `payment_method` ≤ 70, prime −100…999 (ordres explicites au-delà écartés), `satoshis` si explicite, caution 2…15, séquestre 1800…36000 s, lat/lon ensemble et bornées, `maker_hash_id` valide, `maker_nick` égal au pseudo dérivé localement. `maker_status` inconnu → null. `maker` (id base) non lu. Ids dupliqués : toutes les copies écartées. > 1000 éléments → `CoordinatorTooManyOrders`.
- `/api/limits/` : entrée invalide ou devise inconnue écartée (`droppedEntries`) ; > 500 entrées ou racine non objet → rejet.

## Faits RoboSats non évidents (commit ff1998c)

- Carnet vide = 404 `{"not_found": …}` : `api/views.py:797-801`. Le frontend n'envoie aucun paramètre : `frontend/src/models/Coordinator.model.ts:239` ; l'API accepte `currency` (0 = toutes) et `type` (2 = tous) : `api/views.py:782-795`.
- `premium` envoyé en chaîne via `str(premium)` (`api/views.py:812`) ; pour un ordre explicite il est calculé et peut sortir de −100…999 : `api/logics.py:277-295`.
- Activité du maker : `api/logics.py:196-202`. Caution 2–15 codée en dur : `robosats/settings.py:304-305`. Séquestre 30 min–10 h : validateurs de `api/models/order.py`.
- `/api/limits/` : `api/views.py:1177-1197` ; le frontend attend `max_bondless_amount`, que la vue n'envoie pas.
- `/api/info/` ajoute `federation_hash` (vote sur la liste) : `api/views.py:1065-1070`.
- Pseudo = nom d'utilisateur créé depuis le hash : `robosats/middleware.py:148-152`.
