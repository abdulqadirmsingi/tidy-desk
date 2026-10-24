# TidyDesk

A native macOS menu bar app that automatically tiles your windows. Swift, SwiftUI and AppKit; no web views, no backend, no network. *TidyDesk is a placeholder name; branding lives in `Config/branding.env`.*

> **Status: early build (v0.1.0).** It compiles, the automated suite passes, and the app launches as a menu bar agent. Window placement against real third-party apps, hotkeys and the visual UI have **not yet been verified on a desktop** — see [docs/TESTING.md](docs/TESTING.md). Treat it as a build to try, not a finished product.

## What it does

- Tiles eligible windows per display with **Grid** or **Columns** (1–4 windows per display), re-arranging when windows open, close, minimize, restore, hide, or move between displays.
- Extra windows either **stack** in the last tile or **float** until space frees up.
- Drag a tile's edge to resize (neighbours adapt); drop a window on another tile to swap; keyboard shortcuts for swap, move to another display, grow/shrink, reset.
- Learns minimum sizes of apps that refuse to shrink and floats windows that can't fit.
- **Focus mode**, **No Peek** (dims windows beneath the active one), **Clean Space** (clean backdrop behind one window), a keyboard-driven **window switcher**, active-window border/glow.
- Per-display settings that survive unplugging a display; "restore previous arrangement"; pause at any time.
- Entirely local: no analytics, screenshots, or network access. See [PRIVACY.md](PRIVACY.md).

## Requirements

- macOS 15 (Sequoia) or later. Developed on macOS 26.5 / Xcode 26.6 / Swift 6.3 on Apple Silicon. Nothing is arm64-only; `UNIVERSAL=1` builds Intel + Apple Silicon.
- Xcode (or Command Line Tools) with Swift 6.

## Build, test, run

```bash
scripts/build-app.sh            # -> build/TidyDesk.app (release, ad-hoc signed)
scripts/build-app.sh --run      # build and launch
swift test                      # automated tests
scripts/test.sh                 # warnings-as-errors build + tests
open Package.swift              # develop in Xcode
```

## Grant Accessibility permission

1. Launch the app; the welcome tour opens on first run.
2. Click **Open Accessibility Settings**, then enable TidyDesk under *System Settings → Privacy & Security → Accessibility*.
3. If the menu bar still shows a warning icon after a few seconds, quit and reopen the app.

Ad-hoc signed builds get a new identity on every rebuild, so macOS may ask you to grant access again. Sign with your Apple Development certificate to keep it stable: `SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh` (see [DEVELOPMENT.md](DEVELOPMENT.md)).

## Default shortcuts (Control + Option)

`A` arrange now · `T` pause/resume · `L` Grid/Columns · `Z` restore previous · `←/→` swap with previous/next tile · `D` / `⇧D` move to next/previous display · `F` Focus · `N` No Peek · `C` Clean Space · `Tab` window switcher · `=` / `-` grow/shrink tile · `0` reset sizes · `↑` cycle stack · `G` float/tile active window (also in the menu bar as *Float Active Window*). All are configurable in Settings → Shortcuts.

## Current limitations

- **Spaces:** macOS has no public Space identification API. Windows on other Spaces aren't enumerated; their order is kept best-effort. Per-Space isolation is not claimed.
- **Stage Manager:** detected through a read-only preference; tiling pauses while it's on.
- **Minimum sizes:** no public API reports them; they are learned from refused resizes.
- **No Peek / Clean Space:** overlays are placed directly beneath the active window; windows above it in z-order are not affected.
- **Modifier-drag swapping** would need Input Monitoring; plain drag-and-drop onto a tile and shortcuts are used instead.
- **Mac App Store** is not possible (sandbox forbids controlling other apps' windows). Distribute with Developer ID — [RELEASE.md](RELEASE.md).
- No auto-updater. Updates are manual.

## Documentation

[CLAUDE.md](CLAUDE.md) · [RULES.md](RULES.md) · [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [DEVELOPMENT.md](DEVELOPMENT.md) · [RELEASE.md](RELEASE.md) · [PRIVACY.md](PRIVACY.md) · [docs/TESTING.md](docs/TESTING.md) · [docs/DECISIONS.md](docs/DECISIONS.md)
