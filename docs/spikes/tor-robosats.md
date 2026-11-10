# Spike 1 — Joindre un coordinateur RoboSats par le Tor embarqué

Mesures du 10/11/2026, entre 07:01 et 07:30 UTC. Test : `integration_test/robosats_tor_test.dart`. Base du code : `main` à `50a931af8`.

## Verdict : ça fonctionne

Depuis Dart, avec le Tor déjà embarqué par Bull et sans aucune dépendance nouvelle, l'app appelle `GET /api/info/` sur l'adresse `.onion` d'un coordinateur RoboSats et reçoit la réponse attendue.

## Résumé pour le propriétaire

1. **Les 5 coordinateurs du réseau réel ont répondu**, ainsi que le coordinateur de test « temple ». Chacun a renvoyé la bonne identité (celle inscrite dans la liste officielle de RoboSats).
2. **Le coordinateur de test « lake » est hors ligne** : 9 essais, 9 échecs. Un Tor classique, indépendant de l'app, échoue de la même façon : la panne est de son côté, pas du nôtre. Il ne reste donc qu'un seul coordinateur de test utilisable (temple).
3. **Démarrage de Tor** : 14 à 28 secondes la toute première fois, environ 10 secondes aux lancements suivants.
4. **Premier contact avec un coordinateur** : 2 à 13 secondes, le plus souvent 5 à 6 secondes.
5. **Une fois la connexion ouverte, c'est rapide** : environ 1 seconde par requête.
6. **Fiabilité** : sur 54 premiers contacts vers les 6 coordinateurs en ligne, 51 ont réussi et 3 ont échoué (dont un qui a attendu 60 secondes avant d'abandonner). Sur 90 requêtes enchaînées sur une connexion déjà ouverte, aucune n'a échoué.
7. **Conséquence pour l'app** : prévoir un écran d'attente au premier affichage (compter 20 à 40 secondes à froid), interroger les coordinateurs en parallèle, réessayer automatiquement après un échec, et garder la connexion ouverte au lieu d'en rouvrir une à chaque fois.
8. **Ce qui n'est pas encore prouvé** : le comportement sur un vrai téléphone Android (vitesse, réseau mobile, mise en veille). Ces mesures viennent d'un PC.

## Conditions de mesure

- App compilée pour Linux de bureau en mode debug, lancée sans écran (Xvfb) dans un conteneur Docker, sur un PC (AMD Ryzen 7 5700U, 16 fils d'exécution). Flutter 3.44.9, Dart 3.12.2.
- **Le PC est derrière un VPN Mullvad** (WireGuard, sortie à Zurich, vérifiée pendant la session). Tor s'est connecté en mode direct à chaque fois ; le repli Snowflake n'a jamais été déclenché.
- 9 lancements de l'app en 29 minutes : 4 « à froid » (aucun état Tor sur disque, comme une première installation) et 5 « à chaud » (app relancée, état Tor du lancement précédent conservé sur disque).
- Un seul créneau horaire, un seul réseau, une seule machine : ce sont des ordres de grandeur, pas des garanties.

## Mesures

### Démarrage de Tor (`ensureReady()` jusqu'à `TorReady`)

| Cas | Lancements | Valeurs (s) |
|---|---|---|
| À froid | 4 | 14,0 · 14,1 · 19,7 · 27,7 |
| À chaud | 5 | 9,7 · 9,8 · 9,9 · 10,0 · 10,0 |

Ce temps inclut les 5 secondes de retenue volontaire de Bull après le signal « prêt » d'Arti (visible dans les journaux : « holding readiness for 5s »). Ouvrir une session une fois Tor prêt prend 3 à 15 ms.

### Première requête par coordinateur (nouvelle session Tor, nouvelle connexion)

| Coordinateur | Réseau | Réussites | Min (s) | Médiane (s) | Max (s) | Version | Échecs |
|---|---|---|---|---|---|---|---|
| temple | mainnet | 8/9 | 5,6 | 7,0 | 9,5 | 0.8.8 | 1 × `timeout` après 60,1 s |
| lake | mainnet | 8/9 | 3,7 | 5,2 | 9,0 | 0.8.8 | 1 × `other` après 5,1 s |
| bazaar | mainnet | 9/9 | 3,3 | 6,5 | 13,4 | 0.8.7 | — |
| freeport | mainnet | 9/9 | 3,6 | 5,9 | 7,7 | 0.8.7 | — |
| ammanaya | mainnet | 9/9 | 2,1 | 3,9 | 4,9 | 0.8.8 | — |
| temple | testnet | 8/9 | 4,3 | 6,2 | 9,4 | 0.8.6 | 1 × `other` après 5,2 s |
| lake | testnet | 0/9 | — | — | — | — | 9 × `hostUnreachable` (4,0 à 43,9 s) |

Hors lake testnet : 51 réussites sur 54, médiane 5,6 s, de 2,1 à 13,4 s. Chaque réponse réussie avait le statut HTTP 200, le champ `network` attendu, un `node_id` égal à la clé inscrite dans `federation.json`, et les champs vérifiés par le test (`version`, `maker_fee`, `taker_fee`, `bond_size`, `min_order_size`, `max_order_size`, `num_public_buy_orders`, `num_public_sell_orders`).

### 10 requêtes à la suite sur une même connexion

9 séries de 10 requêtes (8 vers temple mainnet, 1 vers lake mainnet), une session et un client HTTP par série : **90 requêtes, 0 échec**.

| Requêtes | Nombre | Min (s) | Médiane (s) | Max (s) |
|---|---|---|---|---|
| La première de chaque série (ouvre la connexion) | 9 | 5,6 | 8,0 | 11,6 |
| Les suivantes (connexion réutilisée, d'après les temps) | 81 | 0,59 | 0,93 | 2,40 |
| Toutes | 90 | 0,59 | 0,95 | 11,6 |

Par série de 10, la médiane va de 0,69 à 1,22 s. Trois requêtes sur 81 ont dépassé 1,5 s. À noter : `/api/info/` est mis en cache 30 secondes par le serveur, ces temps mesurent donc surtout le trajet Tor.

## Pièges constatés

1. **Pas de nouvel essai automatique.** Dans ce modèle de code, rien ne retente un premier contact raté. Le cas le plus coûteux observé : 60 secondes d'attente (budget Tor `torConnectBudget`) avant l'échec `timeout`, sur temple mainnet, à la première requête d'un lancement à chaud. Les deux autres échecs sont tombés en 5 secondes. Une seule occurrence de chaque : la cause n'est pas établie.
2. **Dio masque la raison de l'échec.** Tous les échecs de connexion arrivent en `DioException` de type `unknown`, avec pour cause une `SocksClientConnectionCommandFailedException`. La raison lisible (`timeout`, `hostUnreachable`…) n'est disponible que par le rappel `onConnectFailure` de `TorHttpClientFactory.create`. Deux échecs ont été classés `other` : le code de réponse SOCKS n'a pas été relevé.
3. **Ouvrir une connexion coûte cher, la réutiliser non.** 5,6 à 11,6 s pour la première requête d'une session, environ 1 s ensuite. Une session par requête serait inutilisable.
4. **Un coordinateur de test sur deux est en panne.** lake testnet est injoignable ; tous les tests testnet de la suite du projet dépendront de temple seul.
5. **Un statut 200 ne suffit pas.** Vérification annexe (Tor classique + `curl`, hors app) : temple mainnet répond 200 à `curl` avec son en-tête par défaut, mais en `text/plain`, avec une taille annoncée de plusieurs Mo de données aléatoires envoyées au compte-gouttes. Avec un en-tête `User-Agent` de navigateur, de Dart, ou sans en-tête, il renvoie le JSON normal en 2 s. Le client de l'app (Dio sur `dart:io`, en-tête par défaut non relevé) n'a jamais reçu ce leurre. Il faut donc valider le type et la forme de la réponse, et ne pas changer l'en-tête `User-Agent` à la légère.
6. **Le drapeau d'activation passe par l'environnement**, hérité par l'app sur Linux de bureau. Sur un téléphone ce n'est pas le cas : le test accepte aussi `--dart-define=RUN_LIVE_ROBOSATS_TEST=true`, forme **non essayée**.
7. **Le test est rouge tant qu'un coordinateur listé est en panne.** Chaque coordinateur a son propre cas de test, ce qui rend le résultat lisible, mais les 9 lancements ont tous fini en « Some tests failed » à cause de lake testnet. Sans le drapeau, les 9 cas sont ignorés proprement (« All tests skipped », vérifié par un lancement).

## Ce qui a été vérifié dans le dossier de préparation

- La chaîne `locator<Tor>().embedded.sessions.open()` → `TorSession.endpoint` → `locator<TorHttpClientFactory>().create(endpoint)` → Dio existe telle que décrite et fonctionne.
- `http://<onion>/api/info/` sans authentification : confirmé pour les 6 coordinateurs en ligne.
- Les adresses et les clés de nœud de `frontend/static/federation.json` (RoboSats `ff1998c`) sont exactes pour les 6 coordinateurs en ligne.
- « Jusqu'à une minute à froid » : ici 14 à 28 s. La retenue de 5 s est confirmée par les journaux.
- Non vérifié ici : la politique « onion uniquement » du proxy (aucune requête clearnet tentée).

## Modèle de code à reprendre en phase 1

Uniquement des noms réels, exécutés par le test. À placer dans `lib/features/p2p/`, jamais dans `lib/core`.

```dart
import 'dart:io';

import 'package:bull_tor/tor.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

// Une session et un client par coordinateur, gardés ouverts tant que l'écran en a besoin.
final TorSession session = await locator<Tor>().embedded.sessions.open();
TorConnectFailure? connectFailure;
final HttpClient client = locator<TorHttpClientFactory>().create(
  session.endpoint,
  onConnectFailure: (failure) => connectFailure = failure,
);
final dio = Dio(
  BaseOptions(
    baseUrl: 'http://$onion',
    connectTimeout: torConnectDeadline,
    receiveTimeout: torConnectDeadline,
    sendTimeout: torConnectDeadline,
  ),
);
(dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () => client;
try {
  final response = await dio.get<Object?>('/api/info/');
  // Valider le type et les champs avant usage : voir le piège 5.
} on DioException {
  // La raison utile est dans connectFailure, pas dans le type Dio.
} finally {
  client.close(force: true);
  await session.close();
}
```

`sessions.open()` démarre Tor si besoin. Pour afficher la progression, écouter `locator<Tor>().embedded.states`.

À ajouter par rapport à ce modèle : interrogation des coordinateurs en parallèle, nouvel essai après échec, délai d'attente plus court que 66 s pour l'affichage, contrôle du `node_id` contre la liste de la fédération.

## Ce qui reste inconnu

- **Android** : temps de démarrage et de premier contact sur un téléphone, en Wi-Fi et en réseau mobile, en version release.
- **Arrière-plan** : mise en sommeil de Tor quand l'app n'est plus au premier plan, puis réveil (le test ne lance pas le contrôleur de cycle de vie).
- **Sessions en parallèle** : le test interroge les coordinateurs l'un après l'autre.
- **Sans VPN, ou sur un réseau qui bloque Tor** : repli Snowflake jamais déclenché ici.
- **Proxy Tor externe (Orbot)** : non essayé.
- **Durée** : 29 minutes d'observation ; aucune donnée sur une connexion gardée ouverte des heures.
- **Routes authentifiées, POST, WebSocket** (`/relay/`, chat) : hors de ce spike.
- **Cause du `timeout` de 60 s et des deux échecs `other`.**

## Relancer la mesure

Depuis la racine du dépôt, après `make deps`, `make build-runner` et `make translations` :

```sh
export RUN_LIVE_ROBOSATS_TEST=true
xvfb-run -a dbus-run-session -- bash -c 'echo "" | gnome-keyring-daemon --unlock --daemonize --components=secrets; fvm flutter test integration_test/robosats_tor_test.dart -d linux --reporter=expanded'
```

Les mesures sortent sur des lignes `ROBOSATS_TOR_MEASURE {json}`. Premier lancement : environ 13 minutes de compilation sur ce PC (crates Rust comprises), puis environ 1 minute avant le début des tests aux lancements suivants. Un fichier de test seul se lance directement, sans passer par l'agrégateur `all_test.dart`.
