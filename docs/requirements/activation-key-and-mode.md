# Requirement: Activation Key and Mode

The user picks **one key** and **one mode** from Settings. Both are persisted to `UserDefaults` and applied live without restart.

## Modes

| Mode | Behavior |
|---|---|
| **Hold** (default) | Key-down → start recording. Key-up → stop and transcribe. |
| **Single Tap** | First complete tap → start recording. Next complete tap → stop and transcribe. |
| **Double Tap** | Two complete taps within `doubleTapWindowMs` (default 400 ms) → start. A single complete tap → stop. |

A "complete tap" means key-down followed by key-up. Holding the key in tap modes is treated as a single tap (no special behavior).

In Double Tap mode, stop requires only **one** tap, not another double tap. **Why:** requiring a second double-tap under time pressure is error-prone. Stopping a recording should be easy.

## Picking a key

The activation key is chosen from a fixed list of 10 modifier keys:

| Key | Keycode | `CGEventFlags` mask |
|---|---|---|
| Right Control | 62 | `.maskControl` |
| Left Control | 59 | `.maskControl` |
| Right Option (default) | 61 | `.maskAlternate` |
| Left Option | 58 | `.maskAlternate` |
| Right Command | 54 | `.maskCommand` |
| Left Command | 55 | `.maskCommand` |
| Right Shift | 60 | `.maskShift` |
| Left Shift | 56 | `.maskShift` |
| Caps Lock | 57 | `.maskAlphaShift` |
| Function (Fn) | 63 | `.maskSecondaryFn` |

Left and right variants share a flag-mask family; the implementation disambiguates by keycode, not by flag bit. See [../architecture/configuration.md](../architecture/configuration.md).

Caps Lock + Hold is explicitly warned against in Settings UI. **Why:** macOS toggles the Caps Lock flag on press rather than reflecting held state, making Hold mode unreliable. Tap modes work fine with Caps Lock. See [supported-keys-and-limitations.md](supported-keys-and-limitations.md).

## Persistence

Declared as typed keys on the `Settings` namespace (backed by `UserDefaults.standard`):

| Key | Type | Default |
|---|---|---|
| `Settings.activationKeyCode` | `Int` | `61` (Right Option) |
| `Settings.activationMode` | `ActivationMode` | `.hold` |
| `Settings.doubleTapWindowMs` | `Int` | `400` |

See [../architecture/settings-store.md](../architecture/settings-store.md) for the typed read/write API and [../conventions/persistence.md](../conventions/persistence.md) for declaration conventions.

## Live apply

[`FreeFlowSession`](../architecture/free-flow-session.md) subscribes to `store.publisher(for: Settings.activationKeyCode)` and `Settings.activationMode`. When either emits a new typed value:

- If the session is `.idle`, it asks `HotkeyManager` to switch immediately. The manager rebuilds the event tap on a fresh `com.freeflow.eventtap` thread (preserving the [threading invariant](../architecture/threading-invariant.md)).
- If the session is `.recording` or `.processing`, the new value is stored as a pending reconfiguration and applied when the cycle returns to `.idle`. The Settings UI shows no special indicator — the change just applies a moment later. See [../architecture/free-flow-session.md](../architecture/free-flow-session.md).

The deferral is structural; there is no path that lets a settings change tear down the event tap mid-cycle.

## Settings UI

The Activation section of Settings contains:

1. **Activation Key picker** — dropdown with the 10 human-readable labels above.
2. **Activation Mode picker** — segmented or list picker with the three modes; each row shows the mode name and a one-line description.
3. **Inline warnings** when applicable:
   - Caps Lock + Hold → "Caps Lock toggles on press and is unreliable in Hold mode. Switch to Single Tap or Double Tap."
   - (Future) Fn key → "Function (Fn) may conflict with the system Globe key on newer Macs."

## Related

- [supported-keys-and-limitations.md](supported-keys-and-limitations.md) — known macOS limitations per key
- [../architecture/configuration.md](../architecture/configuration.md) — how live-apply works under the hood
- [../conventions/persistence.md](../conventions/persistence.md) — UserDefaults key conventions
