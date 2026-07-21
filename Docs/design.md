# Control-surface design

Syncorda’s macOS control surface is designed for people actively tuning timing-sensitive audio routes.

## Principles

- Use standard SwiftUI controls and semantic system materials so the interface adapts to the current macOS appearance, contrast, and accessibility settings.
- Put the route state, source choice, output selection, and primary action in that order. The active task is always visible before secondary profile actions.
- Give every output an independently labeled card so its device identity, enable state, mute state, volume, and delay can be read and adjusted together.
- Pair a wide slider with an editable numeric field and a stepper. Sliders provide quick coarse adjustment; the field and stepper provide exact keyboard and pointer control.
- Apply volume, mute, enable, and delay edits immediately. There is no Apply button or hidden staged state.

## Precision and accessibility

Volume spans `0–100%` in `0.1%` increments. Delay spans `0–1000 ms` in `1 ms` increments. The editable fields have explicit accessibility labels, sliders identify their target device, and device UIDs can be selected for copying.

The interface uses system typography, controls, colors, and SF Symbols. This keeps it readable under the current macOS platform design, including its evolving visual materials, without sacrificing the clarity needed for real-time audio controls.
