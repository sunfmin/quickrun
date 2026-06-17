## Build

Always build the app with `scripts/release.sh` — there is no separate dev build script.

- **Local / testing**: `SKIP_NOTARIZE=1 ./scripts/release.sh` — Developer ID signed with hardened runtime, notarization skipped. Use this for every local build. Developer ID signing gives a durable Accessibility (TCC) grant across rebuilds; ad-hoc signing does not.
- **Distribution**: `NOTARY_PROFILE=… ./scripts/release.sh` (or `NOTARY_APPLE_ID` + `NOTARY_PASSWORD`) — full notarize + staple.

Output bundle: `dist/QuickRun.app`. Bundle assembly is shared in `scripts/lib.sh`.

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, default label strings (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
