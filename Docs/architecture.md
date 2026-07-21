# Architecture

Syncorda has no virtual audio driver. It uses the public Core Audio process-tap API introduced in macOS 14.2.

```text
selected audio process(es)
  └─ CATapDescription(.mutedWhenTapped)
      └─ private aggregate device + source IOProc
          └─ 2.5-second stereo Float32 history ring
              ├─ physical output A IOProc → SRC/drift controller → device buffer
              └─ physical output B IOProc → delay cursor + SRC/drift controller → device buffer
```

The process tap mutes the selected app's ordinary route. Syncorda then owns the selected audio stream and writes it to each target device directly. Each renderer has:

- its own Core Audio device callback;
- its own source-timeline cursor;
- a configurable extra-delay cursor offset;
- linear sample-rate conversion from the tap rate to the device rate;
- bounded correction for independent device-clock drift;
- preallocated Float32 scratch buffers and lock-free counters in the audio callback.

This is why Syncorda can delay Bluetooth without delaying the MacBook speakers. A macOS Multi-Output Device and a stacked aggregate do not expose independently delayed source cursors.

## Timing model

`extraDelayMilliseconds` is intentionally one-directional: a positive value delays that named output. The renderer initially starts at:

```text
source write cursor - 30 ms preroll - user extra delay
```

The short preroll avoids callback-start underruns. The history buffer is at least 96,000 source frames and at least 2.5 seconds; that comfortably covers the MVP's 1 second maximum manual offset and output jitter.

Automatic acoustic calibration is deliberately out of scope. It would require a microphone test signal, receiver/room measurement, and policy around the user's microphone permission. Manual output delay is deterministic and scriptable now.

## Control plane

`SyncordaApp` hosts a per-user Unix socket at `/tmp/syncorda-<uid>.sock`. Both the GUI and `syncordactl` call the same `SyncordaService`, so there is one route state, one profile store, and one source of truth.

The protocol is newline-delimited JSON and only listens on the local Unix socket. It is not exposed on the network.

## Known MVP limits

- Source selection currently chooses one active Core Audio process. Chrome's active audio is usually a `com.google.Chrome.helper` process, which Syncorda resolves when given `com.google.Chrome`.
- Float32 linear PCM output devices are supported in this first renderer. macOS exposes the tested built-in and Bluetooth devices in this format. A future AudioConverter-based output format adapter can cover more exotic hardware.
- Roku/AirPlay support depends on whether macOS offers a normal writable Core Audio output for that receiver. Syncorda enumerates such devices, but compatibility must be tested per receiver.
- Device enable/disable and source changes restart the route. Delay, gain, and mute can update live.
