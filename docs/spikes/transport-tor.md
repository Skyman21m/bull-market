# Transport Tor du client RoboSats (ticket #27)

Branche `feat/p2p-transport-tor`, 10/11/2026. Suite du spike [tor-robosats.md](tor-robosats.md), dont ce ticket applique les recommandations.

## Ce qui a été construit

- **Le paquet `features/p2p`** (nom Dart `p2p`), membre du workspace, ajouté à la liste `workspace:` et aux dépendances de l'app. Aucun écran, aucune route, aucun onglet : la fonctionnalité n'est pas encore visible (ticket #29).
- **La façade publique** `lib/p2p.dart` : `P2pFeature.setup(locator)`, appelé par la coquille dans `lib/locator.dart` juste après les journaux, et `P2pFacade`, que la coquille et les futurs écrans utilisent. Elle réexporte les types de `packages/robosats` qui apparaissent dans ses signatures et dans les champs de ces types (ordre, montant, prime, moyens de paiement, coordinateur, infos), pour qu'un écran n'ait pas à importer `robosats`.
- **L'adaptateur `TorCoordinatorTransport`** (`lib/src/data/tor_coordinator_transport.dart`), qui implémente le port `CoordinatorTransport` de `packages/robosats` sur le Tor embarqué : chaîne `tor.embedded.sessions.open()` → `TorSession.endpoint` → `TorHttpClientFactory.create` → Dio, comme dans le spike.
- **Le service**, mince : `requestBooks(réseau)` lance en même temps la lecture du carnet de chaque coordinateur du réseau (`FederationBookReader.requestAll`) et rend un futur par coordinateur ; `fetchInfo(coordinateur, réseau)` lit `/api/info/` avec la vérification d'identité ; `watchTorState()` donne l'état de Tor en quatre étapes (pas démarré, en cours, prêt, échec), tiré de `tor.embedded.states` ; `closeSessions()` ferme toutes les sessions. Toute l'analyse des réponses reste dans `packages/robosats`.

## Décisions

- **Pas d'en-tête `User-Agent`** (décision du projet) : `HttpClient.userAgent = null`, et un `User-Agent` présent dans la requête est retiré. L'en-tête est le même pour tous les utilisateurs de Troc, qui ne se distinguent donc pas entre eux ; Troc n'imite pas le client officiel.
- **`Accept-Encoding: identity`** pour toutes les requêtes, et aucune décompression. Constaté par les tests : `dart:io` demande `gzip` d'office, même quand la décompression automatique est coupée ; une réponse compressée serait alors arrivée illisible. Avec `identity`, le plafond de taille compte les octets réellement reçus : une petite réponse compressée ne peut pas gonfler en mémoire. Un coordinateur qui compresserait quand même verrait sa réponse refusée comme « pas du JSON ».
- **Échéance totale de 132 s par requête** (`torConnectDeadline` × 2), session Tor et nouveaux essais compris. Délais Dio par tentative : `torConnectDeadline` (66 s), pour que la raison donnée par Tor arrive avant. **Une fois Tor prêt**, un premier contact qui échoue au bout du budget de connexion de Tor (60 s) laisse encore un budget entier pour un nouvel essai. **À froid, ce n'est pas vrai** : le démarrage de Tor compte dans l'échéance ; dans la mesure ci-dessous il a pris 62 s, et il ne restait qu'environ 10 s au nouvel essai. Les écrans doivent donc attendre l'état « prêt » (`watchTorState`) avant de demander les carnets.
- **Échéance passée avant les en-têtes** : la session est remplacée comme après un échec de connexion. Fermer son client annule aussi une connexion encore en cours, qui sinon aurait attendu le délai de la tentative (jusqu'à 66 s).
- **Nouvel essai** : un échec de connexion, c'est une erreur SOCKS ou socket avant tout en-tête de réponse, ou une connexion fermée avant les en-têtes (ce que donne aussi une connexion gardée ouverte qui est morte). La session est alors fermée et remplacée, et une requête `GET` est retentée au plus 2 fois, chacune sur une nouvelle session (nouveaux circuits). Les autres méthodes ne sont jamais retentées. **Une réponse qui n'est pas du HTTP valide** (n'importe quoi à la place de la ligne de statut, `Content-Length` négatif ou en double, caractère NUL dans un en-tête, en-têtes sans fin) veut dire que le coordinateur a répondu : échec `CoordinatorTransportFailed` tout de suite, sans nouvel essai, pour qu'un coordinateur qui répond mal ne passe pas pour hors ligne et ne coûte pas trois sessions (corrigé après la relecture). La raison Tor (`timeout`, `hostUnreachable`…) vient de `TorHttpClientFactory.classify(DioException.error)`, sans variable partagée ; elle n'apparaît que dans la console de développement (`log.info`).
- **Une session Tor par origine de coordinateur** pour les lectures publiques, ouverte à la première requête et partagée par les requêtes simultanées vers ce coordinateur. Une session par robot pour les appels authentifiés reste à faire (#28).
- **`closeSessions()` n'est pas définitif** : le transport est un singleton ; après fermeture, la requête suivante rouvre une session. GetIt l'appelle aussi à la destruction du singleton.
- **Pas de famille `P2pFailure`** pour l'instant : toutes les erreurs sont les `CoordinatorFailure` de `packages/robosats`, réexportées par la façade. Leur traduction pour l'utilisateur viendra avec les écrans.
- **Règle 11 d'`AGENTS.md`, précisément** : toute `Exception` devient un échec typé. Une `Error` (bogue de programmation) levée par l'adaptateur lui-même, ou par l'ouverture de session ou la fabrique de client qu'il reçoit, se propage à l'appelant, comme dans `CoordinatorClient`, après fermeture de la session concernée (fuite de session corrigée après la relecture). Une `Error` levée à l'intérieur de Dio arrive enveloppée dans une `DioException` et devient `CoordinatorTransportFailed`. Une session ou un client qui échoue à se fermer avec une exception est abandonné sans bruit.
- **Seulement `http` vers un hôte `.onion`** : tout autre adresse (`https`, `file:`, un nom ou une adresse IP du web, une adresse qui porte un identifiant et un mot de passe) échoue en `CoordinatorTransportFailed` avant toute session, donc rien n'est envoyé. Un `Coordinator` se construit librement et la façade le réexporte : le transport vérifie lui-même. Les tests visent `127.0.0.1` par un paramètre réservé aux tests.

## Garanties face au contrat du port

| Clause du contrat | Comment | Test (`features/p2p/test/tor_coordinator_transport_test.dart`) |
|---|---|---|
| Toujours terminer par `Ok` ou `Err`, ne jamais lever d'exception | Un `Completer` rempli par le premier qui arrive : la réponse ou la minuterie de l'échéance ; toutes les exceptions sont converties ; une `Error` se propage (règle 11) | groupe `never throws` (Tor sans session, fabrique de client qui lève, URL non HTTP) ; groupe `programming errors` (une `Error` arrive à l'appelant, la session est fermée) |
| Ne jamais rester en attente | La minuterie de l'échéance totale répond `CoordinatorTimedOut` quoi qu'il arrive, et annule la tentative en cours ; avant les en-têtes, la session est aussi remplacée, ce qui annule une connexion en cours dès que les autres requêtes de cette session sont finies | `cuts a Tor session that never opens`, `cuts a coordinator that never sends its headers, and drops the connection` (le serveur voit la connexion fermée), `cancels a connection still being made` |
| Échéance totale, corps compris | Même minuterie ; elle annule la lecture du corps par le `CancelToken` de Dio | `cuts a body sent a byte at a time, and drops the connection` (le serveur voit la connexion fermée) |
| S'arrêter au plafond de taille, sans garder plus | Corps lu en flux (`ResponseType.stream`) ; au premier morceau qui dépasse, la requête est annulée et le morceau jeté ; refus immédiat si `Content-Length` annonce trop | `accepts a body of exactly the cap`, `refuses a body announced larger than the cap`, `refuses at once a body announced too large, and drops the connection` (aucun corps envoyé : seul l'en-tête peut refuser ; le serveur voit la connexion fermée), `stops reading a chunked body one byte over the cap`, `stops reading a body that never ends and drops the connection` (le serveur voit la connexion fermée) |
| Pas de décompression qui contournerait le plafond | `Accept-Encoding: identity`, `autoUncompress = false` | `neither asks for nor inflates a compressed body` |
| Noms d'en-têtes en minuscules | Réécrits en minuscules, valeurs multiples jointes | `gives the status, the body and lowercase header names` |
| Ne pas suivre les redirections | `followRedirects: false`, `maxRedirects: 0` ; un `3xx` est rendu tel quel au client, qui le refuse | `returns a redirect as it is, without following it`, `lets the coordinator client reject a redirect` |
| Tout le reste en `CoordinatorTransportFailure` | Échec de connexion → `CoordinatorUnreachable` ; connexion coupée pendant le corps → `CoordinatorUnreachable` ; délai → `CoordinatorTimedOut` ; réponse qui n'est pas du HTTP, et le reste → `CoordinatorTransportFailed` | `gives up after two retries…`, `retries a refused TCP connection`, `retries a connection closed before the headers`, `reports a connection lost in the middle of the body`, groupe `answers that are not HTTP fail at once, without retry` (une seule session ouverte) |
| Appels simultanés | Une session par origine, partagée ; un compteur d'utilisateurs ferme une session retirée quand, et seulement quand, sa dernière requête finit | `reuses one session per origin, even for concurrent requests`, `closes a replaced session only when its last request ends` |
| Nouvel essai sur une nouvelle session, GET seulement | Voir « Décisions » | `retries a GET on a new session after a SOCKS refusal`, `never retries a request that is not a GET` |
| Pas de `User-Agent` | `userAgent = null`, en-tête de la requête retiré | `sends no User-Agent and asks for no compression` |
| Seulement des services onion | Schéma `http` et hôte en `.onion` vérifiés avant toute session | groupe `only reaches onion services` (défaut de production : `https://….onion`, `http://example.com`, `http://127.0.0.1`, `file:` refusés, aucune session ouverte) |
| Fermeture | `closeSessions` ferme sessions et clients ; une requête en cours échoue sans rouvrir ; une session qui finit de s'ouvrir après est fermée aussitôt, sans servir | groupe `closeSessions` (le serveur ne reçoit aucune connexion de la session tardive) |

Côté service (`request_federation_books_usecase_test.dart`, `p2p_feature_test.dart`) : toutes les requêtes partent avant la première réponse ; un coordinateur qui ne répond pas ne retarde ni ne cache les autres, et son échec arrive ensuite ; Tor sans session donne un échec par coordinateur, sans exception ; l'état de Tor est bien traduit en quatre étapes.

## Mesures réelles

**Toutes ces mesures viennent d'un seul lancement, à froid, sur un PC de bureau derrière un VPN** : des ordres de grandeur, pas des garanties. Il a eu lieu le 10/11/2026 entre 18:20:03 et 18:22:27 UTC, avec `integration_test/p2p_book_tor_test.dart`, sur la version d'avant la relecture (`ec0631a07`). Les corrections faites ensuite (classement des réponses qui ne sont pas du HTTP, session remplacée quand l'échéance passe avant les en-têtes, adresses onion seulement) ne touchent aucun chemin pris pendant ce lancement, sauf la fin de lake testnet, coupé par l'échéance, dont la session serait aujourd'hui aussi fermée ; le test n'a pas été relancé. Les 18 lignes de mesure brutes sont versionnées dans [transport-tor-mesures.jsonl](transport-tor-mesures.jsonl) ; les heures et les nouveaux essais cités plus bas viennent, eux, de la console du lancement, qui n'est pas versionnée.

**Conditions** : app compilée pour Linux de bureau en mode debug, lancée sans écran (Xvfb) dans un conteneur Docker, sur le PC du projet (AMD Ryzen 7 5700U). **Le PC est derrière un VPN Mullvad.** Démarrage à froid : aucun état Tor sur disque, Tor démarré par les premières requêtes du test, comme le fera le premier affichage du carnet. Un seul lancement, un seul créneau : des ordres de grandeur, pas des garanties.

**Résultat : test vert.** Les 5 coordinateurs du réseau principal ont donné une identité vérifiée et un carnet lu ; sur le réseau de test, temple a répondu, lake n'a pas répondu (comme pendant la plus grande partie du spike précédent).

**Démarrage de Tor** : 62,3 s entre les premières requêtes et l'état « prêt » (mesuré, ligne `tor_state` du jsonl). Les 57,3 s d'Arti puis la retenue de 5 s de Bull sont **déduites** des heures de la console (« Starting embedded Tor » à 18:20:03,18, « readiness ready » à 18:21:00,46), pas mesurées par le test. C'est plus que les 14 à 28 s du spike : cause non établie.

**Scintillement de l'état au démarrage** : les quatre premières lignes `tor_state` donnent `notStarted` (19 ms), `connecting` (22 ms), `notStarted` (26 ms), `connecting` (26 ms). Le Tor de Bull passe brièvement par `TorStopped`, que `P2pTorState.of` traduit en `notStarted` (`p2p_tor_state.dart`). À traiter avec les écrans (#29), par exemple en ne montrant pas « pas démarré » une fois une connexion commencée.

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

- **Le nouvel essai a servi** (lu dans la console, pas dans le jsonl : les lignes `log.info` ne nomment pas le coordinateur) : à 18:22:05, 60,1 s après que Tor fut prêt, quatre premières tentatives ont échoué sur l'expiration du budget de connexion de Tor (`timeout`, 60 s) et ont été relancées sur une nouvelle session. Les seules requêtes encore en cours à ce moment, d'après les temps du jsonl, étaient les deux de freeport et les deux de lake testnet : c'est une déduction. freeport a alors répondu en 8 s environ ; lake testnet n'a pas répondu dans les 9,6 s qui restaient avant l'échéance totale.
- **L'échéance totale tient** : le chargement complet a duré 132,0 s, exactement l'échéance de la requête la plus lente (lake testnet), sous la borne de 3 minutes du test.
- **Premiers contacts plus lents que dans le spike** : 3,9 à 23,2 s après que Tor fut prêt, contre 2 à 13 s une par une dans le spike. Ici 7 sessions s'ouvrent en même temps juste après le démarrage de Tor ; l'effet propre du parallélisme n'est pas isolé.
- **Aucun ordre écarté** par le paquet `robosats` sur 97 ordres reçus, aucun carnet tronqué.
- **Aucun refus lié aux en-têtes** : sans `User-Agent` et avec `Accept-Encoding: identity`, les 6 coordinateurs joints ont répondu en JSON valide (le leurre envoyé à `curl` n'est pas apparu).

**Chargement à chaud** (les 5 carnets du réseau principal relus aussitôt après, sur les sessions déjà ouvertes) : 0,8 à 4,3 s par coordinateur, 4,3 s en tout, 5 sur 5.

**Conséquence pour les écrans (#29)** : à froid, l'échéance totale court pendant le démarrage de Tor. Ici Tor a pris 62 s sur 132 : un premier contact qui échoue au bout des 60 s du budget Tor ne laisse plus qu'environ 10 s au nouvel essai. Les écrans doivent attendre l'état « prêt » (`watchTorState`) avant de lancer les carnets ; relancer ensuite les coordinateurs en échec reste une option.

## Ce qui n'est pas vérifié

- **Android** : rien n'a été lancé sur un téléphone ; toutes les mesures viennent d'un PC.
- **Arrière-plan et mise en veille de Tor** : le comportement des sessions quand Tor s'endort puis se réveille n'est pas testé. Une session morte devrait être détectée comme échec de connexion (`proxyUnreachable`) et remplacée, mais ce n'est démontré qu'avec un faux Tor.
- **Une session par robot** pour les appels authentifiés : hors de ce ticket (#28).
- **Snowflake, Orbot, réseau sans VPN** : non essayés.
- **La forme `--dart-define=RUN_LIVE_ROBOSATS_TEST=true`** du drapeau, prévue pour un téléphone : non essayée.
- **L'effet de `Accept-Encoding: identity` sur les coordinateurs** au-delà de cette mesure : aucun refus constaté, mais un seul lancement.
- **Annulation d'une connexion SOCKS en cours quand l'échéance passe** : le transport ferme alors le client de la session, ce qui annule la tâche de connexion de `dart:io` (vérifié avec une fausse connexion : `cancels a connection still being made`). Avec la vraie fabrique de `bull_tor`, l'annulation ne détruit la socket qu'une fois la réponse SOCKS arrivée, donc la connexion locale au port SOCKS peut durer jusqu'au budget de Tor (60 s), bornée et sans fuite durable ; la session Tor est fermée juste après, mais son effet sur une connexion SOCKS en cours n'est pas vérifié.
- **Les corrections faites après la relecture** n'ont été vérifiées que par les tests unitaires : le test réel n'a pas été relancé.

## Relancer la mesure

Depuis la racine du dépôt, après `make deps`, `make build-runner` et `make translations` :

```sh
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; RUN_LIVE_ROBOSATS_TEST=true fvm flutter test integration_test/p2p_book_tor_test.dart -d linux --reporter=expanded'
```

Les mesures sortent sur des lignes `P2P_BOOK_MEASURE {json}` : une par coordinateur et par réseau (carnet, infos, durées en millisecondes depuis le début du chargement), une par coordinateur pour le second chargement « à chaud » du réseau principal, et un résumé. Sans le drapeau, le test est ignoré.
