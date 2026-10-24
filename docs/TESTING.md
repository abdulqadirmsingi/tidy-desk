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
| Focus mode | enter/exit, invalidation rules |
| Configuration | round trip, missing file, older/partial files, missing version, newer schema refused and untouched, corrupt file backed up, per-display override/reset, clamping, delete |
| Shortcuts | defaults conflict-free and distinct, conflict detection, display strings |
| Coordinates | AppKit ↔ AX flip |

### `TidyDeskTests` (app target, no permission, no foreign windows)

Permission service matches system state; display geometry consistent; `SettingsStore` persistence and silent/notifying updates; reset keeps onboarding flag; hot-key registration (own-map conflicts only); login-item state readable.

### Opt-in Accessibility test

`TIDYDESK_AX_TESTS=1 swift test` — moves/resizes a window created by the test through `AXElement`/`WindowPlacementService`. **Skipped in the last run** because the host shell isn't trusted for Accessibility. It has not passed yet.

## Not covered by automated tests

The coordinator, observers, overlays, SwiftUI views, menu bar, and any behavior against third-party apps. These need Accessibility and a display, and automated tests must not rearrange a developer's desktop.

## Manual QA checklist (all **NOT PERFORMED**)

Mark with date and macOS version when done.

| # | Scenario | Result |
|---|---|---|
| 1 | Launch: menu bar icon appears, no Dock icon, welcome tour opens on first run | ☐ |
| 2 | Permission: grant via tour; icon changes from warning; revoke while running → tiling stops, no prompts loop | ☐ |
| 3 | Safari, Finder, Terminal, Xcode, Cursor/another editor tile in Grid and Columns (1–4) | ☐ |
| 4 | Open/close/minimize/restore/hide/unhide windows → layout updates once, no flicker | ☐ |
| 5 | Non-resizable window (e.g. System Settings, Calculator) is left floating | ☐ |
| 6 | App with large minimum size → learned minimum appears in Settings → Apps; layout adapts or floats | ☐ |
| 7 | Modal dialog / sheet / popover / menu is never moved | ☐ |
| 8 | Drag a tile edge → neighbours adapt; drop onto another tile → swap; drag to another display | ☐ |
| 9 | Shortcuts: all defaults register; a conflicting one shows a warning | ☐ |
| 10 | Stack and Float overflow; cycle stack; float/tile active window | ☐ |
| 11 | Focus mode enter/exit; exits on layout change and when another window is activated | ☐ |
| 12 | No Peek dims only windows beneath the active one; disabling leaves no overlay | ☐ |
| 13 | Clean Space; exits on lock/sleep/display removal | ☐ |
| 14 | Window switcher: grouped by display, arrows/Tab/Return/Esc | ☐ |
| 15 | Laptop only; laptop + external; per-display settings differ | ☐ |
| 16 | Unplug/replug external → windows recovered on screen, layout restored on reconnect | ☐ |
| 17 | Stage Manager on → tiling pauses with explanation; off → resumes | ☐ |
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
