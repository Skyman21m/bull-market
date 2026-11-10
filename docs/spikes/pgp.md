# Spike 3 : PGP du robot RoboSats en Dart

Rédigé le 10/11/2026, mis à jour le même jour après la revue de sécurité. Code : paquet `packages/robosats` (Dart pur, sans Flutter, sans réseau). Référence : RoboSats au commit `ff1998c`. Note de préparation : `preparation-identite-et-pgp.md`, partie B (dossier du projet).

## Résumé

1. Le paquet sait fabriquer la clé PGP d'un robot, la relire, signer une facture ou une adresse, et chiffrer, signer, déchiffrer et vérifier un message de chat.
2. **GnuPG 2.4.4, le moteur des coordinateurs, et OpenPGP.js 5.11.3, la bibliothèque de l'app officielle, acceptent tout ce que le code produit, et le code lit tout ce qu'ils produisent.** C'est vérifié dans les deux sens par un script relançable, et par le relecteur de sécurité sur 1 500 messages dans chaque sens.
3. La clé produite et les messages de chat ont exactement la même structure que ceux de l'app officielle : un coordinateur ne peut pas distinguer Troc de l'app officielle par leur forme.
4. Après la revue de sécurité du 10/11/2026, **`dart_pg` est entièrement retiré** : tout l'OpenPGP utile à RoboSats est écrit dans le paquet, au-dessus de primitives existantes (`pinenacl`, `pointycastle`, `crypto`). Décision du propriétaire : cette couche Dart est provisoire, une bibliothèque Rust la remplacera avant toute diffusion.
5. Tout ce que le paquet lit est borné en taille et en coût : aucun message, aucune clé, aucune signature venant d'un coordinateur ou d'un pair ne peut faire planter l'app ni lever une exception.
6. Rien n'a été envoyé à un coordinateur.

## Bibliothèque

**Pourquoi `dart_pg` 2.0.0 a été retiré.** Constats faits en l'exécutant, puis par la revue de sécurité :

1. **Déni de service sans aucune clé.** Son lecteur de paquets décompresse récursivement pendant la lecture, avant toute authentification : un message de 415 caractères (4 Gio une fois décompressé) tuait le processus.
2. **Marque dans chaque signature** : une notation `salt@notations.dart-pg.org` aléatoire, non désactivable (`lib/src/packet/signature.dart:188-192`), qui désignerait Troc au coordinateur.
3. **Aléa non injectable** (`lib/src/common/helpers.dart:24`) : pas de test déterministe possible.
4. **Deux erreurs sur les zéros de tête** : une clé Ed25519 sur 256 illisible, une signature valide sur 100 environ rejetée.
5. **Exceptions non typées sur une clé de pair hostile** (paramètres KDF altérés) ; auto-signature différente de celle d'OpenPGP.js ; en-têtes d'armure ; lecture des clés dépendante de l'horloge.

**Ce qui le remplace.** `lib/src/pgp/` (1 891 lignes, commentaires compris) contient l'armure, les paquets, les clés, les signatures, l'échange de clé ECDH (RFC 6637) avec l'enveloppe de clé AES (RFC 3394), le bloc chiffré avec contrôle d'intégrité et la lecture bornée des messages. `lib/src/robot_pgp_key.dart` (520 lignes) est l'interface publique. Les primitives viennent de `pinenacl` (Ed25519, X25519), `pointycastle` (AES) et `crypto` (SHA) ; la décompression, de `dart:io`. Aucun type de ces bibliothèques ne sort du paquet.

**Autres voies de la note.** `openpgp` (binaires Go) et `pgp_dart` (Sequoia, 0.0.1) n'ont pas de date de création réglable : écartées. La bibliothèque Rust (rPGP ou Sequoia) est la cible avant diffusion.

## Paramètres reproduits

| Élément | Valeur | Source RoboSats | Dans le paquet |
|---|---|---|---|
| Type de clé | v4, primaire EdDSA « historique » ed25519 (algo 22), sous-clé ECDH cv25519 (algo 18, paramètres `03 01 08 07`) | `frontend/src/pgp/index.ts:23-25` ; `tests/robots/3/enc_priv_key` | `RobotPgpKey.generate` |
| Identifiant | `RoboSats ID <hash_id>` | `pgp/index.ts:26` | `RobotIdentity.pgpUserId` |
| Phrase de passe | le token | `pgp/index.ts:27` | `generate`, `unlock` |
| Date de création | maintenant moins un jour | `pgp/index.ts:29` | 24 h exactement (voir « Écarts ») |
| Protection de la clé privée | usage 254, AES-256 CFB, S2K itéré et salé SHA-256, compteur 224 (16 Mio), contrôle SHA-1 | `tests/robots/3/enc_priv_key` | `ProtectedSecret.lock` |
| Auto-signature | type 0x10, SHA-512, sous-paquets 2\*, 11 (9 7 8), 16\*, 21 (8 10), 22 (0 2 1), 25, 27\* (03), 30 (01), 33 ; \* = critique | idem | `selfCertification` |
| Liaison de sous-clé | type 0x18, **SHA-512**, sous-paquets 2\*, 16\*, 27\* (0C), 33 | idem | `subkeyBinding` |
| Armure | sans en-tête, lignes de 60 caractères, ligne CRC, `\n` | `tests/robots/*/enc_priv_key` | `armorEncode` |
| Contrôle de forme de la clé publique | ligne vide obligatoire, lignes base64 | `api/utils.py:496-518` | test « passes the shape check of the coordinator » |
| Âge minimal de la clé | 12 heures | `api/utils.py:582-594` | clé datée de 24 h |
| Signature en clair | type 0x01, SHA-512, clé primaire, datée de maintenant | `pgp/index.ts:102-119` | `signCleartext` |
| En-tête exigé | `-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n` | `api/utils.py:642-644` | `cleartextEncode` |
| Signataire exigé | empreinte de la clé primaire | `api/utils.py:641` | signature par la clé primaire |
| Message de chat | chiffré pour soi puis pour le pair, signé, signature datée de la veille | `pgp/index.ts:39-62` | `encryptChatMessage` |
| Lecture du chat | texte rendu même si la signature est invalide | `pgp/index.ts:70-99` | `decryptChatMessage` |
| Refus d'envoyer son token | message bloqué | `EncryptedApiChat/index.tsx:210-214` | échec `PgpPlaintextContainsToken` |
| En-tête du premier contact | sauts de ligne remplacés par `\` | `frontend/src/models/Robot.model.ts:82-83` ; `robosats/middleware.py:53-59`, `122-125` ; `api/utils.py:525-526` | `firstContactAuthorizationHeader`, `pgpArmorToWire` |

Contenu du message de chat produit, vu par GnuPG : deux paquets de clé de session v3 (ECDH), un bloc chiffré v1 avec contrôle d'intégrité, AES-256, sans compression ; à l'intérieur, signature « une passe », données littérales au format `u` et signature.

### Chat par REST (`/api/chat/`)

- `GET /api/chat/?order_id=<id>&offset=<n>` (`chat/views.py:40-113`) : réponse `{"peer_connected", "peer_pubkey", "messages": [{"index", "time", "message", "nick"}]}`. `message` est le bloc `PGP MESSAGE`. Statuts d'ordre 9, 10, 11 et 16.
- `POST /api/chat/` (`chat/views.py:116-218`, `chat/serializers.py:61-84`) : corps `{"PGP_message", "order_id", "offset"}`. Statuts 9 et 10. Avec `offset`, même réponse que le `GET` ; sinon `{}`.
- Dans `PGP_message`, chaque saut de ligne devient un `\` (`EncryptedChat/index.tsx:263`) ; l'app les rétablit à la lecture (`EncryptedApiChat/index.tsx:141` et `166`). Fonctions `pgpArmorToWire` et `pgpArmorFromWire` ; les lectures du paquet acceptent les deux formes.
- Le texte en clair ne quitte jamais l'appareil. Le coordinateur ne stocke que le bloc chiffré (`chat/models.py:87`). Le robot relit ses propres messages en les déchiffrant, puisque chaque message est aussi chiffré pour lui.
- L'auteur d'un message se déduit du pseudo renvoyé : le sien, donc sa propre clé publique, sinon celle du pair (`EncryptedApiChat/index.tsx:156`). C'est le paramètre `sender` de `decryptChatMessage`.
- L'app officielle interroge toutes les 5 secondes (`EncryptedApiChat/index.tsx:53`).

## Matrice d'interopérabilité

| Sens | État | Comment |
|---|---|---|
| Dart → GnuPG 2.4.4 | **prouvé** | `tool/pgp_interop.sh` : import de la clé publique (`imported: 1`), date et identifiant lus, ré-export, import de la clé privée sans phrase de passe (`secret keys imported: 1`), `--list-packets` identique à `tests/robots/3/enc_priv_key` hors valeurs propres à la clé, facture signée vérifiée (`VALIDSIG`, EdDSA, SHA-512, empreinte primaire), texte extrait par le code Python du coordinateur, signature par GnuPG avec notre clé et le token, chat déchiffré par le pair et par notre clé (`DECRYPTION_OKAY`, `GOODMDC`, signature datée de la veille) |
| GnuPG 2.4.4 → Dart | **prouvé** | même script : clé ré-exportée par GnuPG, clé ed25519/cv25519 générée par GnuPG, texte signé en clair par GnuPG, message compressé, chiffré et signé par GnuPG ; plus `tests/robots/1/signed_message` du dépôt |
| Dart → OpenPGP.js 5.11.3 | **prouvé** | même script, avec les appels de `frontend/src/pgp/index.ts` : clé déverrouillée par le token et validée, blocs identiques à l'octet après un aller-retour, facture signée vérifiée, chat déchiffré comme pair et comme expéditeur avec signature valide, texte signé par notre code avec une clé d'OpenPGP.js vérifié. Revue de sécurité : 1 500 messages, 0 échec |
| OpenPGP.js 5.11.3 → Dart | **prouvé** | même script : clé générée par OpenPGP.js lue et déverrouillée, deux textes signés (dont un à tirets, blancs de fin de ligne et plusieurs lignes) rendus exactement comme OpenPGP.js les rend, chat signé et non signé déchiffrés. Revue de sécurité : 1 500 messages, 0 échec. Plus les clés `tests/robots/{1,2,3}` du dépôt |
| Structure | **identique** | `gpg --list-packets` : notre clé contre `tests/robots/3` et contre une clé d'OpenPGP.js ; notre message de chat contre un message d'OpenPGP.js (deux clés de session v3, bloc chiffré v1, signature « une passe », littéral `u`, signature à sous-paquets 2, 16, 33, sans compression) |
| GnuPG 2.2 (image officielle des coordinateurs) | **non exécuté** | pas d'image Debian bookworm en local |
| python-gnupg réel | **non exécuté** | non installé ; ses lignes de commande sont reproduites de mémoire dans le script |
| Coordinateur réel | **non exécuté** | étape suivante |

Les artefacts du dernier passage du script sont dans `packages/robosats/test/fixtures/pgp_interop/`, avec ce que GnuPG et OpenPGP.js ont affiché (`transcript.txt`). La génération, la signature et, à aléa fixé, le chiffrement sont déterministes : les tests vérifient à chaque exécution que le code écrit encore, à l'octet près, la clé, la facture et le message que GnuPG et OpenPGP.js ont acceptés, et qu'il lit toujours ce qu'ils ont écrit.

## Bornes et refus

Tout est dans `lib/src/pgp/limits.dart`. Au-delà, l'échec est `PgpInputTooLarge` ou un refus typé, jamais une exception.

| Borne | Valeur | Repère |
|---|---|---|
| Bloc de clé armuré | 20 000 caractères, 32 paquets | une clé de robot : 1 000 caractères, 5 paquets |
| Texte signé en clair | 20 000 caractères, 8 signatures | le coordinateur accepte 15 000 caractères |
| Message de chat armuré | 65 536 caractères ; texte de 30 000 octets à l'envoi | |
| Clés de session par message | 8 | l'app officielle : 2 |
| Signatures par message | 8 | l'app officielle : 1 |
| Décompression | 262 144 octets, une seule couche | l'app officielle ne compresse pas |
| Hachage S2K d'une clé privée | 32 Mio | OpenPGP.js : 16 Mio. Une clé privée protégée par GnuPG avec un compteur plus élevé est refusée |

Un message de chat n'est lu que s'il est fait de clés de session suivies d'un seul bloc chiffré v1, rien d'autre. Rien n'est décompressé ni interprété avant le contrôle d'intégrité (SHA-1 du bloc). À l'intérieur : signatures « une passe », un seul texte, des signatures, directement ou dans un seul paquet compressé. C'est plus strict qu'OpenPGP.js, qui tolère des paquets autour du bloc chiffré.

Une clé de pair est refusée (`PgpKeyUnsupported`) si ses paramètres KDF ne sont pas SHA-256/384/512 avec AES, ou si son point X25519 est d'ordre faible (secret partagé nul).

## Règles de dates

Elles suivent OpenPGP.js 5, sans tolérance, contre une horloge injectable (`now`) :

- une signature datée après l'horloge est refusée (« Signature creation time is in the future ») ;
- une signature expirée est refusée ;
- une signature antérieure à la clé est refusée (« Key is newer than the signature »), de même qu'une signature faite quand la clé était expirée ou avant son auto-signature ;
- on ne chiffre pas pour une clé datée du futur, expirée, ou dont une auto-signature a expiré (`PgpKeyOutOfDate`).

**Contrainte d'ordre des dates.** L'app officielle date ses signatures de chat de la veille et refuse une signature plus ancienne que la clé de son auteur. Notre clé est datée de 24 h avant sa création et nos signatures de 24 h avant l'envoi : l'ordre est toujours respecté, et si l'horloge recule, la signature est datée comme la clé, jamais avant. L'app officielle, elle, retire un jour de calendrier : 23 h ou 25 h les deux jours de changement d'heure. Ce jour-là, elle peut refuser pendant une heure au plus de chiffrer pour une clé toute neuve, y compris une des siennes ; rien à corriger de notre côté.

**Propriété inhérente à RoboSats.** Une signature de chat et une signature « en clair » sont le même objet (signature de texte par la clé primaire). Une signature faite pour un message de chat vaut donc signature en clair du même texte, et inversement. Ne jamais faire signer en chat un texte qui serait une facture ou une adresse à soi.

## Ce que la revue de sécurité a demandé, et ce qui a été rejoué

**Entrées de déni de service du relecteur**, relues par `decryptChatMessage` (exécutable compilé, sur ce poste) : toutes rejetées par un échec typé.

| Entrée | Taille armurée | Avant | Maintenant |
|---|---|---|---|
| 3 couches de compression, 4 Gio | 415 caractères | processus tué (plus de 1,5 Gio) | `PgpMessageUndecryptable`, 0,09 ms, 12 Mio |
| 3 couches de compression, 256 Mio | 366 caractères | pic de 1 038 Mio | `PgpMessageUndecryptable`, 0,08 ms, 12 Mio |
| 2 000 paquets compressés imbriqués | 5 495 caractères | | `PgpMessageUndecryptable`, 0,4 ms, 11 Mio |
| 10 000 paquets compressés imbriqués | 27 186 caractères | | `PgpMessageUndecryptable`, 1,6 ms, 11 Mio |
| 50 000 paquets compressés imbriqués | 135 628 caractères | 690 Mio | `PgpInputTooLarge`, 0,02 ms, 11 Mio |
| paquets vides, 50 à 400 ko | 69 467 à 555 300 caractères | jusqu'à 26 s | `PgpInputTooLarge`, 0,02 ms, 13 Mio au plus |

La mémoire indiquée est celle du processus entier, dont 12 Mio avant l'appel. Les deux bombes de compression sont des jeux d'essai du paquet (`test/fixtures/pgp_hostile/`) ; les autres entrées sont reconstruites par les tests. Une bombe placée à l'intérieur d'un message correctement chiffré par un pair (16 Mio de zéros) est refusée de même : la décompression s'arrête à 256 Kio.

**Clés hostiles** : chaque variante du relecteur (champ KDF vide, tronqué, à condensat ou chiffrement inconnu, MD5 et 3DES, 200 octets, point nul) est maintenant refusée à la lecture par `PgpKeyUnsupported`, avec les sept points X25519 d'ordre faible connus. SHA-512 avec AES-256 et SHA-384 avec AES-192 sont acceptés et testés en aller-retour. Une modification d'un octet, à chaque position, d'une clé publique, d'une clé privée, d'un texte signé et d'un message de chat ne lève jamais d'exception (4 tests).

**Mutants.** 75 altérations du code de `lib/src/pgp/` et de `robot_pgp_key.dart` (celles du relecteur portant sur la sécurité, adaptées au nouveau code, plus 34 sur le code nouveau : contrôle d'intégrité, enveloppe, bornes, dates, KDF, secret partagé nul) ont été appliquées une à une, la suite de tests étant relancée à chaque fois. 73 font échouer au moins un test. Les 2 qui passent sont sans effet observable :

- accepter du texte après la ligne `-----END …-----` : la ligne `END` se retrouve alors dans le corps, qui n'est plus du base64 valide, et le bloc reste refusé ;
- ne plus vérifier qu'un paquet de sous-clé est du bon genre (public dans un bloc public) : il reste alors des octets non lus, ou il en manque, et la sous-clé reste écartée.

Les 18 survivants signalés par la revue ont chacun leur test, avec des paquets réellement re-signés (`test/support/craft.dart`).

**Vérification plus stricte** : signature expirée, datée du futur, antérieure à la clé, sans en-tête `Hash:` : refusées ; blancs ajoutés en fin de ligne : le texte rendu est le texte signé, sans eux.

## Écarts

Avec la note de préparation :

- **Liaison de sous-clé en SHA-512, pas SHA-256.** La note (B1.3) décrit le robot de test n° 1, de 2023. Le n° 3, de février 2025, et une clé faite par OpenPGP.js 5.11.3 ont une liaison en SHA-512. Le paquet fait de même.
- `dart_pg`, recommandé par la note, est retiré (voir « Bibliothèque »).

Avec la demande initiale :

- **Antidatage de 24 h exactement**, et non d'un jour de calendrier (voir « Règles de dates »).
- **Garde-fous ajoutés** : `signCleartext` refuse un texte que le découpage du coordinateur ne rendrait pas intact ; `encryptChatMessage` refuse un texte contenant le token.
- **Limites assumées** : seules les clés v4 ed25519 + cv25519 sont acceptées (un pair qui aurait fourni une clé RSA par l'API serait illisible) ; la révocation n'est pas évaluée (un coordinateur garde la première clé d'un robot).

Changements d'interface dus aux corrections :

- `RobotPgpKey.generate(identity)` n'accepte plus d'horloge ni d'aléa ; la variante de test est `generateWith`, marquée `@visibleForTesting`. Même chose pour `encryptChatMessageWith` et `GarageKey.generateWith`. Un aléa faible ne peut plus être passé en production sans avertissement de l'analyseur.
- `signCleartext` et `encryptChatMessage` renvoient maintenant n'importe quel `PgpFailure` ; `verifyCleartext` et `decryptChatMessage` acceptent `now` ; deux échecs nouveaux : `PgpInputTooLarge`, `PgpKeyOutOfDate`.
- `verifyCleartext` renvoie le texte réellement signé (sans les blancs de fin de ligne) et exige l'en-tête `Hash:`.

## Risques

| Risque | Parade |
|---|---|
| Code de sécurité écrit à la main (1 891 lignes) | provisoire, à remplacer par une bibliothèque Rust avant diffusion ; recoupé par GnuPG et OpenPGP.js dans les deux sens ; revue de sécurité indépendante ; tests de mutation ; le contrôle de garde des clés ne le voit pas : même vigilance que pour `packages/secrets` |
| `pinenacl` 0.6.0 : portage de TweetNaCl, pas d'audit connu | vecteurs RFC 8032 et RFC 7748 dans les tests |
| Aucun code Dart n'est à temps constant | inhérent au Dart pur ; la clé privée chiffrée est de toute façon chez le coordinateur |
| Secrets en mémoire | les tampons transitoires que le paquet possède sont remis à zéro (clés dérivées, copies du token, clé de session) ; la graine et le scalaire restent dans `UnlockedRobotPgpKey` le temps d'une tâche ; les copies faites par le ramasse-miettes et par les bibliothèques sont hors de portée ; rien n'est écrit ni journalisé ; `toString()` et échecs sans secret |
| Durée du déverrouillage (32 Mio de SHA-256) | 0,3 s mesuré sur ce poste ; téléphone non mesuré ; à appeler hors du fil d'interface, une fois par lot de messages |
| Clé de pair malveillante fournie par le coordinateur | inhérent à RoboSats : le coordinateur distribue les clés |
| Horloge du téléphone fausse de plus de 24 h | les signatures de l'app officielle paraissent « du futur » et sont marquées invalides ; l'app officielle a le même comportement |

## Dépendances

`pubspec.lock` : par rapport à `main`, un seul paquet ajouté, `pinenacl` 0.6.0 (MIT, Dart pur, portage de TweetNaCl). `dart_pg` 2.0.0, `sign_dart` 1.0.0 et `sha3` 0.2.1, ajoutés au début du spike, ont été retirés par `fvm flutter pub get`. `make deps` (verrouillage strict) passe.

## Reste à tester

1. **Face à un coordinateur de test** : création du robot avec une clé de Troc, `update_invoice` avec une facture signée, envoi et relecture d'un message de chat, restauration du robot avec le seul token.
2. GnuPG 2.2.x et le vrai python-gnupg : relancer `tool/pgp_interop.sh` sur une Debian bookworm.
3. Temps de génération et de déverrouillage sur un téléphone Android milieu de gamme.
4. Limite de taille de `PGP_message` : le modèle annonce 5 000 caractères (`chat/models.py:87`), sans contrôle visible dans le sérialiseur.
5. Les contrôles de tout le projet (`make analyze`, `make unit-test`, `make custody-check`) demandent le code généré, absent en local : seuls leurs équivalents sur le paquet ont été lancés.

## Relancer

Tests du paquet, depuis la racine du dépôt :

```bash
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools \
  bash -c 'make deps && cd packages/robosats && fvm dart test'
```

Recoupement avec GnuPG et OpenPGP.js, sur une machine qui a GnuPG et l'image `bull-tools` (trousseaux temporaires, jamais celui de l'utilisateur ; les étapes OpenPGP.js ne tournent que si `OPENPGPJS` désigne une copie locale, rien n'est téléchargé) :

```bash
OPENPGPJS=/chemin/vers/openpgp.min.js packages/robosats/tool/pgp_interop.sh                    # vérifie
OPENPGPJS=/chemin/vers/openpgp.min.js packages/robosats/tool/pgp_interop.sh --update-fixtures  # vérifie et remplace test/fixtures/pgp_interop/
```
