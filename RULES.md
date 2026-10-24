# RULES.md — Engineering rules for TidyDesk

These rules apply to every contributor, human or AI. They are deliberately concrete so they can be checked in review.

## 1. Product rules

1. Lives in the menu bar (`LSUIElement`), no Dock icon, no window at launch except onboarding on first run.
2. Never rearranges the desktop before the user understands what will happen (onboarding gate; the first arrange is user-initiated).
3. Never closes apps, never loses window arrangement. A "restore previous arrangement" snapshot exists before every bulk arrange.
4. Pause is always one click/shortcut away and takes effect immediately (cancels in-flight reconciles).
5. Fail soft: if a window cannot be moved/resized, let it float and say so; never retry endlessly.
6. UI is clean and native: system controls, SF Symbols, system typography, no decoration that slows the user down. Features without UI needs (tiling itself) must "just work".

## 2. Platform rules

1. Public APIs only. Forbidden: private AX/CGS/SkyLight symbols, SIP changes, injection, scripting additions, admin privileges.
2. Permissions: only Accessibility. No Screen Recording, Input Monitoring, Full Disk Access, etc.
3. Window identity = runtime `WindowID` mapped to an `AXUIElement` via `CFEqual`. Never title-based; never persisted.
4. Always call `AXUIElementSetMessagingTimeout` on app elements; a hung app must not hang TidyDesk.
5. Global shortcuts use Carbon `RegisterEventHotKey` (public, needs no extra permission). Handle registration failure per shortcut and surface it.
6. Coordinates: AppKit is bottom-left origin, AX/CG is top-left of the primary display. Convert only through `ScreenCoordinates`.
7. Do not modify global system settings (Stage Manager, Spaces, Dock) without explicit user consent. Detect and pause instead.

## 3. Privacy rules

1. No network code at all in v1. No analytics, telemetry, crash upload, updater.
2. Never persist or log window titles, document names, screenshots, or keystrokes. Titles may be read transiently for the Tab View and discarded on dismiss.
3. Logging uses `os.Logger`; interpolations of anything about windows/apps use `privacy: .private` or are omitted. Log events and counts, not content.
4. Persist only what `PRIVACY.md` lists. Adding a persisted field requires updating `PRIVACY.md` in the same change.

## 4. Architecture rules

1. `TidyDeskCore` has no AppKit/AX/SwiftUI. Layout math is pure and deterministic.
2. Views present; services decide. No window-management logic in SwiftUI views.
3. Single owner of mutable tiling state (`TilingCoordinator`). UI state (`AppModel`) is separate runtime state.
4. Dependency injection through initializers. A singleton needs a written reason in the PR/commit.
5. Protocols only where they enable a real test seam or decouple a system API. No speculative abstractions.
6. Value types and enums for configuration and layout modes. Exhaustive `switch`; no `default` that hides new cases.
7. Typed errors (`enum …: Error`), with a user-readable description and a recovery path.
8. Reconciliation is idempotent, coalesced, cancellable, and generation-checked so stale plans never apply.
9. Own-move vs user-move: every geometry write is recorded in an expectation table; matching notifications are ignored.
10. Loop guards are mandatory: per-window retry cap, "stubborn" set cleared only on structural change or user intent.

## 5. Swift code rules

1. Swift 6 language mode, strict concurrency. `@MainActor` for UI/AX; Sendable value types across boundaries.
2. No force unwraps/casts/`try!` except a documented invariant (e.g. CF type bridging after a `CFGetTypeID` check).
3. No `DispatchQueue.main.async` when `@MainActor`/`Task` works. Timers/observers/tasks have an owner and are cancelled in `deinit`/`stop()`.
4. No retain cycles: closures stored by services capture `[weak self]`.
5. Names follow Swift API Design Guidelines. Access control is explicit (`public` only in Core's API surface; `private`/`internal` elsewhere).
6. No magic numbers: use `LayoutDefaults` / `TilingTuning` constants with names.
7. Comments explain *why* (platform quirks, safety). No restating comments, no commented-out code, no TODOs without a tracked item in `PROJECT_PLAN.md`.
8. Files stay small and cohesive (guideline: < 300 lines; split by responsibility).
9. Warnings are errors in `scripts/test.sh`. Do not silence them.
10. No dead code, no unused dependencies, no duplicate models.
11. No third-party dependencies unless a real need is documented (v1 has none).

## 6. Testing rules

1. Every pure function in Core has unit tests, including edge cases (zero/negative sizes, NaN-ish geometry, empty input).
2. Automated tests must not move real windows or require Accessibility. Permission-dependent tests are opt-in (`TIDYDESK_AX_TESTS=1`) and use windows created by the test itself.
3. No disabled/skipped tests that hide failures. A known failing behavior is documented in `docs/TESTING.md`.
4. Bug fix = regression test first when the bug is in Core.
5. Report results truthfully: "built", "tested", "manually verified" are three different claims.

## 7. UX & accessibility rules

1. Every control has an accessibility label; keyboard navigable; respects Reduce Motion and Increase Contrast.
2. Error text states what happened and what to do next. Prefer inline messages over alerts; avoid modal alerts except destructive confirmations.
3. Overlays are click-through, never take focus, and are removed on disable, sleep, lock, and display removal.
4. Strings are written for localization (no concatenated sentences); English only for v1.

## 8. Security & release rules

1. No secrets, certificates, Apple IDs or app-specific passwords in the repo. Notarization uses a keychain profile (`notarytool store-credentials`).
2. Hardened runtime on for distribution builds; entitlements only when required (none expected).
3. Direct (Developer ID) distribution is the target; Mac App Store is out of scope because Accessibility control of other apps is incompatible with App Sandbox.
4. Never sign/notarize/publish without the user's explicit go-ahead.

## 9. Git & change hygiene

1. Small commits, imperative subject (`Add columns layout`), body explains why.
2. Never commit `build/`, `.build/`, `.swiftpm/`, user config, or credentials.
3. Each phase ends with: builds clean, tests pass, docs/checkboxes updated.
4. Architecture-affecting decisions are appended to `docs/DECISIONS.md` (short ADR entries).

## 10. Definition of done (per change)

Builds without warnings · tests added/updated and green · no new network/permission/PII surface · docs and plan updated · unverified behavior explicitly listed.
