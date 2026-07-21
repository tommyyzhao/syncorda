# Syncorda agent doctrine

Make the smallest verified change that preserves the user's audio.

1. Inspect first: run `syncordactl status --json`; do not interrupt an active
   route merely to inspect it. If loading a new binary requires a restart,
   record and restore the route immediately.
2. Keep audio callbacks allocation-free and lock-free: no Foundation, logging,
   file I/O, JSON, locks, or network work.
3. GUI and CLI are one control plane. Every mutable route setting must work in
   both the SwiftUI app and `syncordactl`, and live controls must not stage an
   unapplied state.
4. Treat a transport as unsupported until it passes
   [the compatibility protocol](Docs/compatibility.md). Test hardware with the
   release bundle, not just `.build` output.
5. Keep every public identifier aligned: app, bundle ID, CLI, socket, profile
   path, workflows, and release artifact names change together.
6. Before every handoff run `swift run syncordachecks`. For app, engine, or
   bundle changes also run `swift build`, `./scripts/build-app.sh`, and
   `./scripts/verify-bundle.sh dist/Syncorda.app`.

Read [architecture](Docs/architecture.md), [operations](Docs/operations.md),
and [CLI](Docs/cli.md) before changing routing behavior; read
[releasing](Docs/releasing.md) before tags, signing, or notarization. On this
machine, consult `.syncorda-local/HANDOFF.md` when present; it is gitignored and
must never be committed or hold credentials.
