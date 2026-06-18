# Conventions: Anti-Patterns

Explicit "do not do this" list, with the why. Each entry exists because the pattern looks reasonable in isolation and has a sharp edge that has bitten this kind of app before.

Some entries below are marked **structurally impossible** — the architecture makes them not just forbidden but unreachable. They're kept in this doc so a contributor encountering an unfamiliar piece of code understands the rule that shaped its design.

## 1. Compile-time constants for user-facing behavior

**Don't:** put a user-facing setting (activation key, mode, double-tap window, dictionary terms) in `Constants.swift` as a `static let` and call that "configurable."

**Do:** declare it as a `SettingKey` on the [`Settings`](../architecture/settings-store.md) namespace, default sourced from `Constants`. SwiftUI binds with `@AppStorage(Settings.x.name)`; non-SwiftUI code uses `store.value(for: Settings.x)`. See [../architecture/configuration.md](../architecture/configuration.md).

**Why:** "configurable via recompile" is not configurable. A user installing the signed `.dmg` cannot edit a `.swift` file. If a setting belongs in Settings, it belongs in `SettingsStore` from day 1, not as a "future improvement."

## 2. Lying permission checks — **structurally impossible**

**The shape that was forbidden:** `checkAccessibility()` falls back to `checkInputMonitoring()` when Accessibility status is uncertain, returning `true` from one when only the other is actually granted.

**Why this can't happen in the current design:** there is no shared `PermissionManager` returning booleans. Each permission is owned by a [`Capability`](../architecture/capabilities.md) that returns `CapabilityStatus` of `.granted` / `.denied` / `.unknown`. There is no path that lowers `.unknown` to `.granted` by consulting a different capability. And the action gated by each capability (e.g., `CGEvent.post`) is *only callable through that capability* — so even if the status were wrong, the action would refuse.

**If you find yourself writing a permission check outside a capability**, that's the regression. The fix is to extend the existing capability, not to add a parallel check elsewhere.

## 3. Bespoke `build.sh` that bypasses bundle metadata

**Don't:** hand-roll an `.app` assembly script that copies the binary into `Contents/MacOS/` and signs it, without also copying `Info.plist` into `Contents/` and passing `--entitlements` to `codesign`.

**Do:** prefer `xcodebuild` for release builds. If a hand-rolled script is necessary (e.g., for local dev installs), the script must:

1. Copy `Info.plist` into `Contents/Info.plist`.
2. Verify with `codesign -dv` that the resulting bundle reports the expected `Identifier=com.freeflow.app`.
3. Sign with `--entitlements <path>` so disabled-sandbox + audio-input capabilities are applied.
4. Fail loudly if any of the above is missing.

**Why:** a bundle without a valid `CFBundleIdentifier` is unidentifiable to TCC. macOS may accept it for *reading* events (Input Monitoring) but silently refuse to let it *post* events (Accessibility). The failure mode used to be invisible — no error, no log, no user feedback. In the current design, [`AccessibilityCapability`](../architecture/capabilities.md) includes a silent-no-op detector that catches this and reports `.denied`, opening onboarding. Even so, do not rely on the detector — produce a valid bundle in the first place. See [../architecture/distribution.md](../architecture/distribution.md).

## 4. Logging user content, or trusting an opaque error string

**Don't:** interpolate user content (transcribed text, dictionary terms) into a log line at *any* privacy level. And don't log a third-party/OS `error.localizedDescription` `privacy: .public` raw — you don't control what it contains across OS and library versions.

**Do:** keep user content out of the format string entirely — log a `.count` or length, never the value. Log error strings `privacy: .public` (so the failure *reason* survives in field bug reports) but pass them through `LogRedaction.redactUserPaths(_:)` first, which strips `/Users/<name>` paths that would otherwise leak the macOS account name. See [logging.md](logging.md).

**Why:** logs get shared — users paste `log show` output into public issues. The protection for user content is *omission*: there's no `privacy:` flag to get wrong because the text is never in the line. The residual leak — a home path inside an opaque framework error — is closed deterministically at the source by `LogRedaction`, not by a build-mode flag that only one of six error logs ever adopted and that the non-developer users who actually file logs (running the signed release) could never toggle. See [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md).

## 5. Dead manager classes

**Don't:** create a `*Manager` class because the architecture diagram has a box labeled "Manager." Don't keep one around once it's been superseded.

**Do:** delete it. A manager class that no other code instantiates is documentation lying about how the app works. Future contributors will read it, model it as part of the architecture, and waste time reasoning about the wrong system.

**Why:** code is the source of truth. A class that exists but is never used signals either an incomplete refactor (finish it) or vestigial scaffolding (delete it). Either way, the resolution is action, not letting it sit.

## 6. Onboarding that only fires on hard failure — **structurally impossible**

**The shape that was forbidden:** showing `OnboardingView` only when `HotkeyManager.start()` returns `false`. The result is that an app missing only Accessibility (but with Input Monitoring granted) launches normally, the user tries to dictate, no text appears, and onboarding never opens.

**Why this can't happen in the current design:** the onboarding gate is `[any Capability].allSatisfy { $0.status == .granted }`, not "did the hotkey start succeed." Adding a new permission means adding a new capability, which automatically participates in onboarding. There is no path that launches the app while a required capability is not `.granted` without showing onboarding.

## 7. Mid-cycle configuration restart — **structurally impossible**

**The shape that was forbidden:** an external observer calls `HotkeyManager.restart()` while `FreeFlowSession.currentState != .idle`, tearing down the event tap mid-recording and dropping the audio buffer.

**Why this can't happen in the current design:** there is no public `restart` method, and *nothing recreates the event tap to apply a settings change.* [`FreeFlowSession`](../architecture/free-flow-session.md) is the only consumer of `SettingsStore` activation publishers; it inspects its own state and either applies the change **in place** (when idle, or live during a tap-mode recording) or defers it (a Hold recording or `.processing`). Applying in place is a keycode/mode swap on the one always-running tap — no `tapCreate`, no teardown, no dropped buffer — so even the live mid-recording path cannot reproduce the forbidden shape. The Settings UI cannot reach past the session, and the only `CGEvent.tapCreate` call site is `InputMonitoringCapability` at startup. See [../architecture/configuration.md](../architecture/configuration.md) and [../architecture/threading-invariant.md](../architecture/threading-invariant.md).

## 8. Inline `UserDefaults` key string literals outside `Settings.*`

**Don't:** write `UserDefaults.standard.object(forKey: "activationKeyCode")` or `@AppStorage("activationKeyCode")` anywhere except in the `Settings.*` declaration and its matching `@AppStorage(Settings.x.name)` form.

**Do:** declare every key as a `SettingKey` on the `Settings` namespace. Reference the name via `Settings.x.name` so a typo is a compile error rather than a silent drift.

**Why:** two string literals for the same key — one in `SettingKey`, one in `@AppStorage` — will drift apart. When they do, SwiftUI and `SettingsStore` are looking at different keys, the publisher doesn't fire on UI changes, live-apply silently breaks. See [../architecture/settings-store.md](../architecture/settings-store.md).

## Related

- [logging.md](logging.md) — the privacy-redaction rule
- [../architecture/permissions.md](../architecture/permissions.md) — what each permission enables
- [../architecture/capabilities.md](../architecture/capabilities.md) — the layer that makes #2, #6, #7 structurally impossible
- [../architecture/configuration.md](../architecture/configuration.md) — the live-apply contract
- [../architecture/settings-store.md](../architecture/settings-store.md) — the typed-key contract referenced by #1 and #8
- [../architecture/distribution.md](../architecture/distribution.md) — what a valid bundle looks like
