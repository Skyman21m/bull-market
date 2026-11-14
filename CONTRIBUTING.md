# Contributing to Bull Market

## How we work

1. **An issue first.** Every task starts from an [issue](https://github.com/Skyman21m/bull-market/issues), attached to a milestone (phase).
2. **One branch per task**, created from `main`: `feat/p2p-…`, `fix/…`, `infra/…`, `docs/…`, `spike/…` (throwaway check).
3. **Commits** in the [Conventional Commits](https://www.conventionalcommits.org/) format (`feat(p2p): …`, `fix(p2p): …`), small and atomic. No `Co-Authored-By` trailer.
4. **One pull request per task** to `main`, with `Closes #<issue>`, following the provided template.
5. **Before merging**: the `CI` status is green (analysis, guardrails, unit tests), the debug APK builds, and the PR has been reviewed by an independent reviewer (an agent with no context, or a person who did not write the code). Conversations are resolved.
6. **Nobody pushes directly to `main`.** No force-push.
7. **Merging** is done by the repository owner or by delegation from them. Their explicit approval is still required for any public version or release, any change to the repository settings, and any change of name, license or architecture.

The code rules are those of the upstream repository: read [AGENTS.md](AGENTS.md) before writing code (always `fvm`, `make analyze` and `make checks`, no hard-coded colors or texts, nothing new in `lib/core`, `FEATURES.md` kept up to date). The P2P code lives in `features/p2p/` (package `p2p`).

## Pulling in Bull Bitcoin updates

`develop` is the mirror of Bull and is never changed here.

1. Update `develop`: "Sync fork" button on GitHub, or from the command line. The push only accepts a fast-forward, and the token used must have the `workflow` permission, because Bull changes its workflows.
   ```bash
   git remote add upstream https://github.com/SatoshiPortal/bullbitcoin-mobile.git   # only once
   git fetch upstream
   git push origin refs/remotes/upstream/develop:refs/heads/develop
   ```
2. Open a `develop → main` pull request with the `upstream-sync` label. If there are conflicts, resolve them in a `sync/YYYY-MM-DD` branch created from `main`, into which `develop` is merged.
3. Green CI and review, as for any PR.
4. Merge with a **merge commit**, never with squash or rebase, to keep Bull's history.

On the `develop → main` PR, never click "Update branch" or resolve conflicts in the web editor: that would write to `develop` and break the mirror.

Files specific to this fork, for which we keep our version in case of conflict: `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `NOTICE.md`, `.github/`. If Bull changes its `LICENSE` file, we keep ours and carry its change over to `LICENSE-BULL`.

## Security

Never put a recovery phrase, private key, PIN, token or other secret in an issue, a PR, a log or a test fixture. Vulnerabilities are reported privately: see [SECURITY.md](SECURITY.md).

## License of contributions

By contributing, you agree that your contribution is distributed under AGPL-3.0 (see [NOTICE.md](NOTICE.md)).
