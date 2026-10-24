# Architecture

Two SwiftPM targets keep the testable rules apart from the macOS plumbing:

```
Sources/TidyDeskCore   pure Swift (Foundation + CoreGraphics): models, layout, planner, order, persistence
Sources/TidyDesk       the app: Platform (AX, displays, keys, permission, login) + Features + App wiring
```

`TidyDeskCore` never imports AppKit, SwiftUI or ApplicationServices. Anything with real behavior is unit-tested there.

## Modules

| Area | Responsibility |
|---|---|
| `Core/Models`, `Configuration` | Value types: `LayoutKind`, `OverflowPolicy`, `TileWeights`, `DisplaySettings`, `Configuration` (versioned, tolerant decoding). |
| `Layout/AxisSplitter`, `LayoutAlgorithms` | Pure tile geometry for Grid and Columns, honoring spacing, margins, weights and per-tile minimums. |
| `Layout/TilePlanner` | Chooses which windows tile, stack or float; deterministic. |
| `Layout/RatioInference` | Converts a user's manual resize into new tile weights. |
| `WindowOrder` | Per-display ordering, swaps, moves, display park/restore. |
| `ConstraintLearner`, `FocusModeState` | Minimum-size learning; focus-mode state transitions. |
| `ConfigurationStore` + migration | Atomic JSON persistence, schema versioning, corruption recovery. |
| `Platform/Accessibility` | `AXElement` wrapper, discovery, lifecycle observers, placement. |
| `Platform/Displays` | `NSScreen` → stable display IDs and AX-space frames. |
| `Platform/Permissions`, `Keyboard`, `LoginItems` | Accessibility trust, Carbon hot keys, `SMAppService`. |
| `Features/WindowManagement` | `TilingCoordinator` (the single mutable-state owner) + `TilingUIState`. |
| `Features/Overlays` | Borders, No Peek dimming, Clean Space backdrop. |
| `Features/MenuBar`, `Settings`, `Onboarding`, `TabView` | SwiftUI presentation only. |
| `App` | `AppModel` composition root, `SettingsStore`, window presenter, lifecycle. |

UI state (`TilingUIState`, `AppModel`) is separate from runtime window state inside `TilingCoordinator`.

## Window discovery flow

`WindowDiscoveryService.discover` lists regular, non-hidden apps (excluding itself), reads each app's `AXWindows`, and keeps a registry mapping `AXUIElement` → `WindowID` using `CFEqual` (no private window-number API). A window is eligible if it is an `AXWindow` / `AXStandardWindow`, not minimized, full-screen or modal, has settable position and size, belongs to a non-excluded app, and has a usable frame. Ineligible but existing windows (minimized, hidden app, other Space) are reported as *alive* so their order slot is retained; dead elements are pruned by probing. Every `AXElement` (app, window, and observer-delivered) gets a 0.5 s messaging timeout in its initializer, because the timeout is per element. If a window read times out, the rest of that app's windows are skipped for the pass and their order slots are kept.

## Catching new windows

Observer registration can fail while an app is still starting. `WindowLifecycleMonitor.sync` keeps such registrations pending and retries them on later passes; the coordinator schedules those passes on a finite `RetrySchedule` (0.5, 1, 2, 4, 8 s), then stops. Independently, a focus change onto a window the registry has never seen triggers a reconcile, so a missed creation event is healed as soon as the window is used. `WindowEligibility` (Core) is the single definition of which windows may be tiled, and *Explain Active Window* reports its verdict in plain language without titles.

## Event handling flow

`WindowLifecycleMonitor` converts `AXObserver` callbacks (window created, destroyed, moved, resized, miniaturized, focus) and workspace/system notifications (launch, terminate, hide, unhide, activate, Space change, sleep, wake, screen lock, display parameters) into `WindowEvent`s. Observers are added per app on demand and removed on termination or `stop()`. Nothing polls.

`TilingCoordinator.handle` then:

- **structural / Space / display events** → `scheduleReconcile()` (120 ms debounce; a newer request cancels the older task).
- **geometry events** → ignored if they match an *expectation* recorded when we wrote that frame (own-move echo, 0.7 s). Otherwise, with the left mouse button down, the window is queued as a user gesture and finished on mouse-up; without it, an app moved itself → a bounded number of corrections (4 per 10 s) before the window is marked stubborn.
- **sleep / lock** → exits presentation modes, removes overlays; **wake / unlock** → reconcile after a settling delay.

## Reconciliation and placement

`reconcile` = up to 3 passes of: refresh displays → discover → update order (`WindowOrder.reconcile`) → plan each display (`TilePlanner`) → apply (`WindowPlacementService.place`: set position, set size, re-set position, read back). A refused resize is compared with the request by `ConstraintLearner`; a learned minimum is stored (silently, no re-trigger) and the pass repeats. Retry limits live in the pure, tested `PlacementBudget`: each window gets two refusals, and an app that moves itself more than four times in ten seconds without a mouse gesture is treated the same. After that the window is *stubborn*, excluded from planning and left floating until the user changes settings or chooses *Arrange Now*. All of this runs on the main actor so a plan is always applied against the state it was computed from.

First-seen frames are remembered per window so *Restore Previous Arrangement* can put windows back (and pause tiling).

## Layout calculation

Layouts are described as **columns of stacked tiles** in a landscape frame:

| Layout | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Grid | full | `[0][1]` | `[0][1/2]` | 2×2: `[0 2][1 3]` (row-major) |
| Columns | one column | n equal columns | | |

`TileWeights.primary` scales the first column; `secondary` scales the first row of a two-row column. Portrait areas transpose the frame (columns become rows) except the 2×2 grid. `AxisSplitter` splits each axis proportionally to weights while pinning segments at their minimums, returning nil if the minimums cannot fit. `TilePlanner` admits windows greedily in order, so a window that cannot fit is rejected without blocking the others; rejected/surplus windows follow the overflow policy (stack on the last tile if they fit, otherwise float).

## Display management

`DisplayService` converts `NSScreen` frames to Accessibility coordinates (`ScreenCoordinates.flip`) and identifies displays by CoreGraphics UUID. Windows belong to the display with the largest overlap. When a display disappears, `WindowOrder` parks its ordering; when it returns, windows still alive are moved back in their old order. Per-display settings live in `Configuration.displays` and are never deleted on disconnect.

## Persistence

`config.json` in `~/Library/Application Support/<AppName>/`, written atomically, debounced 0.4 s, flushed on quit. Fields decode with defaults, so older files load after upgrades. `ConfigurationMigration` has an (currently empty) step list keyed by schema version; newer-than-supported files are never overwritten or deleted (`save` throws, the UI says changes won't be saved) unless the user explicitly resets, in which case the file is first moved aside as `config.json.newer-<ms>`; unreadable or invalid files (including ones that exist but cannot be read) are moved aside under a unique `config.json.corrupt-<ms>` name, the newest 5 are kept, and the UI message says whether the backup actually succeeded. Nothing about windows (titles, references, frames) is stored — only bundle identifiers of excluded apps and learned minimum sizes.

## Suggestions

When tiling is not automatic, the app speaks up instead of staying silent. `SuggestionPolicy` (Core, tested) decides when: *tidy up* when a new window appears while tiling is off and at least two windows exist (45 s cooldown, 15 min of silence after "Not Now"), and *grant access* when Accessibility is missing (at most every 10 minutes). The coordinator raises it (a paused-mode scan is read-only: it only looks, and keeps observers attached so new windows are noticed), and `ToastPresenter` shows a non-activating glass toast just below the menu bar, which on notched Macs is below the notch. Nothing is shown while the welcome tour is open. Choosing *Always Arrange Automatically* enables tiling and completes onboarding.

## Command palette and switcher

Both are transient glass panels shown by `FloatingPanelPresenter`: a non-activating key panel, so the previously active window stays active and commands act on it, closed on focus loss. Palette search is `CommandSearch` (Core, tested): prefix > word-start > substring > keyword > letters-in-order, every word must match. Commands are every `ShortcutAction` (title, keywords, current shortcut) plus Settings and the welcome tour. Switcher keyboard movement is `SwitcherNavigation` (Core, tested): left/right walk reading order, up/down jump between displays keeping the column. Default shortcuts are Control + Option plus a key reachable with the other hand; the palette is ⌃⌥K.

## Onboarding

`OnboardingFlow` (Core, tested) owns step order and skips the permission steps once access is granted; if access arrives while the user is on the grant page, the tour moves on by itself. The views (`Features/Onboarding`) only present it: a frosted window (`NSVisualEffectView` behind-window blur, transparent title bar), `glassPanel()`/`glassButton()` helpers that use Liquid Glass on macOS 26 and frosted material before it, and `TilingDemo`, which animates placeholder windows through the real `TilePlanner`. Reduce Motion stops the animations and slides, and Reduce Transparency replaces glass with plain backgrounds.

## Pause conditions

`TilingStatus.resolve` (Core, tested) decides whether windows may be touched, in priority order: no permission → asleep/locked → Stage Manager on → user pause / onboarding incomplete. Stage Manager is read from the `com.apple.WindowManager` `GloballyEnabled` preference. There is no change notification, so it is re-checked on reconciles and on every focus change; tiling resumes by itself once it is off. While paused for it, a notice explains why.

## Permission handling

`AccessibilityPermission` reads `AXIsProcessTrusted`, prompts once on request, deep-links to Privacy & Security, and refreshes on the system's Accessibility notification and on app activation. On revocation the coordinator removes overlays and reports `needsPermission`; no AX call is made until it returns.

## Error recovery summary

Failed/vanished windows → attempt budget → stubborn; refused sizes → learned minimum; infeasible layout → floating windows; display loss → parked order + off-screen recovery; corrupt config → backup + defaults; hot-key conflicts → surfaced per shortcut; paused/Stage Manager/asleep/no permission → no window writes.
