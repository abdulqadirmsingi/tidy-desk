# Decision log

Short ADR entries. Newest last.

## 1. SwiftPM package + bundling script instead of an `.xcodeproj`
No project generator is installed and a hand-written `.pbxproj` is brittle. A package with a pure `TidyDeskCore` library and an app target is reproducible from the CLI and opens in Xcode. Trade-off: Instruments/archive workflows need an Xcode project created later. `Config/branding.env` stays the identity source.

## 2. Window identity via `CFEqual` on retained `AXUIElement`s
The only public alternative to titles. `_AXUIElementGetWindow` is private and is not used (RULES §2).

## 3. Global shortcuts with Carbon `RegisterEventHotKey`
Public API, needs no Input Monitoring permission, reports conflicts. A `CGEventTap` would need an extra permission.

## 4. Plain drag-and-drop swap instead of modifier-drag
A global modifier-drag gesture needs an event tap/Input Monitoring. Dropping a window on a tile (detected from AX move events + mouse-up) works with Accessibility alone.

## 5. Minimum sizes are learned, not read
No public AX attribute exposes them. Refused resizes are compared with requests and stored per bundle id.

## 6. Stage Manager detection via the `com.apple.WindowManager` preference (read-only)
No public query API. If the key's semantics change, the worst case is a missed pause, never a system change.

## 7. No Peek / Clean Space as backdrops ordered beneath the active window
Uses `NSWindow.order(_:relativeTo:)` with a window number found by pid+bounds in `CGWindowListCopyWindowInfo` (no Screen Recording needed without titles). Windows above the active window in z-order are unaffected. If no reference window is found the backdrop is hidden rather than covering everything.

## 8. Own sheets/windows via `NSWindow` + `NSHostingView` rather than SwiftUI scenes
Reliable opening from a menu bar agent (`LSUIElement`) with no launch-time window.

## 9. Auto-tiling resumes at launch once onboarding is done
The user opted in during onboarding; first-seen frames are recorded so *Restore Previous Arrangement* works. Before onboarding completes nothing is moved.

## 10. Ad-hoc signing by default for local builds
Avoids guessing which of several keychain identities is yours. Stable Accessibility grants need `SIGN_IDENTITY` (documented).
