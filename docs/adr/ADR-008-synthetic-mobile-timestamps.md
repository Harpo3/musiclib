# ADR-008 — Synthetic (Fabricated) Last-Played Timestamps for Mobile Accounting

**Date**: 2026-04-30  
**Status**: Accepted  
**Deciders**: Louis (sole maintainer)

---

## Context

MusicLib tracks `LastTimePlayed` for every track in the DSV. This value drives the library view's "last played" column and affects smart playlist ordering. When tracks are played on a mobile device via KDE Connect, no playback events are reported back to the desktop — the mobile player is opaque to MusicLib.

When the user uploads a new playlist (`musiclib-cli mobile upload`), MusicLib knows:
- Which tracks were on the previous playlist
- When that playlist was uploaded (the accounting window start)
- The current time (the accounting window end)

It does not know which tracks were played, how many times, or when.

---

## Decision

When accounting for a previous mobile playlist, MusicLib **fabricates** `LastTimePlayed` timestamps. The algorithm distributes timestamps evenly across the accounting window using linear interpolation:

```
offset_i = window_duration × (i / total_tracks)
timestamp_i = window_start + offset_i
```

This assigns one synthetic timestamp per track, spread uniformly across the period. The assumption is that each track was played once, evenly spaced. The real listening pattern is unknown and unrecorded.

Fabricated timestamps are written to:
1. `musiclib.dsv` — the authoritative store
2. `Songs-DB_Custom1` file tag — so that a `musiclib-cli build` run after DSV loss restores them as if real

---

## Rationale

- **No alternative exists.** KDE Connect does not expose playback history. The mobile player (e.g., a standard Android music app) provides no API for this.
- **Some data is better than none.** A uniform distribution gives the library view meaningful "last played" values and prevents all mobile tracks from showing as unplayed.
- **The fabrication is documented, not hidden.** BACKEND_API.md §2.2.1 explicitly labels these as "fabricated" and notes the Synthetic Timestamp Note. The DSV is the authoritative store regardless.

**Accepted costs**:
- `LastTimePlayed` for mobile tracks is not accurate — it is a linear approximation.
- The values survive a `musiclib-cli build` (reconstructed from `Songs-DB_Custom1` tags) and will re-appear as if real. There is no flag to distinguish fabricated from real timestamps.
- There is no opt-out in the current config schema.

---

## Consequences

- The mobile upload workflow requires a minimum 1-hour accounting window (`MIN_PLAY_WINDOW`) to produce meaningful timestamps. Uploads within 1 hour of the previous upload are rejected for accounting.
- The maximum window is 40 days (`MOBILE_WINDOW_DAYS`) before the system emits a warning — beyond that, the uniform distribution assumption degrades further.
- Recovery files (`.pending_tracks`, `.failed`) preserve fabricated timestamp values so they can be retried if writes fail during accounting.
- Any future feature that reports real mobile playback events should supersede this ADR with a new one.

---

## See Also

- ARCHITECTURE.md §2.4 — mobile sync workflow and timestamp logic  
- BACKEND_API.md §2.2.1 — full accounting algorithm and Synthetic Timestamp Note  
- BACKEND_API.md §2.2.3 — `mobile retry` subcommand (re-applies fabricated timestamps on failure)
