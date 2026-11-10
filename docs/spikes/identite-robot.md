# Spike 2 : identité du robot RoboSats en Dart

Rédigé le 10/11/2026. Code : paquet `packages/robosats` (Dart pur, sans Flutter, sans réseau, sans PGP). Référence : RoboSats au commit `ff1998c`.

## Résumé

1. Le calcul qui transforme une Garage Key (`robo1…`) en robot est reproduit en Dart de bout en bout : token, valeur envoyée au coordinateur, identifiant public, pseudo, clé Nostr, en-tête `Authorization`.
2. Toutes les valeurs de contrôle préparées avant le spike sont retrouvées au caractère près, sans exception : les 3 robots de test du dépôt RoboSats, la Garage Key d'exemple, les 2 cas limites, les 200 pseudos et l'exemple d'en-tête.
3. Le pseudo dépend d'une division en nombres flottants : le portage la reproduit exactement, y compris sur 38 hash construits exprès pour tomber sur les cas d'arrondi que les 200 pseudos ne couvrent pas.
4. Une question reste ouverte, comme prévu : la formule de la clé Nostr du robot. Les deux formules sont disponibles et testées ; celle du code actuel de l'app officielle est utilisée par défaut. À trancher face à un vrai coordinateur avant de créer un robot réel.
5. Aucune dépendance nouvelle : le fichier `pubspec.lock` n'a pas changé.

## Ce qui est reproduit, et contre quoi c'est vérifié

Les valeurs de contrôle sont dans `packages/robosats/test/fixtures/vecteurs-identite-robot.json`, copie conforme du fichier de préparation du spike. Ses champs `_avertissement` et `_comment_chaque_valeur_est_produite` disent d'où vient chaque valeur.

| Élément | Dans le paquet | Vérifié contre |
|---|---|---|
| Garage Key : génération (32 octets, générateur sûr, injectable en test), forme bech32 `robo1…`, validation | `GarageKey.generate`, `GarageKey.parse`, `GarageKey.fromBytes` | clé d'exemple de `garageKey.test.ts` (dépôt RoboSats) ; aller-retour sur 300 clés aléatoires ; 500 clés altérées de 1 à 4 caractères, toutes refusées ; mauvais préfixe, mauvaise longueur, casse mélangée, bourrage non nul |
| Token du robot n° `i` : SHA-512, BIP32 `m/44'/88'/i'/0`, 36 chiffres base62 de poids faible | `GarageKey.deriveToken` | tokens des index 0, 1 et 18 affirmés par `garageKey.test.ts` ; index 6 des vecteurs ; clé privée intermédiaire des vecteurs ; vecteur n° 1 de la spécification BIP32 ; 25 graines et chemins aléatoires comparés à la bibliothèque BIP32 du portefeuille (`bip32_keys`) |
| Règle d'entropie du token (bits > 128 et Shannon > 4) | `RobotToken.parse`, `RobotToken.measureEntropy` | les 8 tokens des vecteurs ; 9 cas aux limites dont les valeurs attendues viennent de la fonction `validateTokenEntropy` de RoboSats, recopiée et exécutée sous Node |
| `tokenSHA256` en basE91 | `RobotIdentity.tokenSha256Base91` | fichiers `tests/robots/N/b91_token` du dépôt (3 robots) ; 5 autres valeurs des vecteurs dont le cas de 39 caractères ; aller-retour sur 2 000 suites d'octets |
| `hash_id` | `RobotIdentity.hashId`, `RobotHashId.parse` | 8 valeurs des vecteurs ; identifiant utilisateur de la clé PGP du robot de test n° 1, lu par GnuPG |
| Pseudo | `RobotHashId.nickname`, `RobotIdentity.nickname` | 200 pseudos produits par le code Python du coordinateur ; fichiers `tests/robots/N/nickname` ; dictionnaires recalculés à l'identique (même empreinte SHA-256 que les fichiers de RoboSats) |
| Clé Nostr du robot, formule du code actuel | `identity.nostrKeyPair()` | vecteurs seulement (voir la question ouverte) |
| Clé Nostr du robot, formule des jeux de test | `identity.nostrKeyPair(NostrKeyDerivation.repositoryFixtures)` | fichiers `tests/robots/N/nostr_pubkey` du dépôt (3 robots) |
| Clé Nostr de la Garage Key (actuelle et ancienne) | `GarageKey.recoveryNostrKeyPair`, `legacyRecoveryNostrKeyPair` | valeurs affirmées par `garageKey.test.ts` |
| En-tête `Authorization`, forme courte et premier contact | `authorizationHeader()`, `firstContactAuthorizationHeader(...)` | exemple des vecteurs, reconstruit à partir des clés PGP de `tests/robots/1/` ; fins de ligne `\r\n` et `\r` ; découpage en 4 morceaux comme le fait le coordinateur |

Deux points de méthode :

- **Arithmétique flottante du pseudo.** Les 200 pseudos de référence ne distinguent pas un calcul en flottants d'un calcul en entiers exacts (vérifié : un portage en entiers exacts les passe tous). Un second fichier, `pseudos-frontieres-flottantes.json`, contient 38 hash placés sur les frontières : 8 où le flottant et l'entier exact divergent, 8 où l'arrondi de la conversion compte, 15 cas d'égalité parfaite entre deux flottants, 7 valeurs extrêmes. Les valeurs attendues viennent de l'arithmétique de Python (même formule que RoboSats), pas de l'exécution du code de RoboSats.
- **Valeurs secrètes.** Garage Key, token, hash envoyé au coordinateur et clé secrète Nostr n'apparaissent jamais dans `toString()`, ni dans les erreurs. Il faut un appel explicite (`reveal…`) pour les lire. Le paquet n'écrit aucun journal.

## Question ouverte : la clé Nostr du robot

Le dépôt RoboSats contient deux formules qui donnent des clés différentes :

- `sha256(sha512(token))` : le code actuel de l'app (`frontend/src/models/Slot.model.ts:34-38`). C'est le choix par défaut (`NostrKeyDerivation.currentFrontend`). Aucun fichier du dépôt ne permet de vérifier son résultat pour un token.
- `sha256(token)` : la formule qui redonne les fichiers `tests/robots/N/nostr_pubkey` et que décrit `development/docs.md:80` (`NostrKeyDerivation.repositoryFixtures`).

Le coordinateur enregistre la clé une seule fois, à la création du robot, sans contrôle. Une mauvaise formule ne produit aucune erreur : le robot ne recevrait simplement ni notifications ni chat Nostr dans l'app officielle. À trancher avant le premier robot réel, en créant un robot avec l'app officielle sur un coordinateur de test et en lisant `nostr_pubkey` dans la réponse de `GET /api/robot/`.

## Constats et décisions

- **Aucun désaccord trouvé** entre la note de préparation (partie A) et le code source de RoboSats sur les points implémentés.
- **Cas non signalé par la note : hash sans pseudo.** Quand le hash vaut au moins 2^256 − 2^202 (une chance sur 2^54), le quotient flottant s'arrondit à 1,0 et le code Python de RoboSats lève une erreur d'indice : aucun coordinateur ne peut créer ce robot. Le paquet renvoie alors l'échec `NicknameUnavailable` au lieu de planter. C'est utile surtout pour un `hash_id` reçu d'un pair, qui est une donnée non fiable.
- **BIP32 écrit dans le paquet** (une quarantaine de lignes) plutôt qu'avec `bip32_keys` : le contrôle de garde des clés du dépôt (`make custody-check`) réserve la dérivation privée de cette bibliothèque à `packages/secrets`. Une Garage Key n'est pas une graine du portefeuille. Le contrôle, lancé sur le paquet seul, ne signale rien. `bip32_keys` sert uniquement de point de comparaison dans les tests. **Ce paquet manipule du matériel de clé (Garage Key, tokens, clés Nostr) : à signaler dans la demande de fusion.**
- **Un token trop faible n'est pas un `RobotToken`.** `RobotToken.parse` le refuse (échec `TokenEntropyTooLow`), comme l'app officielle refuse de contacter un coordinateur avec. `measureEntropy` reste disponible pour guider la saisie.
- **`hash_id` strict** : 64 caractères hexadécimaux minuscules, rien d'autre.
- **Logarithme en base 2.** Dart n'en a pas ; il est exact pour les puissances de deux, donc les deux seuils (128 bits, Shannon 4) se comportent comme en JavaScript sur ces cas. Pour les autres valeurs, l'écart possible avec JavaScript porte sur les derniers chiffres (tests à 10⁻¹² près), sans effet sur l'acceptation d'un token réaliste.
- **Ajout par rapport à la demande** : la clé Nostr de la Garage Key elle-même (qui sert à retrouver l'index du dernier robot), parce que les vecteurs la contiennent.
- **Non fait, hors périmètre** : génération d'un token aléatoire « historique » (sans Garage Key), avatar, PGP, réseau.
- **`FEATURES.md` non modifié** : la règle (AGENTS.md, règle 13) vise l'ajout d'une fonctionnalité ou un changement dans ce qu'une fonctionnalité consomme. Ce paquet n'est encore utilisé par aucune fonctionnalité, et les paquets d'infrastructure dans la même situation (`bull_pricer`, `bull_payjoin`) n'y figurent pas. L'entrée sera à ajouter avec la première fonctionnalité qui l'utilise.
- **À mettre à jour par ailleurs** : `AGENTS.md` et `ARCHITECTURE.md` énumèrent les membres de l'espace de travail (« vérifié le 08/11/2026 ») ; `packages/robosats` n'y est pas encore.

## Dépendances

Le paquet déclare `crypto` (SHA-256, SHA-512, HMAC), `pointycastle` (courbe secp256k1), `bech32`, `convert`, `meta` et `primitives` (`Result`, `Failure`) ; en test seulement, `bip32_keys`. Toutes étaient déjà dans `pubspec.lock` : après `fvm flutter pub get`, le fichier est inchangé, et `make deps` (verrouillage strict) passe. Seul le `pubspec.yaml` racine gagne une ligne (`- packages/robosats`).

BasE91, base62, regroupement de bits bech32 et BIP32 sont écrits dans `lib/src/`, avec leurs tests. Les dictionnaires de pseudos (4 832 adjectifs, 12 591 noms) sont recopiés de RoboSats (AGPL-3.0, comme Troc), avec mention de l'origine en tête de fichier.

## Ce qui n'a pas pu être vérifié ici

1. **Contre les vraies bibliothèques de l'app officielle** (`base-ex`, `js-sha256`, `@scure/bip32`, `nostr-tools`, `robo-identities-wasm`) : les vecteurs viennent d'une ré-implémentation. Ce spike y ajoute des recoupements indépendants (BIP32 contre `bip32_keys` et la spécification, clé publique Nostr calculée par deux bibliothèques différentes), mais pas l'exécution du frontend.
2. **La clé Nostr du robot, formule actuelle** : voir la question ouverte.
3. **Le pseudo calculé par l'app officielle** (`generate_roboname`) est supposé identique à celui du coordinateur ; seul le code du coordinateur a servi de référence.
4. **Le code Python de RoboSats sur les 38 hash frontières** : son exécution n'a pas été autorisée dans cette session. Les valeurs attendues viennent de la même formule calculée par Python, ce qui valide l'arithmétique mais pas le choix des mots sur ces hash précis.
5. **Les contrôles de tout le projet.** `make analyze`, `make unit-test` et `make custody-check` demandent le code généré, absent en local : ils n'ont pas été lancés. Leurs équivalents ont été lancés sur le paquet seul (analyse, format, `dart fix`, contrôle de garde des clés, tests) et sont au vert. `make fix-check` sur tout le projet a été lancé et échoue en local : il propose des corrections dans 70 fichiers existants de l'application et aucune dans ce paquet, vraisemblablement faute de code généré. À confirmer par la CI.
6. **Aucun échange avec un coordinateur**, et aucune mesure de temps sur téléphone.

## Relancer les tests

Depuis la racine du dépôt, avec l'image d'outils locale :

```
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools bash -c 'make deps && cd packages/robosats && fvm dart test --reporter=expanded'
```

Résultat du 10/11/2026 (Dart 3.12.2) : 169 tests, tous au vert.

Dans la CI, `make unit-test` prend le paquet en compte automatiquement, puisqu'il figure dans la liste `workspace:`.
