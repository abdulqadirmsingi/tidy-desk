# Release

Target: **direct distribution** (Developer ID + notarization). The Mac App Store is not a goal: App Sandbox forbids controlling other apps' windows through Accessibility, which is the product's core function.

> Nothing in this document has been run with your Developer ID certificate yet. The build script and ad-hoc signing path were run; notarization is untested. Steps that need your credentials are marked **(you)**.

## Local vs. distribution signing

| | Local development | Distribution |
|---|---|---|
| Certificate | Apple Development | **Developer ID Application** |
| Runs on | your Mac | any Mac, after notarization |
| Notarization | no | **required** (Gatekeeper) |
| Keeps Accessibility grant across rebuilds | yes (stable identity) | yes |

Your keychain currently lists Apple Development and Apple Distribution identities (`security find-identity -v -p codesigning`). **Developer ID Application was not found**, and Apple Distribution is for the App Store — it will not pass Gatekeeper for direct downloads. **(you)** Create a *Developer ID Application* certificate in your Apple Developer account (Certificates, IDs & Profiles) or via Xcode → Settings → Accounts → Manage Certificates.

## 1. Configure

Edit `Config/branding.env` (`APP_NAME`, `BUNDLE_ID`, `VERSION`, `BUILD`, `DEVELOPER_NAME`). Increase `BUILD` for every distributed build. The bundle identifier must be one you control (the default `com.niajiri.tidydesk` is a placeholder).

## 2. Build and sign (hardened runtime)

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DIST=1 UNIVERSAL=1 scripts/build-app.sh
```

`DIST=1` adds a secure timestamp; hardened runtime (`--options runtime`) is always on. No entitlements are needed: the app uses no JIT, no library injection, no camera/mic, and Accessibility isn't an entitlement. Verify:

```bash
codesign --verify --deep --strict --verbose=2 build/TidyDesk.app
codesign -dvv build/TidyDesk.app 2>&1 | grep -E "Authority|flags|TeamIdentifier"   # flags should include "runtime"
```

## 3. Notarize

**(you)** One-time: store credentials in the keychain (nothing goes in the repo). Use an app-specific password from appleid.apple.com:

```bash
xcrun notarytool store-credentials "tidydesk-notary" --apple-id "you@example.com" --team-id "TEAMID"
```

Then:

```bash
ditto -c -k --keepParent build/TidyDesk.app build/TidyDesk-notarize.zip
xcrun notarytool submit build/TidyDesk-notarize.zip --keychain-profile "tidydesk-notary" --wait
xcrun stapler staple build/TidyDesk.app
xcrun stapler validate build/TidyDesk.app
spctl --assess --type execute --verbose build/TidyDesk.app     # expect: accepted, source=Notarized Developer ID
```

If notarization is rejected: `xcrun notarytool log <submission-id> --keychain-profile tidydesk-notary` explains why (usually an unsigned nested binary or a missing timestamp).

## 4. Package

ZIP (simple):

```bash
ditto -c -k --keepParent build/TidyDesk.app build/TidyDesk-0.1.0.zip
```

DMG (drag-to-Applications):

```bash
mkdir -p build/dmg && cp -R build/TidyDesk.app build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname "TidyDesk" -srcfolder build/dmg -ov -format UDZO build/TidyDesk-0.1.0.dmg
codesign --sign "Developer ID Application: Your Name (TEAMID)" --timestamp build/TidyDesk-0.1.0.dmg
xcrun notarytool submit build/TidyDesk-0.1.0.dmg --keychain-profile tidydesk-notary --wait
xcrun stapler staple build/TidyDesk-0.1.0.dmg
```

## 5. Install and first run

1. Open the DMG/ZIP, drag **TidyDesk** to **/Applications**, launch it.
2. Grant Accessibility in System Settings → Privacy & Security → Accessibility.
3. Optional: Settings → General → *Start at login* (uses `SMAppService`; if macOS reports "requires approval", approve it under System Settings → General → Login Items).
4. Test the downloaded (quarantined) build on a second Mac if you have one **(you)**: download via browser, open, confirm Gatekeeper accepts it without warnings.

## Updating

There is no updater. To update, quit the app, replace it in /Applications, relaunch. Settings persist (they live in `~/Library/Application Support/TidyDesk`). If you later add an updater, use a signature-verifying framework (e.g. Sparkle with EdDSA keys), download over HTTPS only, and ask the user before installing.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "can't be opened because Apple cannot check it" | Not notarized/stapled, or quarantined ZIP re-signed. Re-run step 3 and re-package *after* stapling. |
| Accessibility grant doesn't stick | Signature identity changed. Use a stable certificate, or `tccutil reset Accessibility <bundle id>` and re-grant. |
| Notary rejects with "not signed with a valid Developer ID" | You used an Apple Development/Distribution cert. Use Developer ID Application. |
| Start at Login does nothing | App must be in /Applications; check Login Items in System Settings. |
