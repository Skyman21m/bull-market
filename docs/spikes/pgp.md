# Spike 3 : PGP du robot RoboSats en Dart

Rédigé le 10/11/2026. Code : paquet `packages/robosats` (Dart pur, sans Flutter, sans réseau). Référence : RoboSats au commit `ff1998c`. Note de préparation : `preparation-identite-et-pgp.md`, partie B (dossier du projet).

## Résumé

1. Le paquet sait maintenant fabriquer la clé PGP d'un robot, la relire, signer une facture ou une adresse, et chiffrer, signer, déchiffrer et vérifier un message de chat.
2. **GnuPG, le moteur des coordinateurs, accepte tout ce que le code produit, et le code lit tout ce que GnuPG produit.** C'est vérifié dans les deux sens avec GnuPG 2.4.4, en rejouant les appels du coordinateur, par un script relançable.
3. La clé produite a exactement la même structure que la clé la plus récente du dépôt RoboSats, faite par l'app officielle : un coordinateur ne peut pas distinguer Troc de l'app officielle par la forme de la clé.
4. Les clés des 3 robots de test du dépôt, faites par l'app officielle, sont lues et déverrouillées avec leur token.
5. **Non prouvé : la lecture de nos messages par OpenPGP.js**, la bibliothèque de l'app officielle. Aucune copie d'OpenPGP.js n'existe sur cette machine et l'installation était exclue. Voir la matrice.
6. La bibliothèque recommandée, `dart_pg` 2.0.0, a trois défauts gênants pour RoboSats, constatés en l'exécutant. Elle est gardée pour une seule tâche (l'enveloppe chiffrée du chat) ; les clés et les signatures sont écrites par le paquet. Décision à confirmer par le propriétaire : voir « Bibliothèque ».
7. Rien n'a été envoyé à un coordinateur.

## Bibliothèque

**Constats sur `dart_pg` 2.0.0** (code lu dans le cache pub, puis exécuté) :

| Affirmation de la note | Constat |
|---|---|
| Dart pur, licence BSD-3-Clause | confirmé (`LICENSE` du paquet) |
| Dépend de `pinenacl`, `pointycastle`, `sign_dart` | confirmé ; `sign_dart` amène en plus `sha3` |
| 2.1.0 exige `pointycastle ^4` | confirmé par `pub get` : « dart_pg 2.1.0 depends on pointycastle ^4.0.0 […] version solving failed » |
| Clé ed25519 + cv25519 en v4, date de création réglable | confirmé ; GnuPG importe la clé produite |
| En-tête `Hash: SHA512`, fins de ligne `\n` | confirmé |
| Protection S2K comme OpenPGP.js | S2K identique, mais AES-128 par défaut au lieu d'AES-256 (réglage global) |

Ce que la note n'avait pas vu :

1. **Marque dans chaque signature.** `dart_pg` ajoute à toute signature v4 une notation `salt@notations.dart-pg.org` avec une valeur aléatoire (`lib/src/packet/signature.dart:188-192`, `lib/src/packet/signature/notation_data.dart:21`). Chaque facture signée et la clé elle-même désigneraient Troc au coordinateur, et rien n'est reproductible. Non désactivable.
2. **Aléa non injectable.** Le générateur est un champ statique privé (`lib/src/common/helpers.dart:24`). Impossible d'écrire un test déterministe de génération de clé.
3. **Deux erreurs sur les zéros de tête**, constatées par exécution : une clé Ed25519 dont la graine commence par un octet nul est illisible (1 clé sur 256, exception « SigningKey must be created from a 32 byte seed ») ; une signature dont R ou S commence par un octet nul est rejetée (31 signatures valides sur 3 000 dans l'essai, soit environ 1 sur 100). Un robot restauré sur 256 serait inutilisable, et un message de chat sur 100 serait affiché « signature invalide ».
4. Auto-signature différente de celle d'OpenPGP.js (préférences, « features » `0b` au lieu de `01`, ordre), en-têtes `Version:` et `Comment:` dans l'armure, lecture des clés dépendante de l'horloge du téléphone, types utiles non exportés par l'interface publique.

**Décision prise dans le spike.** Le paquet écrit et lit lui-même les clés, les signatures et l'armure (environ 1 300 lignes dans `lib/src/pgp/`, commentaires compris), en s'appuyant sur des primitives existantes : `pinenacl` (Ed25519, X25519), `pointycastle` (AES) et `crypto` (SHA). `dart_pg` ne sert plus que dans un fichier, `lib/src/pgp/message_cipher.dart`, pour l'enveloppe chiffrée d'un message : échange de clé ECDH (RFC 6637), bloc chiffré avec contrôle d'intégrité, décompression. Aucun type de `dart_pg` ni de `pinenacl` ne sort du paquet.

**Autres voies de la note.** `openpgp` (binaires Go) et `pgp_dart` (Sequoia, 0.0.1) n'ont toujours pas de date de création réglable : écartées. Une liaison Rust maison reste le repli lourd. Écrire tout le sous-ensemble soi-même est en pratique à 150 lignes près de ce qui est fait.

**Question pour le propriétaire.** Retirer complètement `dart_pg` (et avec lui `sign_dart` et `sha3`) demanderait d'écrire environ 150 lignes de plus pour l'enveloppe chiffrée. Gain : une grosse dépendance de moins, mainteneur unique, 18 000 lignes dont nous utilisons une petite partie, et un chiffrement du chat entièrement testable de façon déterministe. Coût : plus de code de sécurité écrit à la main. Le spike a gardé `dart_pg` pour rester au plus près de la recommandation.

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
| Dart → GnuPG 2.4.4 | **prouvé** | `tool/pgp_interop.sh` : import de la clé publique (`imported: 1`), date de création et identifiant lus, ré-export, import de la clé privée sans phrase de passe (`secret keys imported: 1`), `--list-packets` identique à `tests/robots/3/enc_priv_key` hors valeurs propres à la clé, vérification de la facture signée (`VALIDSIG`, EdDSA, SHA-512, empreinte primaire), extraction du texte par le code Python du coordinateur, signature par GnuPG avec notre clé privée et le token, déchiffrement du chat par le pair et par notre clé (`DECRYPTION_OKAY`, `GOODMDC`, bonne signature datée de la veille) |
| GnuPG 2.4.4 → Dart | **prouvé** | même script : clé publique ré-exportée par GnuPG, clé ed25519/cv25519 générée par GnuPG, texte signé en clair par GnuPG, message compressé, chiffré et signé par GnuPG ; plus `tests/robots/1/signed_message` du dépôt |
| OpenPGP.js → Dart, clés | **prouvé pour les clés** | `tests/robots/{1,2,3}/enc_priv_key` : lues, déverrouillées par le token, appariées à `pub_key`, identifiant égal à `RoboSats ID <hash_id>`, utilisées pour signer et pour le chat. La note les attribue à OpenPGP.js d'après leur encodage |
| OpenPGP.js → Dart, messages | **non prouvé** | aucun message chiffré ni signature d'OpenPGP.js dans le dépôt |
| Dart → OpenPGP.js | **non prouvé** | aucune copie d'OpenPGP.js sur la machine. Indice seulement : même structure de clé que l'app officielle, et GnuPG lit tout |
| GnuPG 2.2 (image officielle des coordinateurs) | **non prouvé** | pas d'image Debian bookworm en local |

Les artefacts du dernier passage du script sont dans `packages/robosats/test/fixtures/pgp_interop/`, avec la sortie de GnuPG (`gpg_transcript.txt`). Comme la génération et la signature sont déterministes, les tests vérifient à chaque exécution que le code écrit encore, à l'octet près, la clé et la facture que GnuPG a acceptées, et qu'il lit toujours ce que GnuPG a écrit. python-gnupg n'est pas installé ici : ses lignes de commande sont reproduites de mémoire dans le script.

## Écarts

Avec la note de préparation :

- **Liaison de sous-clé en SHA-512, pas SHA-256.** La note (B1.3) décrit le robot de test n° 1, de 2023. Le n° 3, de février 2025, a une liaison en SHA-512 ; c'est la seule différence. Le paquet suit le plus récent. À confirmer sur une clé faite par l'app actuelle.
- Les quatre constats sur `dart_pg` ci-dessus.

Avec la demande :

- **Rôle de `dart_pg` réduit**, et `pinenacl` déclaré en dépendance directe.
- **Aléa du chiffrement du chat non injectable** (clé de session, clé éphémère, préfixe) : il vient de `dart_pg`. La génération de clé et les signatures, elles, sont déterministes.
- **Antidatage de 24 h exactement.** L'app officielle retire un jour de calendrier en heure locale, soit 23 h ou 25 h les deux jours de changement d'heure. Sans effet sur la règle des 12 heures.
- **Garde-fous ajoutés** : `signCleartext` refuse un texte que le découpage du coordinateur ne rendrait pas intact (vide, espaces autour, ligne commençant par un tiret) ; `encryptChatMessage` refuse un texte contenant le token.
- **Tests d'abord, en partie seulement.** Le premier jet du code interne a été écrit avant ses tests ; les tests ont été écrits avant sa première exécution, et les cas limites ajoutés ensuite l'ont été test d'abord.
- **Limites assumées** : seules les clés v4 ed25519 + cv25519 sont acceptées (un pair qui aurait fourni une clé RSA par l'API serait illisible) ; ni expiration ni révocation ne sont évaluées ; pas de contrôle d'horloge sur les signatures reçues.

## Risques

| Risque | Parade |
|---|---|
| OpenPGP.js refuse nos messages ou nos signatures | à tester en premier face à l'app officielle ; la disposition des signatures de données (sous-paquets 2, 16, 33) est déduite des signatures de clé, pas observée |
| `dart_pg` : un seul mainteneur, 2.0.0 du 11/12/2024 (journal du paquet), dernière version 2.1.0 du 08/04/2025 d'après la note, aucun audit connu, figé à 2.0.0 | usage réduit à un fichier, remplaçable |
| `pinenacl` 0.6.0 : portage de TweetNaCl, pas d'audit connu | vecteurs RFC 8032 et RFC 7748 dans les tests |
| Aucun code Dart n'est à temps constant | inhérent au Dart pur ; la clé privée chiffrée est de toute façon chez le coordinateur |
| Secrets en mémoire : graine, scalaire et token restent dans des objets que le ramasse-miettes ne remet pas à zéro, et `dart_pg` en fait des copies | `UnlockedRobotPgpKey` à garder le temps d'une tâche ; rien n'est écrit sur disque ni journalisé ; `toString()` et échecs sans secret |
| Code de sécurité écrit à la main | recoupé par GnuPG dans les deux sens ; le contrôle de garde des clés ne le voit pas : même vigilance que pour `packages/secrets` |
| Durée du déverrouillage (32 Mio de SHA-256) | 0,3 s mesuré sur ce poste ; téléphone non mesuré ; à appeler hors du fil d'interface, une fois par lot de messages |
| Clé de pair malveillante fournie par le coordinateur | inhérent à RoboSats : le coordinateur distribue les clés |

## Dépendances

`pubspec.lock` gagne quatre paquets et n'en modifie aucun ; `make deps` (verrouillage strict) passe.

| Paquet | Version | Licence | Rôle |
|---|---|---|---|
| `dart_pg` | 2.0.0 | BSD-3-Clause | enveloppe chiffrée du chat |
| `pinenacl` | 0.6.0 | MIT | Ed25519, X25519 ; requis aussi par `dart_pg` |
| `sign_dart` | 1.0.0 | BSD-3-Clause | amené par `dart_pg`, jamais atteint par notre code |
| `sha3` | 0.2.1 | MIT | amené par `sign_dart`, jamais atteint |

## Reste à tester

1. **Face à l'app officielle** : elle déchiffre un message de Troc et valide sa signature ; Troc déchiffre un message de l'app. Idem pour une facture signée.
2. **Face à un coordinateur de test** : création du robot avec une clé de Troc, `update_invoice` avec une facture signée, envoi et relecture d'un message de chat, restauration du robot avec le seul token.
3. GnuPG 2.2.x : relancer `tool/pgp_interop.sh` sur une Debian bookworm.
4. Temps de génération et de déverrouillage sur un téléphone Android milieu de gamme.
5. Limite de taille de `PGP_message` : le modèle annonce 5 000 caractères (`chat/models.py:87`), sans contrôle visible dans le sérialiseur.
6. Les contrôles de tout le projet (`make analyze`, `make unit-test`, `make custody-check`) demandent le code généré, absent en local : seuls leurs équivalents sur le paquet ont été lancés.

## Relancer

Tests du paquet, depuis la racine du dépôt :

```bash
docker run --rm -v "$PWD":/work -w /work -v troc-pub-cache:/home/bull/.pub-cache bull-tools \
  bash -c 'make deps && cd packages/robosats && fvm dart test'
```

Recoupement avec GnuPG, sur une machine qui a GnuPG et l'image `bull-tools` (trousseaux temporaires, jamais celui de l'utilisateur) :

```bash
packages/robosats/tool/pgp_interop.sh                    # vérifie
packages/robosats/tool/pgp_interop.sh --update-fixtures  # vérifie et remplace test/fixtures/pgp_interop/
```
