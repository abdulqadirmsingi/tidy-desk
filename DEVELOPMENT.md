# Development

## Tools

- macOS 15+ with Xcode 26 (Swift 6.x). Verified here: macOS 26.5.1, Xcode 26.6, Swift 6.3.3, arm64.
- No third-party dependencies, no linter requirement (SwiftLint isn't installed; warnings-as-errors serves as the gate).

## Project setup

```bash
git clone <repo> && cd mavop
open Package.swift          # Xcode: pick the TidyDesk scheme
```

Why SwiftPM and a script instead of a hand-maintained `.xcodeproj`: reproducible from the CLI, reviewable diffs, no project generator. `scripts/build-app.sh` assembles the `.app` bundle (Info.plist from `Config/Info.plist.template`, generated icon, signing). If you later want an `.xcodeproj` for Instruments templates or archive workflows, create one in Xcode that references the package; keep `Config/branding.env` as the source of identity.

## Build

| Command | Result |
|---|---|
| `swift build` | Debug build |
| `scripts/build-app.sh` | `build/TidyDesk.app`, release, signed |
| `scripts/build-app.sh --run` | …and launches it |
| `UNIVERSAL=1 scripts/build-app.sh` | arm64 + x86_64 (Intel not run-tested) |

Branding (name, bundle id, version, developer) is in `Config/branding.env`.

## Test

```bash
swift test                                  # all automated tests, no permissions needed
scripts/test.sh                             # same, with warnings as errors
TIDYDESK_AX_TESTS=1 swift test              # also runs the opt-in Accessibility test
```

The opt-in test needs the host that runs `swift test` (Terminal, Xcode) to be listed under Accessibility. It only moves a window the test creates itself.

## Debugging

- Run the debug binary directly to see output: `.build/debug/TidyDesk`.
- Logs: `log stream --predicate 'subsystem == "com.niajiri.tidydesk"'` (categories `placement`, `lifecycle`, `shortcuts`). Logs contain events and error descriptions only — never window titles.
- Accessibility Inspector (Xcode → Open Developer Tool) shows what attributes an app exposes; use it when a window isn't picked up.
- Reset all local state: delete `~/Library/Application Support/TidyDesk/`. Reset the permission: `tccutil reset Accessibility com.niajiri.tidydesk`.
- A running instance keeps its Accessibility grant tied to its code signature. If the grant "stops working" after a rebuild, you are running a differently signed binary (see below).

## Local development signing

`scripts/build-app.sh` now signs with the Apple Development certificate whose name contains your `git config user.email` when one exists (it prints which), and falls back to ad-hoc (`-`) otherwise. Ad-hoc binaries have no stable identity, so macOS treats each rebuild as a new app and drops the Accessibility grant. To pick a certificate yourself, or to force ad-hoc with `SIGN_IDENTITY="-"`:

```bash
security find-identity -v -p codesigning        # list identities
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh --run
```

Local development signing (Apple Development) is for running on your own Mac. **Distribution** needs a *Developer ID Application* certificate plus notarization — see [RELEASE.md](RELEASE.md). No certificates or credentials are ever stored in the repo.

### Stable signing without typing it every time

Copy `Config/local.env.example` to `Config/local.env` (git-ignored) and set `SIGN_IDENTITY` once; `scripts/build-app.sh` reads it automatically. `security find-identity -v -p codesigning` lists your identities.

### "It's switched on in System Settings but the app says no access"

The grant is tied to the code signature. After a rebuild with a different signature (any ad-hoc build) the old entry looks on but doesn't apply. The app now detects the wait and offers **Reset Permission and Try Again** (runs `tccutil reset Accessibility <bundle id>`, which only affects this app). Manually: remove the entry with **−** in System Settings, relaunch, allow again. Signing with a stable identity avoids it.

## Conventions

Read [RULES.md](RULES.md). In short: pure logic in `TidyDeskCore` with tests, platform code behind small wrappers, one owner of mutable tiling state, bounded retries, no titles in logs.
