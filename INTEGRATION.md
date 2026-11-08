# Fork merge: internal WS2 → 1.0.x line

This branch (`integration/internal-fork`) is a **long-running integration project**, not a release branch.
It merges `WindowShade-internal` (`feat/system-island`) into the public 1.0.x line.

## Baseline

- Merge commit `28b2da5f`: internal tree imported; **public wins every content conflict**.
  Both histories are preserved (internal parent `6a4c4599`).
- Public architecture is authoritative: `prototype/App/Notch/` modules
  (`NotchCanvasView` / `NotchPanel` / `NotchController`).
- The internal monolithic `prototype/App/Notch.swift` was deleted in the next commit;
  it duplicated those types. The island wiring it contained is preserved in internal
  history and must be **ported**, not merged blindly.

## Rules

1. Public wins for release, tooling, appcast, scripts, build.sh, site, Info.plist.
2. Island work is ported into `prototype/App/Notch/` deliberately, one feature at a time,
   with `build.sh --check` + the island test runners as the gate.
3. Never resolve an add/add by taking the internal file wholesale if public has a
   same-named file with a different architecture.

## Port checklist (next)

- [ ] `IslandMotionState` six-state model wired into public `NotchController`/`NotchCanvas`.
- [ ] `islandPrompt` / `islandSizing` / `islandHidden` tokens in `Motion`/`FlickMotion`.
- [ ] `IslandMetrics.PlatterBehavior` + `expandedWidth` (408/371/160) in public geometry.
- [ ] Activity ↔ six-state mapping (`NotchActivityMotion`).
- [ ] Port island tests/runners and add them to CI (keep x86_64 cross check).
- [ ] Full `build.sh --check` (arm64 + x86_64) and island runners green.
- [ ] Then, and only then, cut 1.0.22 (1.0.21 ships from `main`: 1.0.20 + Intel).

## Known state

- The merge currently does **not** build: imported internal-only files may reference
  internal APIs; each one is either ported or removed.
- Do not release from this branch.
