# TidyDesk

A native macOS menu bar app that automatically tiles your windows. Swift, SwiftUI and AppKit; no web views, no backend, no network. *TidyDesk is a placeholder name; branding lives in `Config/branding.env`.*

> **Status: early build (v0.1.0).** It compiles, the automated suite passes, and the app launches as a menu bar agent. Window placement against real third-party apps, hotkeys and the visual UI have **not yet been verified on a desktop** — see [docs/TESTING.md](docs/TESTING.md). Treat it as a build to try, not a finished product.

## What it does

- Tiles eligible windows per display with **Grid** or **Columns** (1–4 windows per display), re-arranging when windows open, close, minimize, restore, hide, or move between displays.
- Extra windows either **stack** in the last tile or **float** until space frees up.
- Drag a tile's edge to resize (neighbours adapt); **hold ⌘ while dragging** a window onto another tile to swap (a plain drag places the window freely and leaves it floating); keyboard shortcuts for swap, move to another display, grow/shrink, reset.
- Learns minimum sizes of apps that refuse to shrink and floats windows that can't fit.
- **Focus mode**, **No Peek** (dims windows beneath the active one), **Clean Space** (clean backdrop behind one window), a keyboard-driven **window switcher**, active-window border/glow.
- *Explain Active Window* in the menu says in plain words why a window is or isn't tiled.
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

The build script signs with the Apple Development certificate matching your git email when you have one, which keeps the grant across rebuilds. Ad-hoc builds (no matching certificate) get a new identity on every rebuild, so macOS asks again; choose a certificate explicitly with: `SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh` (see [DEVELOPMENT.md](DEVELOPMENT.md)).

## The menu bar panel, Dock and finding the app

Click the menu bar icon for a glass panel: status at a glance, the **Automatic tiling** switch, layout, a **Tile <current app>** toggle, *Float this window*, *Why isn’t this window tiled?*, Arrange / Undo / Switcher / Commands, and the Focus / No Peek / Clean Space modes. Right-click the icon for Settings and Quit. The icon changes with state (grid = tiling, pause = off, triangle = needs access). If it's hard to spot among other icons, turn on **Settings → General → Also show in the Dock**. Launching the app again (Spotlight, Finder or the Dock) always opens Settings.

## Shortcuts and the command palette

Remember one: **⌃⌥K** opens the command palette. Type a few letters ("max", "pause", "undo", "monitor") and press Return; it lists every command with its shortcut. The rest are Control + Option plus a key you can reach with your other hand:

`↩` arrange now · `P` pause/resume · `L` Grid/Columns · `U` restore previous · `←` `→` swap with previous/next tile · `[` `]` move to previous/next display · `M` Focus · `N` No Peek · `H` Clean Space · `Tab` window switcher · `=` `-` grow/shrink tile · `0` reset sizes · `↑` cycle stack · `↓` float/tile active window · **⌃⌥⌘1–4** tile 1–4 windows per display.

All are configurable in Settings → Shortcuts. The window switcher (⌃⌥Tab) groups windows by display; use arrows or Tab to move, **1–9** to jump, Return to switch, Esc to close.

## Current limitations

- **Spaces:** macOS has no public Space identification API. Windows on other Spaces aren't enumerated; their order is kept best-effort. Per-Space isolation is not claimed.
- **Stage Manager:** detected through a read-only preference; tiling pauses while it's on.
- **Minimum sizes:** no public API reports them; they are learned from refused resizes.
- **No Peek / Clean Space:** overlays are placed directly beneath the active window; windows above it in z-order are not affected.
- **Dragging:** ⌘-drag swaps tiles; a plain drag floats the window where you drop it (use *Float Active Window* to tile it again). ⌘ is read when you release the mouse, so keep it held until you let go.
- **Mac App Store** is not possible (sandbox forbids controlling other apps' windows). Distribute with Developer ID — [RELEASE.md](RELEASE.md).
- No auto-updater. Updates are manual.

## Documentation

[CLAUDE.md](CLAUDE.md) · [RULES.md](RULES.md) · [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [DEVELOPMENT.md](DEVELOPMENT.md) · [RELEASE.md](RELEASE.md) · [PRIVACY.md](PRIVACY.md) · [docs/TESTING.md](docs/TESTING.md) · [docs/DECISIONS.md](docs/DECISIONS.md)
