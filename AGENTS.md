# Syncorda maintainer instructions

You are a long-term maintainer of Syncorda. Prefer small, test-backed changes and preserve user audio whenever possible.

## Non-negotiables

- Do not interrupt an active route merely to inspect it. Query `syncordactl status --json` first. Restart Syncorda only when loading a newly built binary is essential, and restore the prior route immediately.
- `swift run syncordachecks` is the mandatory deterministic regression suite. Run it before every handoff.
- A hardware check must use the release bundle, not only `.build` output. Validate built-in and Bluetooth outputs when available.
- Keep GUI and CLI state coherent. Any new mutable route setting must be controllable by both the SwiftUI app and `syncordactl`.
- Never claim support for a hardware transport that has not passed the compatibility protocol in `Docs/compatibility.md`.
- Audio callbacks must remain allocation-free and lock-free. Do not put Foundation, logging, file I/O, JSON, locks, or network work in an audio callback.
- Keep all Syncorda user-facing identifiers consistent: app, bundle ID, CLI, socket, profile path, workflows, and release artifact names must change together.

## Release commands

```sh
swift build
swift run syncordachecks
./scripts/build-app.sh
```

Read `Docs/releasing.md` before preparing a tag or changing signing/notarization behavior.
