# Compatibility matrix

Syncorda is a **local Core Audio output router**, not a Cast or AirPlay transmitter. An output appears only when macOS exposes it as a writable Core Audio device.

## Current release target

| Area | v0.1 alpha status |
| --- | --- |
| Architecture | Apple Silicon (`arm64`) release build |
| macOS | 14.2+ required for process taps |
| Source | One active Core Audio process; Chrome child processes are resolved automatically |
| Built-in output | Validated |
| Bluetooth A2DP output | Validated |
| USB / display audio | Expected; requires hardware confirmation |
| AirPlay / Roku | Enumerated when available; experimental, no compatibility promise |
| Google Cast | Not supported |
| Automatic acoustic sync | Not supported; use manual output delay |

## Qualification protocol

Before marking a device class as supported, test all of the following:

1. Start Chrome to built-in plus the target device at mismatched sample rates when possible.
2. Verify live volume, mute, and delay changes from both GUI and CLI.
3. Run for ten minutes and check `syncordactl status --json` for sustained underruns.
4. Disconnect/reconnect the target device, sleep/wake the Mac, and relaunch the source app.
5. Record the device model, macOS version, architecture, output UID/transport, and result in the issue tracker.

Never infer receiver support only from device enumeration.
