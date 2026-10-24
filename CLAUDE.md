# CLAUDE.md — TidyDesk

Native macOS (Swift/SwiftUI/AppKit) automatic window-tiling menu bar utility. Read `RULES.md` for the full rules and `docs/PROJECT_PLAN.md` for scope and phases. This file is the quick-start for working in the repo.

## Commands

```bash
swift build                      # debug build
swift test                       # automated tests (no Accessibility permission needed)
scripts/build-app.sh             # release build -> build/TidyDesk.app (ad-hoc signed)
scripts/build-app.sh --run       # build and launch
scripts/test.sh                  # tests + warnings-as-errors build
```

Branding (name, bundle id, version) lives in `Config/branding.env`. Never hardcode it elsewhere.

## Layout

- `Sources/TidyDeskCore` — pure Swift, Foundation + CoreGraphics only. Models, layout algorithms, planner, window order, persistence, migration. **No AppKit, no AX.** Everything here must be unit-tested.
- `Sources/TidyDesk` — the app: `App/`, `Platform/` (AX, displays, keyboard, permissions, login), `Features/` (tiling coordinator, overlays, switcher, settings, onboarding, menu bar).
- `Tests/TidyDeskCoreTests` — automated tests. Tests needing Accessibility live under `Tests/` guarded by an env var and are never run by default.
- `docs/` — plan, architecture, testing, release, privacy.

## Non-negotiables

1. Public APIs only. No private APIs (`_AXUIElementGetWindow`, CGS*, SkyLight), no SIP changes, no code injection, no admin rights.
2. No network, analytics, screenshots, screen recording, or logging/persisting of window titles.
3. One owner of mutable tiling state: `TilingCoordinator` (`@MainActor`). Layout math stays in Core as pure functions.
4. Never loop: every correction path must be bounded (retry caps, stubborn-window set, coalesced + generation-checked reconciles).
5. Never claim a feature works unless it was run. Record unverified items in `docs/TESTING.md`.
6. Keep AX calls guarded: set messaging timeouts, treat every attribute read as optional, tolerate vanishing windows.

## Workflow expectations

- Keep the package building after every change. Fix warnings; do not suppress them.
- Add/adjust Core tests with every Core change (`swift test` must pass before you report done).
- Update `docs/PROJECT_PLAN.md` phase checkboxes and `docs/TESTING.md` when status changes.
- Small focused files; match surrounding style; comments only for non-obvious platform behavior.
- Do not touch the user's real desktop in automated tests.
- Confirm before anything destructive or outward-facing (deleting files, signing/notarizing with real credentials, publishing).
