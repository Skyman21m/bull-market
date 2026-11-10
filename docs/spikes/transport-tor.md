# Transport Tor du client RoboSats (ticket #27)

Branche `feat/p2p-transport-tor`, 10/11/2026. Suite du spike [tor-robosats.md](tor-robosats.md), dont ce ticket applique les recommandations.

## Ce qui a été construit

- **Le paquet `features/p2p`** (nom Dart `p2p`), membre du workspace, ajouté à la liste `workspace:` et aux dépendances de l'app. Aucun écran, aucune route, aucun onglet : la fonctionnalité n'est pas encore visible (ticket #29).
- **La façade publique** `lib/p2p.dart` : `P2pFeature.setup(locator)`, appelé par la coquille dans `lib/locator.dart` juste après les journaux, et `P2pFacade`, que la coquille et les futurs écrans utilisent. Elle réexporte les types de `packages/robosats` qui apparaissent dans ses signatures.
- **L'adaptateur `TorCoordinatorTransport`** (`lib/src/data/tor_coordinator_transport.dart`), qui implémente le port `CoordinatorTransport` de `packages/robosats` sur le Tor embarqué : chaîne `tor.embedded.sessions.open()` → `TorSession.endpoint` → `TorHttpClientFactory.create` → Dio, comme dans le spike.
- **Le service**, mince : `requestBooks(réseau)` lance en même temps la lecture du carnet de chaque coordinateur du réseau (`FederationBookReader.requestAll`) et rend un futur par coordinateur ; `fetchInfo(coordinateur, réseau)` lit `/api/info/` avec la vérification d'identité ; `watchTorState()` donne l'état de Tor en quatre étapes (pas démarré, en cours, prêt, échec), tiré de `tor.embedded.states` ; `closeSessions()` ferme toutes les sessions. Toute l'analyse des réponses reste dans `packages/robosats`.

## Décisions

- **Pas d'en-tête `User-Agent`** (décision du projet) : `HttpClient.userAgent = null`, et un `User-Agent` présent dans la requête est retiré. L'en-tête est le même pour tous les utilisateurs de Troc, qui ne se distinguent donc pas entre eux ; Troc n'imite pas le client officiel.
- **`Accept-Encoding: identity`** pour toutes les requêtes, et aucune décompression. Constaté par les tests : `dart:io` demande `gzip` d'office, même quand la décompression automatique est coupée ; une réponse compressée serait alors arrivée illisible. Avec `identity`, le plafond de taille compte les octets réellement reçus : une petite réponse compressée ne peut pas gonfler en mémoire. Un coordinateur qui compresserait quand même verrait sa réponse refusée comme « pas du JSON ».
- **Échéance totale de 132 s par requête** (`torConnectDeadline` × 2), session Tor et nouveaux essais compris. Un premier contact qui échoue au bout du budget de connexion de Tor (60 s) laisse encore un budget entier pour un nouvel essai. Délais Dio par tentative : `torConnectDeadline` (66 s), pour que la raison donnée par Tor arrive avant.
- **Nouvel essai** : un échec avant tout en-tête de réponse (refus SOCKS, service onion injoignable, connexion refusée ou coupée avant les en-têtes) est un échec de connexion. La session est alors fermée et remplacée, et une requête `GET` est retentée au plus 2 fois, chacune sur une nouvelle session (nouveaux circuits). Les autres méthodes ne sont jamais retentées. La raison Tor (`timeout`, `hostUnreachable`…) vient de `TorHttpClientFactory.classify(DioException.error)`, sans variable partagée ; elle n'apparaît que dans la console de développement (`log.info`).
- **Une session Tor par origine de coordinateur** pour les lectures publiques, ouverte à la première requête et partagée par les requêtes simultanées vers ce coordinateur. Une session par robot pour les appels authentifiés reste à faire (#28).
- **`closeSessions()` n'est pas définitif** : le transport est un singleton ; après fermeture, la requête suivante rouvre une session. GetIt l'appelle aussi à la destruction du singleton.
- **Pas de famille `P2pFailure`** pour l'instant : toutes les erreurs sont les `CoordinatorFailure` de `packages/robosats`, réexportées par la façade. Leur traduction pour l'utilisateur viendra avec les écrans.
- **Une `Error`** (bogue de programmation) n'est pas transformée en échec et se propage, comme le veut la règle 11 d'`AGENTS.md` et comme le fait déjà `CoordinatorClient` ; toute `Exception` devient un échec typé.

## Garanties face au contrat du port

| Clause du contrat | Comment | Test (`features/p2p/test/tor_coordinator_transport_test.dart`) |
|---|---|---|
| Toujours terminer par `Ok` ou `Err`, ne jamais lever d'exception | Un `Completer` rempli par le premier qui arrive : la réponse ou la minuterie de l'échéance ; toutes les exceptions sont converties | groupe `never throws` (Tor sans session, fabrique de client qui lève, URL non HTTP) |
| Ne jamais rester en attente | La minuterie de l'échéance totale répond `CoordinatorTimedOut` quoi qu'il arrive, et annule la tentative en cours | `cuts a Tor session that never opens`, `cuts a coordinator that never sends its headers` |
| Échéance totale, corps compris | Même minuterie ; elle annule la lecture du corps par le `CancelToken` de Dio | `cuts a body sent a byte at a time` |
| S'arrêter au plafond de taille, sans garder plus | Corps lu en flux (`ResponseType.stream`) ; au premier morceau qui dépasse, la requête est annulée et le morceau jeté ; refus immédiat si `Content-Length` annonce trop | `accepts a body of exactly the cap`, `refuses a body announced larger than the cap`, `stops reading a chunked body one byte over the cap`, `stops reading a body that never ends and drops the connection` (le serveur voit la connexion fermée) |
| Pas de décompression qui contournerait le plafond | `Accept-Encoding: identity`, `autoUncompress = false` | `neither asks for nor inflates a compressed body` |
| Noms d'en-têtes en minuscules | Réécrits en minuscules, valeurs multiples jointes | `gives the status, the body and lowercase header names` |
| Ne pas suivre les redirections | `followRedirects: false`, `maxRedirects: 0` ; un `3xx` est rendu tel quel au client, qui le refuse | `returns a redirect as it is, without following it`, `lets the coordinator client reject a redirect` |
| Tout le reste en `CoordinatorTransportFailure` | Échec de connexion → `CoordinatorUnreachable` ; connexion coupée pendant le corps → `CoordinatorUnreachable` ; délai → `CoordinatorTimedOut` ; le reste → `CoordinatorTransportFailed` | `gives up after two retries…`, `retries a refused TCP connection`, `reports a connection lost in the middle of the body` |
| Appels simultanés | Une session par origine, partagée ; un compteur d'utilisateurs ferme une session retirée quand sa dernière requête finit | `reuses one session per origin, even for concurrent requests` |
| Nouvel essai sur une nouvelle session, GET seulement | Voir « Décisions » | `retries a GET on a new session after a SOCKS refusal`, `never retries a request that is not a GET` |
| Pas de `User-Agent` | `userAgent = null`, en-tête de la requête retiré | `sends no User-Agent and asks for no compression` |
| Fermeture | `closeSessions` ferme sessions et clients ; une requête en cours échoue sans rouvrir ; une session qui finit de s'ouvrir après est fermée aussitôt | groupe `closeSessions` |

Côté service (`request_federation_books_usecase_test.dart`, `p2p_feature_test.dart`) : toutes les requêtes partent avant la première réponse ; un coordinateur qui ne répond pas ne retarde ni ne cache les autres, et son échec arrive ensuite ; Tor sans session donne un échec par coordinateur, sans exception ; l'état de Tor est bien traduit en quatre étapes.

## Mesures réelles

Un lancement, le 10/11/2026 entre 18:20:03 et 18:22:27 UTC, avec `integration_test/p2p_book_tor_test.dart`. Les 18 lignes de mesure brutes sont versionnées dans [transport-tor-mesures.jsonl](transport-tor-mesures.jsonl).

**Conditions** : app compilée pour Linux de bureau en mode debug, lancée sans écran (Xvfb) dans un conteneur Docker, sur le PC du projet (AMD Ryzen 7 5700U). **Le PC est derrière un VPN Mullvad.** Démarrage à froid : aucun état Tor sur disque, Tor démarré par les premières requêtes du test, comme le fera le premier affichage du carnet. Un seul lancement, un seul créneau : des ordres de grandeur, pas des garanties.

**Résultat : test vert.** Les 5 coordinateurs du réseau principal ont donné une identité vérifiée et un carnet lu ; sur le réseau de test, temple a répondu, lake n'a pas répondu (comme pendant la plus grande partie du spike précédent).

**Démarrage de Tor** : 62,3 s entre les premières requêtes et l'état « prêt » (57,3 s pour Arti, puis la retenue de 5 s de Bull). C'est plus que les 14 à 28 s du spike : un seul lancement, cause non établie.

**Chargement à froid** : les 14 requêtes (infos et carnet de 7 coordinateurs) partent en même temps. Temps en secondes depuis le début ; entre parenthèses, depuis que Tor est prêt.

| Coordinateur | Réseau | Infos | Carnet | Ordres gardés | Ordres écartés | Tronqué |
|---|---|---|---|---|---|---|
| bazaar | mainnet | 66,2 (3,9) | 66,7 (4,3) | 18 | 0 | non |
| ammanaya | mainnet | 78,6 (16,3) | 79,3 (16,9) | 10 | 0 | non |
| lake | mainnet | 79,1 (16,8) | 80,3 (17,9) | 37 | 0 | non |
| temple | mainnet | 85,2 (22,9) | 85,6 (23,2) | 32 | 0 | non |
| freeport | mainnet | 130,7 | 130,6 | 0 (carnet vide) | 0 | non |
| temple | testnet | 77,6 (15,2) | 77,9 (15,6) | 0 (carnet vide) | 0 | non |
| lake | testnet | échec `CoordinatorTimedOut` à 132,0 | échec `CoordinatorTimedOut` à 132,0 | — | — | — |

- **Le nouvel essai a servi** : à 18:22:05, 60,1 s après que Tor fut prêt, quatre premières tentatives ont échoué sur l'expiration du budget de connexion de Tor (`timeout`, 60 s) et ont été relancées sur une nouvelle session. Les seules requêtes encore en cours à ce moment étaient les deux de freeport et les deux de lake testnet. freeport a alors répondu en 8 s environ ; lake testnet n'a pas répondu dans les 9,6 s qui restaient avant l'échéance totale.
- **L'échéance totale tient** : le chargement complet a duré 132,0 s, exactement l'échéance de la requête la plus lente (lake testnet), sous la borne de 3 minutes du test.
- **Premiers contacts plus lents que dans le spike** : 3,9 à 23,2 s après que Tor fut prêt, contre 2 à 13 s une par une dans le spike. Ici 7 sessions s'ouvrent en même temps juste après le démarrage de Tor ; l'effet propre du parallélisme n'est pas isolé.
- **Aucun ordre écarté** par le paquet `robosats` sur 97 ordres reçus, aucun carnet tronqué.
- **Aucun refus lié aux en-têtes** : sans `User-Agent` et avec `Accept-Encoding: identity`, les 6 coordinateurs joints ont répondu en JSON valide (le leurre envoyé à `curl` n'est pas apparu).

**Chargement à chaud** (les 5 carnets du réseau principal relus aussitôt après, sur les sessions déjà ouvertes) : 0,8 à 4,3 s par coordinateur, 4,3 s en tout, 5 sur 5.

**Conséquence pour les écrans (#29)** : à froid, l'échéance totale court pendant le démarrage de Tor. Ici Tor a pris 62 s sur 132 : un premier contact qui échoue au bout des 60 s du budget Tor ne laisse plus qu'environ 10 s au nouvel essai. Deux pistes, à trancher avec les écrans : attendre l'état « prêt » (`watchTorState`) avant de lancer les carnets, ou relancer automatiquement les coordinateurs en échec une fois Tor prêt.

## Ce qui n'est pas vérifié

- **Android** : rien n'a été lancé sur un téléphone ; toutes les mesures viennent d'un PC.
- **Arrière-plan et mise en veille de Tor** : le comportement des sessions quand Tor s'endort puis se réveille n'est pas testé. Une session morte devrait être détectée comme échec de connexion (`proxyUnreachable`) et remplacée, mais ce n'est démontré qu'avec un faux Tor.
- **Une session par robot** pour les appels authentifiés : hors de ce ticket (#28).
- **Snowflake, Orbot, réseau sans VPN** : non essayés.
- **La forme `--dart-define=RUN_LIVE_ROBOSATS_TEST=true`** du drapeau, prévue pour un téléphone : non essayée.
- **L'effet de `Accept-Encoding: identity` sur les coordinateurs** au-delà de cette mesure : aucun refus constaté, mais un seul lancement.

## Relancer la mesure

Depuis la racine du dépôt, après `make deps`, `make build-runner` et `make translations` :

```sh
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; RUN_LIVE_ROBOSATS_TEST=true fvm flutter test integration_test/p2p_book_tor_test.dart -d linux --reporter=expanded'
```

Les mesures sortent sur des lignes `P2P_BOOK_MEASURE {json}` : une par coordinateur et par réseau (carnet, infos, durées en millisecondes depuis le début du chargement), une par coordinateur pour le second chargement « à chaud » du réseau principal, et un résumé. Sans le drapeau, le test est ignoré.
