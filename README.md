# Syncorda

[![CI](https://github.com/tommyyzhao/syncorda/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tommyyzhao/syncorda/actions/workflows/ci.yml)

Syncorda is a native, open-source macOS app that routes one app's audio to multiple local output devices, with a manually configured delay and volume for every output.

**Status: v0.1 alpha.** Syncorda is tested on Apple Silicon and intended for technically comfortable early adopters. See the [compatibility matrix](Docs/compatibility.md) before relying on it for an event or critical workflow.

It is a modern, driverless alternative for the local-device portion of an Airfoil-style workflow. It uses Core Audio process taps instead of a virtual audio driver, so Chrome can be captured and muted at the source, then rendered independently to MacBook speakers, Bluetooth speakers, USB devices, and compatible local AirPlay outputs.

> Syncorda is not affiliated with Rogue Amoeba or Airfoil.

## Current MVP

- macOS 14.2+
- One source app/audio process per route (Chrome is supported, including its active helper process)
- Two or more Core Audio output devices
- Per-output enable, mute, gain, and manual `0–1000 ms` extra delay
- Independent output clocks with live linear sample-rate conversion and drift correction
- SwiftUI GUI and a local Unix-socket CLI that control the same route
- Saved profiles and JSON CLI output

Syncorda keeps all audio on the Mac. It does not implement Google Cast or an AirPlay transmitter; it uses outputs macOS already exposes as local Core Audio devices.

## Build and run

This project deliberately uses Swift Package Manager, so Xcode is not required for local development.

```sh
git clone https://github.com/tommyyzhao/syncorda.git
cd syncorda
./scripts/build-app.sh
open dist/Syncorda.app
```

The first time routing starts, macOS asks Syncorda for System Audio Recording permission. Accept that one OS prompt; afterwards, the route can be configured and controlled from the CLI without using the GUI.

For development without an app bundle:

```sh
swift build
.build/debug/SyncordaApp
```

The bundled CLI lives at `dist/Syncorda.app/Contents/MacOS/syncordactl`.

## Chrome → MacBook speakers + Kitchen Bluetooth speaker

Discover exact device IDs first:

```sh
syncordactl outputs list
syncordactl sources list
```

On the development machine this route is:

```sh
syncordactl start \
  --source com.google.Chrome \
  --output BuiltInSpeakerDevice \
  --output 38-8B-59-68-7B-5E:output=250
```

A positive delay delays only the named output. In this example it delays the Kitchen Bluetooth speaker by 250 ms, matching the observed case where Bluetooth sounds early. Use `syncordactl set-delay` while routing to adjust it live:

```sh
syncordactl set-delay --output 38-8B-59-68-7B-5E:output --milliseconds 250
syncordactl set-volume --output 38-8B-59-68-7B-5E:output --percent 70
syncordactl status --json
syncordactl stop
```

Save and reuse the route:

```sh
syncordactl profile save chrome-kitchen \
  --source com.google.Chrome \
  --output BuiltInSpeakerDevice \
  --output 38-8B-59-68-7B-5E:output=250
syncordactl profile apply chrome-kitchen
```

If `syncordactl` is launched from the app bundle it starts Syncorda's background service automatically. In an unbundled development build, run `SyncordaApp` once or set `SYNCORDA_APP_PATH=/path/to/Syncorda.app`.

## GUI

The app has a deliberately small control surface:

1. Choose the active app audio process.
2. Enable the outputs you want.
3. Set `Delay this output` in milliseconds.
4. Start routing.

Volume, delay, and mute changes apply live. Add a previously inactive output, then restart routing so Syncorda can create its physical renderer.

## Tests

```sh
swift run syncordachecks
swift build
./scripts/build-app.sh
```

`syncordachecks` is a standard-library test executable because this machine's Command Line Tools installation has neither XCTest nor Swift Testing. It tests timeline wraparound, independent delays, resampling, mute semantics, persistent profiles, the JSON protocol, and a live local-control socket round trip.

See [the architecture notes](Docs/architecture.md), [operating guide](Docs/operations.md), [CLI reference](Docs/cli.md), [privacy notes](Docs/privacy.md), [compatibility matrix](Docs/compatibility.md), [design notes](Docs/design.md), [brand record](Docs/branding.md), [contributing guide](CONTRIBUTING.md), and [security policy](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
