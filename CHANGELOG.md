# Changelog

All notable user-facing changes are documented here.

## [Unreleased]

### Added

- Release-readiness documentation, project governance, CI, and hardware compatibility protocol.
- The selected signal-to-two-speakers application icon, packaged in the app bundle.
- A redesigned native macOS control surface with wide sliders, exact numeric fields, and steppers for per-output volume and delay.

### Changed

- Established Syncorda’s app, CLI, local socket, bundle identifier, automation, and release artifact namespaces.
- Local control socket is restricted to its owning macOS user.
- GUI now reconciles externally initiated CLI route updates without resetting local edits.

### Fixed

- A fast output now waits for the process-tap pre-roll rather than advancing into missing timeline frames at startup.

## [0.1.0-alpha.1] - 2026-07-20

### Added

- Driverless Core Audio process-tap routing for one app to multiple local outputs.
- Per-output manual delay, volume, enable/mute behavior, profiles, SwiftUI controls, and `syncordactl`.
