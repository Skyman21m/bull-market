# Client de lecture des coordinateurs (#26) — note de travail

Note temporaire, supprimée au dernier commit de la branche `feat/p2p-client-lecture`.

## Fait

- Lecture : AGENTS.md, `packages/robosats`, `docs/spikes/tor-robosats.md`, sources RoboSats ff1998c (views, serializers, order, currency, federation.json, currencies.json, Coordinator/Book/Limit/Federation models, ApiWebClient, StringAsIcons, MethodList), inventaire 2.3 / 2.5 / 6.
- Enregistrement réel le 10/11/2026 13:51–13:55 UTC (Tor Debian trixie + curl, UA navigateur) : info, book, limits de temple, lake, bazaar, freeport, ammanaya (mainnet) et temple (testnet). lake testnet injoignable (curl rc=97, échec SOCKS, 3 essais par point d'accès). bazaar info : 1er essai rc=28 (délai), 2e réussi. freeport mainnet et temple testnet : book 404 `{"not_found": ...}` (carnet vide). Fichiers bruts dans `packages/robosats/test/fixtures/coordinator/`.

## Faits RoboSats à retenir

- `/api/book/` renvoie 404 + `{"not_found": "..."}` quand le carnet est vide (`api/views.py:797-801`) : c'est un carnet vide, pas un échec. Le frontend n'envoie aucun paramètre (`Coordinator.model.ts:239`) ; l'API accepte `currency` (0 = toutes) et `type` (0 achat, 1 vente, 2 tous).
- Champs Decimal en chaîne (DRF) : amount, min_amount, max_amount, premium (`str(premium)`), bond_size, latitude, longitude.
- `premium` d'un ordre explicite est calculé et peut sortir de −100…999 (`api/logics.py:277-295`).
- `/api/limits/` : objet indexé par id de devise, `{code, price, min_amount, max_amount}` ; le frontend attend aussi `max_bondless_amount` que la vue n'envoie pas.
- `/api/info/` porte `federation_hash` (vote sur la liste de fédération) ; `blossom_enabled`, `federation_hash` récents → optionnels.
- `maker_status` ∈ "Active", "Seen recently", "Inactive".
- Moyens de paiement : le frontend reconnaît par mot entier (insensible à la casse) les 102 noms de `MethodList.ts` + "not specified" ; PIX et Revolut réversibles.

## Conception (API publique visée)

Dossier `packages/robosats/lib/src/coordinator/`.

- `RobosatsNetwork` (mainnet, testnet).
- Port : `CoordinatorTransport.send(CoordinatorRequest) -> Future<Result<CoordinatorResponse, CoordinatorTransportFailure>>`. Requête : méthode, URL absolue (onion + chemin + requête), en-têtes, corps optionnel, `maxResponseBytes`. Réponse : statut, en-têtes (noms en minuscules), octets du corps.
- Fédération : `Coordinator` (alias, nom long, identifiant, description, devise, couleur, date de création, clé Nostr, contact, badges, politiques, origines mainnet/testnet, clés de nœud par réseau, fédéré) ; `Federation.robosats` (constantes générées de federation.json) ; `coordinator.onion(network)`.
- Devises : `FiatCurrency` (id ↔ code), constantes générées de currencies.json.
- Modèles : `CoordinatorInfo`, `PublicOrder`, `OrderBook` (ordres + nombre d'ordres écartés), `CurrencyLimits`.
- `CoordinatorClient(transport)` : `fetchInfo`, `fetchBook({currency, type})`, `fetchLimits`.
- `verifyCoordinatorIdentity(info, coordinator, network)`.
- `FederationBook` / agrégation : une future par coordinateur, résultat par coordinateur, fusion triée.
- Échecs : `sealed CoordinatorFailure extends RobosatsFailure` dans `robosats_failure.dart`.

## Rejeter la réponse ou écarter l'ordre (décisions)

- Enveloppe (statut ≠ 200, sauf 404 not_found du carnet ; pas JSON ; trop gros ; racine du mauvais type ; plus de N ordres) → échec de toute la réponse du coordinateur, jamais des autres.
- `/api/info/` : un seul objet → champ requis absent / mauvais type / hors bornes → réponse rejetée ; champ récent absent → null.
- `/api/book/` : ordre invalide (type, devise inconnue, montants, prime, caution, durée, dates, hash id, nick) → ordre écarté et compté ; doublon d'id → toutes les copies écartées.
- `/api/limits/` : entrée de devise invalide ou inconnue → entrée écartée ; racine pas un objet → rejet.

## En cours / reste

- [ ] fichiers de types et port, échecs
- [ ] constantes générées + tests d'égalité avec les JSON
- [ ] lecteurs info / book / limits + tests réels + hostiles
- [ ] contrôle d'identité, agrégation, moyens de paiement
- [ ] README du paquet, puce AGENTS.md, analyse / format / fix / custody, suppression de cette note
