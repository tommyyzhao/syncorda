# CLI reference

`syncordactl` is intentionally usable from a terminal, script, or agent environment.

```text
syncordactl sources list [--json]
syncordactl outputs list [--json]
syncordactl start --source BUNDLE_OR_PID --output DEVICE_UID[=DELAY_MS] [--output …]
syncordactl set-delay --output DEVICE_UID --milliseconds DELAY_MS
syncordactl set-volume --output DEVICE_UID --percent 0..100
syncordactl status [--json]
syncordactl stop
syncordactl profile save NAME --source BUNDLE_OR_PID --output DEVICE_UID[=DELAY_MS] [--output …]
syncordactl profile apply NAME
```

The command `outputs list` is authoritative: pass its `uid` verbatim to every other command. Quoting is needed when a UID contains shell-special characters.

`--source` accepts an exact process ID or a bundle identifier. Passing `com.google.Chrome` selects an active Chrome child process when one is producing audio.

The delay suffix is optional and uses milliseconds. A positive number means “delay this device.” Delay is clamped to `0…1000` ms.

All status commands return stable JSON with `--json`, including each renderer's device name, effective delay, underrun-frame count, and rendered-frame count.
