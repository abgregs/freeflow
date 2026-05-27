# Requirement: Supported Keys and Limitations

The 10 supported activation keys are listed in [activation-key-and-mode.md](activation-key-and-mode.md). This doc covers per-key behavior, known limitations, and which combinations are restricted, warned about, or accepted with caveats.

## Per-key notes

### Right Control (default)

The original default and the most "neutral" choice — rarely chorded with anything else, present on most external keyboards, fires `flagsChanged` reliably. Caveat: **MacBook built-in keyboards have no Right Control key.** Users on a MacBook with no external keyboard must pick a different key.

### Left Control

Reliable. May conflict with apps that use Left Control + key for shortcuts; this is unlikely to interfere because we listen to the modifier alone, but if the user is mid-chord with another key the activation may fire unexpectedly.

### Right / Left Option

Reliable. Common alternative to Right Control on MacBooks. Same chord caveat as Left Control.

### Right / Left Command

Reliable. Cmd held alone is unusual in typical typing, so misfire risk is low. Caveat: holding Cmd briefly enters "spring-loaded" mode in some apps (Finder, Dock); for very long holds this may produce side effects.

### Right / Left Shift

Reliable. Caveat: macOS accessibility features (Sticky Keys, Slow Keys) interact with Shift. Users with those enabled should test before committing to Shift.

### Caps Lock

**Hold mode is broken.** macOS toggles the `.maskAlphaShift` flag on press rather than reflecting held state. Pressing Caps Lock sets the flag; pressing again clears it — regardless of physical hold. The Hotkey implementation can't distinguish "still held" from "released and toggled off."

Tap modes work correctly because they fire on key-up edges, which are consistent with normal key semantics.

Settings UI shows an inline warning when Caps Lock is paired with Hold mode. The combination is not blocked — users can pick it and experience the broken behavior, by design. **Why:** an interactive warning is more discoverable than a disabled option ("why can't I pick this?"), and a determined user can choose to live with the limitation.

### Function (Fn) — keycode 63

The Fn key may not produce `flagsChanged` events on all Apple keyboards. Behavior depends on:

- **MacBook built-in keyboards**: Fn often does fire `flagsChanged`, but on newer Macs Fn is also the Globe key and is bound to system features (Dictation, emoji picker, language switching). Holding Fn alone may trigger one of those system features before the app sees it.
- **External Apple keyboards**: Magic Keyboards typically expose Fn as `flagsChanged`. Some third-party keyboards do not.

A planned Settings warning will alert the user when Fn is selected. The key is included in the picker because some users specifically want it; it is the user's responsibility to verify it works on their hardware.

## Combinations that are restricted

None are *blocked*. All 10 keys × 3 modes (= 30 combinations) are user-selectable. Two combinations show warnings:

- Caps Lock + Hold (always shown)
- Fn + anything (planned)

The principle: **inform, don't block.** The user knows their hardware better than the app does.

## Macroscopic macOS limitations

These constrain the design as a whole:

- **No way to enumerate other apps' registered hotkeys.** We cannot detect conflicts with system shortcuts or other apps' global hotkeys. The user must discover conflicts empirically. See [../conventions/anti-patterns.md](../conventions/anti-patterns.md).
- **Accessibility permission cannot be auto-granted.** macOS requires the user to manually add the app to System Settings → Privacy & Security → Accessibility. The app can only direct them there. See [../architecture/permissions.md](../architecture/permissions.md).
- **Tap-based modes have ~50–100 ms latency** versus Hold mode, because they require waiting for a complete tap (key-down + key-up) before acting. This is acceptable for a dictation use case.

## Related

- [activation-key-and-mode.md](activation-key-and-mode.md) — the full settings UI and persistence
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — why the event tap is reliable for the keys it does support
