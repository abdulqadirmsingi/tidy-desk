# Testing

Be strict about wording here: **automated** = ran in `swift test`; **manual** = a human did it on a real desktop. Nothing under "Manual QA" has been performed yet.

## Automated tests (last run: 69 passed, 1 skipped, warnings-as-errors build clean)

Run: `swift test` or `scripts/test.sh`. No Accessibility permission needed. Results above are from this repo's initial implementation session on macOS 26.5.1 / Swift 6.3.3.

### `TidyDeskCoreTests` (pure logic)

| Area | Covered |
|---|---|
| Grid | 1, 2, 3, 4 windows; portrait 2 and 3; offsets/safe areas; weights; spacing; margins |
| Columns | 1–4 windows; portrait → rows; minimum widths; infeasible minimums; too-tall minimum; differs from Grid |
| Edge cases | zero/over-limit counts, empty/NaN/too-small areas, 2×2 row alignment, axis splitter pinning |
| Planner | max count, stack overflow, float overflow, tiles again when room appears, determinism, oversized window floats, narrow display reduces columns, empty/unusable area, clamping |
| Ratio inference | resize feeds back into layout (primary and secondary), unchanged frame, clamping |
| Constraint learning | learns on refusal, ignores accepted/implausible, never lowers a minimum |
| Window order | first = primary, append new, removal keeps order, duplicate events, alive-but-unlisted slot kept, swap/move/promote, **display disconnect/reconnect restore**, windows closed while absent not restored |
| Placement budget | refusal cap, one-time stubborn signal, success forgives, per-window, self-moving windows, slow corrections ignored, reset/retain, bounded loop |
| Tiling status | priority of permission, sleep, Stage Manager, user pause; resumes when Stage Manager is off |
| Onboarding flow | step order, permission steps skipped when granted, no stranding when access arrives mid-tour, back/forward direction, progress |
| Command search | empty query, ranking tiers, keywords, all-words rule, case/spacing, letters-in-order, stable ties, every action findable by its title |
| Default shortcuts | unique, all Control+Option, readable key names, palette bound |
| Switcher navigation | reading-order wrap, up/down between displays, single display, empty groups, number keys |
| Eligibility / explanation / retry schedule | every disqualifier, missing attributes tolerated, explanations distinct and title-free, finite growing retry delays |
| Inexpressible resizes | shrinking a single window or a full-height column tile changes no weights (the case that now floats the window) |
| Suggestion policy | tidy-up needs a new window and ≥2 windows while paused, silent when active/Stage Manager/asleep, cooldowns, "Not Now" silence, access reminder is rare and silenced separately; coordinator raises each once |
| Menu bar symbol / Dock setting | symbol per status, attention states never look active, `showInDock` defaults off and survives older files |
| Gestures / centring / count shortcuts | unchanged, nudge snap-back, plain drag floats, ⌘-drag swaps, resize incl. left edge, centring and oversize anchoring, ⌃⌥⌘1–4 |
| False minimum sizes | cell-snapping overshoot is not a refusal, genuine refusals still learned, stale full-height reading never remembered, 75% plausibility cap, saved impossible minimums ignored, a repaired minimum tiles in a 2×2 grid, the unrepaired one pushes other windows out |
| Focus mode | enter/exit, invalidation rules |
| Configuration | round trip, missing file, older/partial files, missing version, newer schema refused and untouched, corrupt file backed up with original bytes, same-instant corruption never overwrites a backup, backups pruned, wrong-type/empty files, unreadable file set aside, honest messages, per-display override/reset, clamping, delete |
| Newer-version protection | save/delete refuse a newer file, load→edit→save cycle keeps it, explicit reset backs it up first, current/unversioned files stay writable; same flow through `SettingsStore` |
| Shortcuts | defaults conflict-free and distinct, conflict detection, display strings |
| Coordinates | AppKit ↔ AX flip |

### `TidyDeskTests` (app target, no permission, no foreign windows)

Permission service matches system state; display geometry consistent; `SettingsStore` persistence and silent/notifying updates; reset keeps onboarding flag; hot-key registration (own-map conflicts only); login-item state readable.

Float toggle (app target): state and UI flags are tested with an injected window, not a real one.

### Opt-in Accessibility test

`TIDYDESK_AX_TESTS=1 swift test` — moves/resizes a window created by the test through `AXElement`/`WindowPlacementService`. **Skipped in the last run** because the host shell isn't trusted for Accessibility. It has not passed yet.

The messaging timeout itself has no public getter, so only its configured value and the "discovery returns promptly without permission" behavior are tested. A genuinely hung app has **not** been simulated.

## Not covered by automated tests

The coordinator, observers, overlays, SwiftUI views, menu bar, and any behavior against third-party apps. These need Accessibility and a display, and automated tests must not rearrange a developer's desktop.

## Manual QA checklist (all **NOT PERFORMED**)

Mark with date and macOS version when done.

| # | Scenario | Result |
|---|---|---|
| 1a | Onboarding looks right: frosted window, glass panels/buttons, animated demo, slide transitions; Reduce Motion and Reduce Transparency respected (**not yet verified**; layout of every step was checked offscreen only, with glass/blur/animation not rendered) |
| 1b | Menu panel: click the icon (opens under it, keeps the previous app active), switch on/off, layout controls, *Tile <app>* and *Float this window* act on the app you were in, actions close the panel first, clicking the icon again closes it, right-click menu, Escape/outside click closes (**not yet verified**; the status item was once checked in isolation, which missed that startup never created it; fixed and now covered by the startup wiring tests, and a relaunch showed TidyDesk's panel/toast windows plus extra menu bar entries, but the icon itself has not been seen) |
| 1c | *Also show in the Dock* adds/removes the Dock icon live; clicking it, or relaunching from Spotlight, opens Settings (**not yet verified**) |
| 1 | Launch: menu bar icon appears, no Dock icon, welcome tour opens on first run | ☐ |
| 2b | With tiling off, open a new window: a toast appears under the menu bar (below the notch) offering to tidy up; each button works; it never steals focus and doesn't reappear immediately (**not yet verified**) |
| 2a | Rebuild with a different signature while an old entry is switched on: the tour shows the reset help after ~6 s, *Reset Permission and Try Again* clears it and re-grant works (**reported by the owner on first run; fix not yet verified**) |
| 2 | Permission: grant via tour; icon changes from warning; revoke while running → tiling stops, no prompts loop | ☐ |
| 3 | Safari, Finder, Terminal, Xcode, Cursor/another editor tile in Grid and Columns (1–4) | ☐ |
| 4a | Open an app that is slow to start (e.g. Prime Video): it joins the layout within a few seconds, without clicking elsewhere (**not yet verified**) |
| 4b | *Why isn’t this window tiled?* (menu panel button, or ⌃⌥K → “explain”) on Prime Video states the real reason (**not yet verified**) |
| 4c | Shrink a single window by dragging its edge: it floats with a notice instead of snapping back (**not yet verified**) |
| 4 | Open/close/minimize/restore/hide/unhide windows → layout updates once, no flicker | ☐ |
| 5 | Non-resizable window (e.g. System Settings, Calculator) is left floating | ☐ |
| 5a | Open Terminal, Claude, Finder, WhatsApp together with tiling on: they tile without any being left floating because of a wrong learned minimum; Settings → Apps → *Clear Learned Sizes* shows only plausible values (**reported broken by the owner; fix not yet verified**) |
| 6 | App with large minimum size → learned minimum appears in Settings → Apps; layout adapts or floats | ☐ |
| 7 | Modal dialog / sheet / popover / menu is never moved | ☐ |
| 8a | ⌘-drag a window onto another tile swaps (keep ⌘ held until release); plain drag leaves it floating with a notice; ⌃⌥⌘1–4 change windows per display; a window that cannot fit (e.g. Prime Video) is centred once, not left covering the tiles (**not yet verified**) |
| 8 | Drag a tile edge → neighbours adapt; drop onto another tile → swap; drag to another display | ☐ |
| 9 | Shortcuts: all defaults register; a conflicting one shows a warning | ☐ |
| 10 | Stack and Float overflow; cycle stack; float/tile active window | ☐ |
| 11 | Focus mode enter/exit; exits on layout change and when another window is activated | ☐ |
| 12 | No Peek dims only windows beneath the active one; disabling leaves no overlay | ☐ |
| 13 | Clean Space; exits on lock/sleep/display removal | ☐ |
| 14 | Window switcher: grouped by display, arrows/Tab/1–9/Return/Esc, glass look, selection animation (**not yet verified**) | ☐ |
| 14a | Command palette (⌃⌥K): opens over the active app without stealing focus, filtering, Return runs the command on the previously active window (**not yet verified**) | ☐ |
| 14b | New default shortcuts register without conflicts on a Mac with several input sources (⌃⌥K, ⌃⌥↩ …) (**not yet verified**) | ☐ |
| 15 | Laptop only; laptop + external; per-display settings differ | ☐ |
| 16 | Unplug/replug external → windows recovered on screen, layout restored on reconnect | ☐ |
| 17 | Stage Manager on (key `com.apple.WindowManager GloballyEnabled` exists and read `0` on the dev Mac; flipping not yet observed) → tiling pauses with explanation; off → resumes | ☐ |
| 18 | Multiple Spaces: switching Spaces doesn't scramble layouts (best effort) | ☐ |
| 19 | Sleep/wake and lock/unlock | ☐ |
| 20 | Quit and relaunch: settings persist, no unexpected rearrangement before onboarding completes | ☐ |
| 21 | Start at Login on/off; approval flow | ☐ |
| 22 | Restore Previous Arrangement | ☐ |
| 23 | Performance: idle CPU near zero with Activity Monitor; many windows responsive | ☐ |

## Measurements actually taken

One launch of the release build, idle, no Accessibility grant: ~89 MB RSS, 0.0 % CPU after 4 s. Single sample; not a benchmark; no Instruments run. No other numbers are claimed.

## Verification gaps in the initial session

- Menu bar rendering, Settings/onboarding visuals, and overlays were **not seen** (screen capture and UI scripting were not permitted in the session). The process launched and stayed alive without a crash.
- Real window placement, observers, drag/drop, hot-key delivery and the Accessibility integration test were **not run** (shell lacked Accessibility trust).
- Intel (`UNIVERSAL=1`) build not exercised. Notarization not attempted.

## Known limitations

See README. Additionally: `Configuration.displays` entries for displays you no longer own persist until reset; No Peek affects only the active window's display.
