# Planning: Runtime Security Hardening (roadmap 0006)

Outcome of the 2026-06 pre-publication security review of the runtime attack
surface: one actionable code finding, plus the accepted-by-design trade-offs
recorded so they stay deliberate rather than forgotten. The review found no
exploitable vulnerability.

## Finding: the event tap is more privileged than it needs to be

`InputMonitoringCapability` creates its tap with `options: .defaultTap`
(`InputMonitoringCapability.swift:73`) — an **active** tap, which may modify or
consume every keyboard event on the system. The callback never does either: it
returns the event unmodified. `.listenOnly` would make modification
*structurally impossible* (the same design language as the rest of the app) and
means a stalled callback cannot delay system-wide event delivery.

**Task:** create the tap with `.listenOnly`.

The change touches the event-tap module governed by the threading invariant
([../architecture/threading-invariant.md](../architecture/threading-invariant.md)),
so review the applicable conventions first (the repo's `brief` skill automates
this) and verify on-device, not just in tests:

1. **TCC interplay.** Active and listen-only keyboard taps interact differently
   with Accessibility / Input Monitoring. Confirm `tapCreate` still succeeds
   with the app's existing grants and that
   [../architecture/permissions.md](../architecture/permissions.md) stays accurate.
2. **All three activation modes** work end-to-end after the change.
3. **The `.tapDisabled*` self-re-enable path** still behaves — confirm whether
   timeout disables still occur for listen-only taps.

## Accepted trade-offs (by design — do not "fix" casually)

- **Dictations transit the system pasteboard** (a ~250 ms window plus the paste
  itself). Any process can read the pasteboard during that window, and
  clipboard-history managers will persist every dictation. **Why accepted:**
  paste-via-⌘V is the only universal insertion mechanism; AX writes were
  rejected (see "No AX-API path" in
  [../architecture/free-flow-pipeline.md](../architecture/free-flow-pipeline.md)).
  The README carries the user-facing caveat. Planned upgrade:
  [0007_transient-pasteboard-markers.md](0007_transient-pasteboard-markers.md)
  marks both writes so well-behaved clipboard managers stop recording
  dictations.
- **The model cache is trusted without verification.** WhisperKit's cache under
  `~/Documents/huggingface/` is user-writable and the app loads whatever is
  there. **Why accepted:** a same-user attacker is outside the security
  boundary (they can already keylog or exfiltrate directly), and a poisoned
  *transcription model* can only emit text the user watches get pasted.
  Transport integrity is HTTPS to Hugging Face. Optional follow-up at release
  time: pin the model revision WhisperKit downloads.
- **No sandbox.** Required for the global event tap (see
  [../architecture/distribution.md](../architecture/distribution.md)). The
  hardened runtime (`--options runtime` at sign time) compensates with library
  validation, blocking unsigned-dylib injection into the process.

## Acceptance criteria

1. The tap is created with `.listenOnly` and the three on-device verifications
   above pass.
2. [../architecture/threading-invariant.md](../architecture/threading-invariant.md)
   and [../architecture/capabilities.md](../architecture/capabilities.md) are
   updated if either describes the tap type.
3. The trade-offs above remain documented (here, or moved to an architecture
   doc if the list accretes more entries).

## Related

- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — the module the finding touches
- [../architecture/permissions.md](../architecture/permissions.md) — the TCC story to re-verify
- [0005_release-pipeline-security.md](0005_release-pipeline-security.md) — the same review's pipeline checklist
