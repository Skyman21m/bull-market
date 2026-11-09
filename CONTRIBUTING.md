# Contribuer à Troc

## Mode de travail

1. **Un ticket d'abord.** Toute tâche part d'un [ticket](https://github.com/Skyman21m/troc/issues), rattaché à un jalon (phase).
2. **Une branche par tâche**, créée depuis `main` : `feat/p2p-…`, `fix/…`, `infra/…`, `docs/…`, `spike/…` (vérification jetable).
3. **Commits** au format [Conventional Commits](https://www.conventionalcommits.org/) (`feat(p2p): …`, `fix(p2p): …`), petits et atomiques. Pas de trailer `Co-Authored-By`.
4. **Une pull request par tâche** vers `main`, avec `Closes #<ticket>`, en suivant le modèle proposé.
5. **Avant fusion** : le statut `CI` est vert (analyse, garde-fous, tests unitaires), l'APK de debug se compile, et la PR a été relue par un relecteur indépendant (un agent sans contexte, ou une personne qui n'a pas écrit le code). Les conversations sont résolues.
6. **Personne ne pousse directement sur `main`.** Pas de force-push.
7. **La fusion** est faite par le propriétaire du dépôt ou par délégation de sa part. Son accord explicite reste requis pour toute version ou diffusion publique, tout changement des réglages du dépôt, et tout changement de nom, de licence ou d'architecture.

Les règles de code sont celles du dépôt d'origine : lire [AGENTS.md](AGENTS.md) avant d'écrire du code (toujours `fvm`, `make analyze` et `make checks`, pas de couleurs ni de textes en dur, rien de nouveau dans `lib/core`, `FEATURES.md` à jour). Le code P2P vit dans `lib/features/p2p/`.

## Récupérer les mises à jour de Bull Bitcoin

`develop` est le miroir de Bull et n'est jamais modifiée ici.

1. Mettre `develop` à jour : bouton « Sync fork » sur GitHub, ou en ligne de commande. La poussée n'accepte qu'une avance rapide, et le jeton utilisé doit avoir le droit `workflow`, car Bull modifie ses workflows.
   ```bash
   git remote add upstream https://github.com/SatoshiPortal/bullbitcoin-mobile.git   # une seule fois
   git fetch upstream
   git push origin refs/remotes/upstream/develop:refs/heads/develop
   ```
2. Ouvrir une pull request `develop → main` avec l'étiquette `upstream-sync`. S'il y a des conflits, les résoudre dans une branche `sync/AAAA-MM-JJ` créée depuis `main` dans laquelle on fusionne `develop`.
3. CI verte et relecture, comme pour toute PR.
4. Fusionner par **commit de fusion**, jamais par squash ni rebase, pour conserver l'historique de Bull.

Sur la PR `develop → main`, ne jamais cliquer « Update branch » ni résoudre les conflits dans l'éditeur en ligne : cela écrirait dans `develop` et casserait le miroir.

Fichiers propres à Troc, pour lesquels on garde notre version en cas de conflit : `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `NOTICE.md`, `.github/`. Si Bull modifie son fichier `LICENSE`, on garde le nôtre et on reporte son changement dans `LICENSE-BULL`.

## Sécurité

Ne jamais mettre de phrase de récupération, clé privée, PIN, jeton ou autre secret dans un ticket, une PR, un journal ou un jeu de test. Les failles se signalent en privé : voir [SECURITY.md](SECURITY.md).

## Licence des contributions

En contribuant, vous acceptez que votre contribution soit distribuée sous AGPL-3.0 (voir [NOTICE.md](NOTICE.md)).
