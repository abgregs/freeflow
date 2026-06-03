# decisions/

ADR-style records: a decision was *taken* (or, more often here, *not taken*) for a reason that needs to outlive the conversation. Read these before re-suggesting a refactor — the friction that would have justified it is usually catalogued in the **Revisit if** section.

- [0001-defer-cycle-protocol-seams.md](0001-defer-cycle-protocol-seams.md) — keep concrete cycle collaborators + `skip*ForTesting` flags instead of extracting `Transcriber` / `AudioCapture` / `HotkeyInput` protocols; revisit when a second adapter appears or skip flags spread further.
