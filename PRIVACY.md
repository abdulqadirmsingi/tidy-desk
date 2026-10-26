# Privacy

TidyDesk is local-only. It has no account system, analytics, telemetry, crash reporting, tracking SDK, cloud sync, or updater, and it contains **no networking code**.

## Data accessed locally (runtime only, never stored)

- For each running regular app: its process id, bundle identifier, and localized name.
- For each window, through Accessibility: position, size, role/subrole, minimized/full-screen/modal state, whether position and size are settable.
- The window **title**, only while the window switcher is open, to label its cards. It's held in memory for that session and discarded; it is never logged or written to disk.
- Window numbers and bounds from `CGWindowListCopyWindowInfo` (no titles requested) to place the No Peek / Clean Space backdrop.
- Display geometry and identifiers; the Stage Manager preference (read-only).

## Permissions

Only **Accessibility**. It is required to move and resize other apps' windows. TidyDesk does not request Screen Recording, Input Monitoring, Full Disk Access, Contacts, Camera, Microphone, or any other permission, and does not take screenshots.

## Data stored on disk

`~/Library/Application Support/TidyDesk/config.json`:

- Tiling on/off, onboarding completed.
- Per-display layout settings (layout, window count, overflow, spacing, margins, tile weights), keyed by display UUID.
- Bundle identifiers of apps you excluded.
- Learned minimum sizes per bundle identifier.
- Shortcut overrides and appearance settings.

If the file cannot be read it is moved aside as `config.json.corrupt-<timestamp>` (the newest 5 are kept) so it can be inspected; these hold the same kind of data as the config. `UserDefaults` is not used. Login-item state is held by macOS (`SMAppService`).

Never stored: window titles, document names or contents, screenshots, keystrokes, window or AX references, process ids.

## Network behavior

None. The app opens no sockets and makes no HTTP requests. You can confirm with Little Snitch / `nettop`.

## Logs

`os.Logger` events (placement failures, shortcut registration errors) contain error descriptions and counts only. No titles or document names are ever interpolated.

## Removing your data

Quit TidyDesk, then:

```bash
rm -rf ~/Library/Application\ Support/TidyDesk
tccutil reset Accessibility com.niajiri.tidydesk      # revoke the Accessibility grant
```

Or use Settings → General → *Reset All Settings*. Turn off *Start at login* before deleting the app.
