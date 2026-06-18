## Build

Always build the app with `scripts/release.sh` — there is no separate dev build script.

- **Local / testing**: `SKIP_NOTARIZE=1 ./scripts/release.sh` — Developer ID signed with hardened runtime, notarization skipped. Use this for every local build. Developer ID signing gives a durable Accessibility (TCC) grant across rebuilds; ad-hoc signing does not.
- **Distribution**: `NOTARY_PROFILE=… ./scripts/release.sh` (or `NOTARY_APPLE_ID` + `NOTARY_PASSWORD`) — full notarize + staple.

Output bundle: `dist/QuickRun.app`. Bundle assembly is shared in `scripts/lib.sh`.

## Release (Homebrew cask)

Versions are tagged on `master` and shipped via the `sunfmin/tap` cask. Released
locally — there is no release CI.

- **Version source**: `scripts/lib.sh` — `SHORT_VERSION` / `BUILD_VERSION` (both
  env-overridable). Bump these in a `Release X.Y.Z` commit; nothing else hardcodes
  the version (README points at "latest release").
- **Notary profile**: `QuickRunNotary` (notarytool keychain profile). Distribution
  builds use `NOTARY_PROFILE=QuickRunNotary ./scripts/release.sh`.
- **Asset name matters**: the cask url is
  `…/releases/download/v#{version}/QuickRun-#{version}.dmg`, but `release.sh`
  outputs `dist/QuickRun.dmg`. Copy it to `dist/QuickRun-<version>.dmg` before
  uploading, or the cask 404s.
- **Cask**: `sunfmin/homebrew-tap` → `Casks/quickrun.rb`. Bump `version` and
  `sha256` (`shasum -a 256` of the versioned dmg).

Steps: bump `lib.sh` + commit → `NOTARY_PROFILE=QuickRunNotary ./scripts/release.sh`
→ `cp dist/QuickRun.dmg dist/QuickRun-<v>.dmg` → `git push` + `git tag v<v>` + push tag
→ `gh release create v<v> dist/QuickRun-<v>.dmg` → bump cask version + sha256 → verify
the published asset's sha matches the cask.

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, default label strings (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
