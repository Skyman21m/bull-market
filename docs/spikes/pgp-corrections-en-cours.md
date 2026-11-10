# Corrections PGP après revue de sécurité : note de suivi

Note de travail, à supprimer avant fusion. Branche `spike/pgp`.

## Fait (commit b931d246a, 380 tests verts, analyse, format, `dart fix`, contrôle de garde au vert sur le paquet)

- Constat 1 (déni de service) : `dart_pg` retiré ; enveloppe (ECDH RFC 6637, AES key wrap RFC 3394, bloc chiffré v1 et contrôle MDC), lecture bornée et décompression plafonnée écrites dans le paquet ; bornes dans `lib/src/pgp/limits.dart` ; aléa du chiffrement injectable (`encryptChatMessageWith`).
- Constat 2 (clé hostile) : paramètres KDF et point X25519 d'ordre faible refusés à la lecture (`PgpKeyUnsupported`).
- Constat 4 (dates) : horloge injectable ; signature future, expirée, antérieure à la clé ou faite hors validité de la clé refusée ; en-tête `Hash:` exigé ; texte canonique renvoyé ; `PgpKeyOutOfDate` au chiffrement.
- Constat 5 : compteur S2K plafonné à 32 Mio.
- Constat 6 : `SecretKeys` en classe masquée, tampons transitoires effacés, aléa injecté réservé à des variantes `@visibleForTesting` (`RobotPgpKey.generateWith`, `encryptChatMessageWith`, `GarageKey.generateWith`).
- Constat 3 : un test par mutant survivant, avec paquets re-signés (`test/support/craft.dart`, `test/pgp/hostile_key_test.dart`, `hostile_message_test.dart`, `signature_packets_test.dart`).
- `pubspec.lock` : `dart_pg`, `sign_dart`, `sha3` retirés par `fvm flutter pub get`.
- `tool/pgp_interop.sh` relancé pour de vrai avec GnuPG 2.4.4 et OpenPGP.js 5.11.3 (`OPENPGPJS=…/openpgp.min.js`) : tout passe dans les deux sens, structure des messages identique à celle d'OpenPGP.js ; jeux d'essai régénérés.

## En cours

- Relance des mutants : générateur `scratchpad/mkmut2.py` (75 mutants), résultats dans `scratchpad/mut2/result.log` (une ligne par mutant ; « All tests passed » = survivant). Le lanceur remplace un fichier de `packages/robosats/lib` le temps de chaque mutant : s'il est interrompu, `git status` montre un fichier modifié sous `lib/`, à rétablir par `git checkout -- packages/robosats/lib`.

## Reste

- Mesures temps et mémoire sur les entrées de déni de service du relecteur.
- Constat 7 : fait (commit ab339fba3), reste à y reporter les résultats des mutants et les mesures.
- Supprimer cette note.

## Résultats à ne pas perdre

- La clé et la facture signée de référence n'ont pas changé d'un octet (fichiers `troc_pub_key`, `troc_enc_priv_key`, `troc_invoice_signed.asc` inchangés).
- OpenPGP.js 5.11.3 n'applique aucune tolérance sur une signature datée du futur (`this.created > now`).
