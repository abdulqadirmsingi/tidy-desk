# TidyDesk — Project Plan

A native macOS menu bar app that automatically tiles application windows, inspired by the *publicly observable behavior* of Shoji (shojimac.com). All code and assets are original. Name, bundle id, and icon are placeholders configured in `Config/branding.env`.

Status legend: `[x]` done and verified · `[~]` implemented, not verified on a real desktop · `[ ]` not done. Statuses are updated honestly as work proceeds.

## 1. Goals and principles

Menu-bar only · automatic arrangement · usable window sizes · independent layout per display · reacts to open/close/minimize/restore/hide/move · keyboard + mouse · no analytics, fully offline · light on CPU/memory · never closes apps or loses arrangement · pause/restore always available · understandable codebase.

## 2. Technology (fixed decisions)

| Area | Choice |
|---|---|
| Language | Swift 6 (toolchain 6.3), strict concurrency |
| UI | SwiftUI + AppKit (status item menu, NSWindow hosting, overlay windows) |
| Window control | Accessibility API (`AXUIElement`, `AXObserver`) |
| Displays | `NSScreen` + CoreGraphics display IDs/UUIDs |
| Shortcuts | Carbon `RegisterEventHotKey` (public) |
| Login | `SMAppService.mainApp` |
| Persistence | `UserDefaults` for trivial flags, versioned JSON for configuration |
| Build | SwiftPM + `scripts/build-app.sh` bundler (Xcode opens `Package.swift`) |
| Targets | macOS 15+, arm64 primary, no arm64-only code (Intel buildable) |
| Forbidden | Electron/web UI, backend, analytics, private APIs, SIP changes, injection |

**Why SwiftPM instead of a hand-made `.xcodeproj`:** reproducible from the command line, diffable, no generator dependency. The `.app` is assembled and signed by script. Details in `DEVELOPMENT.md`.

## 3. API limitations (investigated, honest)

- No public API exposes a window's minimum size → learned from failed resizes and stored per bundle id.
- No public CGWindowID from `AXUIElement` → identity via `CFEqual` of retained elements.
- No public Space identification → per-Space order is *best effort* (windows on other Spaces are not enumerated; known-alive windows keep their order slot). Documented, not claimed perfect.
- Stage Manager has no public query API; detected through the `com.apple.WindowManager` `GloballyEnabled` preference (read-only). If on, tiling is paused with an explanation.
- Some apps refuse resizing (fixed-size windows, Electron quirks) → detected, learned, floated.
- ⌘-drag swap works without an event tap or Input Monitoring: the ⌘ state is read from `NSEvent.modifierFlags` while a window drag (seen through Accessibility move events) is in progress. A plain drag floats the window.
- No Peek / Clean Space: implemented with click-through overlay windows ordered directly beneath the active window (window numbers matched by bounds via `CGWindowListCopyWindowInfo`, which needs no Screen Recording permission when titles are not read). Best effort; z-order above the active window is not controllable.
- Mac App Store: App Sandbox forbids controlling other apps' windows → Developer ID distribution only.

## 4. Feature scope

1. **Discovery** — AX enumeration of regular apps; eligibility: `AXWindow` + `AXStandardWindow`, not minimized/full-screen/modal, resizable & movable, app not hidden/excluded/self.
2. **Auto arrange** — triggers: window created/destroyed/min/restore, app hide/show/launch/quit, display change, settings change, wake, drag-drop. Debounced (≈120 ms), coalesced, generation-checked.
3. **Ordering** — deterministic per display; first = primary; promote on close; swap via keys or drag; no duplicates.
4. **Grid** — 1: full · 2: left/right · 3: primary left, right split · 4: 2×2 row-major. Portrait displays stack instead of side-by-side.
5. **Columns** — n columns (rows on portrait), reduced when minimum widths do not fit.
6. **Counts / overflow** — 1–4 per display; *Stack* (extra windows share last tile, raise/cycle) or *Float* (extras left floating, auto-tiled when room appears).
7. **Resizing** — user resize of a tiled window updates tile weights and neighbors adapt; keyboard grow/shrink/reset; minimum-size learning with bounded retries; infeasible → float.
8. **Multi-display** — per-display settings/order; reconnect restore; move window to next/previous display.
9. **Spaces / Stage Manager** — see §3.
10. **Focus mode** — active window fills usable area; exit restores tiles.
11. **No Peek** — dims everything beneath the active window; click-through; fully removable.
12. **Clean Space** — opaque backdrop beneath the active window on its display; exits on sleep/lock/display loss.
13. **Tab View** — switcher panel grouped by display, icons + names (+ transient titles), keyboard navigation.
14. **Appearance** — spacing, margins, active border, all borders, glow, color, thickness, light/dark/system, menu bar icon style.
15. **Menu bar** — all controls listed in the original brief.
16. **Settings** — General, Layout, Displays, Shortcuts, Appearance, Apps, Privacy & Permissions, About.
17. **Onboarding** — 7 steps, no automatic rearrangement before the final step.
18. **Permissions** — `AXIsProcessTrusted` service, prompt once, deep link to Privacy & Security, detect grant/revoke, suspend when missing.
19. **Persistence** — versioned, atomic, corruption-tolerant; never stores titles or AX references.
20. **Login item** — `SMAppService`.
21. **Lifecycle** — sleep/wake/lock/display reconcile; observers and overlays cleaned up.

## 5. Phases

### Phase 1 — Environment and architecture
- [x] Inspect macOS 26.5.1, Xcode 26.6, Swift 6.3.3 (arm64), SDK, existing files (workspace was empty)
- [x] Choose structure (SwiftPM, Core + App), write plan, rules, CLAUDE.md

### Phase 2 — Native foundation
- [x] Package, Core models, configuration + versioned JSON store + migration
- [~] Menu bar app, Settings window, onboarding, permission service, lifecycle (builds and launches; UI not visually verified)
- [x] Automated tests (69 pass), release build, process launches and idles at ~0% CPU

### Phase 3 — Discovery and placement
- [~] AX wrapper, eligibility, display service, geometry read/write, typed errors (compiled; not run against real windows)
- [ ] Tested against real app windows (manual — see `TESTING.md`)

### Phase 4 — Tiling engine
- [x] Grid, Columns, planner, order book, constraints, overflow (pure, unit tested)
- [~] Coordinator, reconciliation, observers, learned minimums (compiled; unverified on a desktop)

### Phase 5 — Displays and shortcuts
- [x] Per-display settings, reconnect restore logic (unit tested), shortcut registry + conflict detection
- [~] Cross-display moves, hotkey registration on a real system (hotkey registration test runs in `swift test`; delivery unverified)

### Phase 6 — Secondary features
- [~] Focus, swap, drag-resize/drop, Tab View, Clean Space, No Peek, exclusions, login item (all implemented; none verified on a desktop)

### Phase 7 — Reliability and polish
- [~] Permission revocation, sleep/wake, overlay cleanup, onboarding, accessibility labels (implemented, unverified); docs [x]
- [ ] Instruments measurements (not done; no numbers claimed)

### Phase 8 — Release preparation
- [x] Release build script (ad-hoc signed build verified), signing/notarization/packaging docs
- [ ] Notarized build (requires the owner's Developer ID certificate and credentials)
- [ ] Full manual QA matrix (owner to perform; see `TESTING.md`)

## 6. Quality bar (Definition of Done)

Launches natively · menu bar · permission handled · discovers and arranges windows · Grid/Columns correct · open/close updates · minimum sizes respected · basic multi-display · settings persist · pause works · exclusions respected · no loops/freezes · layout tests pass · tested on real windows · docs match behavior · reproducible build · no backend/analytics/network · signing + notarization instructions exist.

## 7. Items beyond the original brief (added deliberately)

- AX messaging timeouts so a hung app cannot freeze TidyDesk.
- Per-window "float" toggle (escape hatch for windows the user does not want tiled).
- Stage Manager detection and automatic pause.
- Loop guards (stubborn windows, retry caps, generation checks).
- `os.Logger` with private interpolation; no title logging.
- `docs/DECISIONS.md` ADR log; `git` repo with `.gitignore`.
- Reduced Motion / Increase Contrast respect for overlays.
- Config backup on corruption (`config.json.corrupt-<timestamp>`) and refusal to overwrite newer-schema files.

## 8. Backend decision

None. No account, license, sync, or update server in v1. Any future need must be raised with data flow, privacy, and cost analysis before implementation.
