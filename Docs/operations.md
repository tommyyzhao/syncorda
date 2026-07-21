# Operating Syncorda

This guide covers normal local operation and safe diagnostics for the current
alpha. It complements the [CLI reference](cli.md), [architecture notes](architecture.md),
and [compatibility matrix](compatibility.md).

## First use

Build and launch the application bundle:

```sh
./scripts/build-app.sh
open dist/Syncorda.app
```

Starting the first route prompts macOS for **System Audio Recording** permission.
That permission is required because Syncorda captures the selected app through
the public Core Audio process-tap API. Syncorda does not record to disk or send
audio over the network. See [privacy notes](privacy.md).

The service listens only on the per-user Unix socket:

```text
/tmp/syncorda-<uid>.sock
```

The bundled `syncordactl` and the SwiftUI app control the same service. Run
`syncordactl status --json` before changing a route so a diagnostic does not
unnecessarily interrupt active audio.

## Typical CLI workflow

Use device IDs discovered on the current Mac; device IDs are not portable
between machines or necessarily stable after a receiver is re-paired.

```sh
syncordactl outputs list
syncordactl sources list
syncordactl start --source com.example.Source --output DEVICE_A --output DEVICE_B=250
syncordactl set-delay --output DEVICE_B --milliseconds 250
syncordactl set-volume --output DEVICE_B --percent 70
syncordactl status --json
syncordactl stop
```

A positive value delays only the named output. Start with the faster-sounding
speaker: if Bluetooth is audible before the built-in speakers, delay Bluetooth;
if it is audible after them, delay the built-in speakers. Delay, volume, and
mute update live. Changing the source or enabling/disabling an output restarts
the route because Syncorda must construct a different renderer set.

## Safe diagnostics

1. Query `syncordactl status --json` and `syncordactl outputs list` first.
2. Confirm the source process and selected output IDs.
3. Check the macOS audio permission if a route cannot start.
4. Check the receiver in macOS Sound settings if it is absent from the output
   list. Syncorda can use only writable Core Audio devices that macOS exposes.
5. Change one live setting at a time while listening to a rhythmic source.

Do not restart Syncorda merely to inspect it. If a newly built binary must be
loaded, record the existing route first and restore it immediately after launch.

## Hardware validation

Before claiming compatibility with a new transport, validate the release bundle
rather than only a development executable:

```sh
./scripts/build-app.sh
dist/Syncorda.app/Contents/MacOS/syncordactl outputs list
```

For each device, verify discovery, start/stop, audible output, live volume,
mute, and delay. Test a Bluetooth receiver separately from the built-in speakers
when possible. Record the result in the compatibility matrix; Roku and other
AirPlay receivers remain receiver-dependent until they pass that protocol.

## Maintainer checks

Run these before handing off a change:

```sh
swift build
swift run syncordachecks
./scripts/build-app.sh
./scripts/verify-bundle.sh dist/Syncorda.app
```

`syncordachecks` is the deterministic regression suite. It covers the timeline,
per-output delay, resampling, mute behavior, profiles, protocol, and local
socket. For signing, notarization, and the release checklist, read
[releasing Syncorda](releasing.md).
