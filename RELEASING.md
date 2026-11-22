# Releasing ShowItems

Maintainer notes. The release pipeline is `.github/workflows/release.yml`.

## How the pipeline works

- It runs on a push of a `v*` tag and on manual dispatch.
- Every job runs only when the repository variable `RELEASE_ENABLED` is exactly `true`. Until it is set, tag pushes and manual runs only show skipped jobs. The pipeline is disabled by default.
- Jobs: `version` (reads `vMAJOR.MINOR.PATCH` from the tag), `bundle` (sets `## Version:` in the toc and builds `ShowItems-<version>.zip`), `release` (creates the GitHub release with the zip), `curseforge` (uploads the zip, optional).
- The zip contains the addon folder at its top level (`ShowItems/ShowItems.toc`), ready to extract into the AddOns folder.

## Enable

```
gh variable set RELEASE_ENABLED --body true
```

## Disable again

```
gh variable delete RELEASE_ENABLED
```

## Publish to CurseForge (optional)

```
gh secret set CF_API_KEY
gh variable set CF_PROJECT_ID --body <id>
gh variable set CF_GAME_VERSION_ID --body <id>
```

Instead of `CF_GAME_VERSION_ID` you can set `CF_GAME_VERSION --body <name>`, the pipeline then looks the id up by name. Without `CF_API_KEY`, `CF_PROJECT_ID` and a game version the `curseforge` job logs a warning and uploads nothing.

The CurseForge game version for toc `## Interface: 16001` must be looked up at https://wow.curseforge.com/api/game/wow/versions. It has not been verified.

## Release a new version

1. Bump `## Version:` in `ShowItems/ShowItems.toc`.
2. Add an entry to `CHANGELOG.md`.
3. Commit and push to `main`.
4. `git tag vX.Y.Z`
5. `git push origin vX.Y.Z`
6. Check the run with `gh run list --limit 1`, then `gh release view vX.Y.Z` (it must list a `.zip` asset).

The tag must be new and higher than the previous one. Never force-push or retag.
