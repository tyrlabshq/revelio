# iOS Swift Package Dependencies To Add

The OCR/offline agent introduced offline-first storage backed by SQLCipher
but could not safely edit `Revelio.xcodeproj/project.pbxproj`. Please add
these Swift Package Manager dependencies via **File → Add Packages…** in
Xcode, then commit the resulting `project.pbxproj` changes.

## Packages

1. **GRDB.swift (with SQLCipher)**
   - URL: `https://github.com/groue/GRDB.swift.git`
   - Minimum version: `6.29.0` (or later 6.x)
   - Products to add to the `Revelio` target:
     - `GRDB` — but configured for SQLCipher. The cleanest way is to depend
       on the community SQLCipher-enabled GRDB package below instead, then
       you get encryption out of the box.

2. **GRDB.swift via `groue/GRDB.swift` branch `SQLCipher`**
   Alternative: if you prefer the SQLCipher-enabled convenience, add
   - URL: `https://github.com/duckduckgo/GRDB.swift.git` (community fork
     with SQLCipher baked in) OR
   - Vanilla GRDB + `sqlcipher/sqlcipher` via CocoaPods.

### Recommended path (pure SPM)

Add:
- `https://github.com/groue/GRDB.swift.git` — pick the `GRDBCipher` product
  if it exists in the version you select. Otherwise you will need to:
  1. Add SQLCipher as a separate SPM dep
     (`https://github.com/sqlcipher/sqlcipher.git`)
  2. Configure GRDB with `-D SQLITE_HAS_CODEC`.

## Files that import GRDB

- `ios/Revelio/Services/LocalDatabase.swift`
- `ios/Revelio/Services/HistoryManager.swift`
- `ios/Revelio/Services/PantryManager.swift`

## Keychain note

The passphrase entry uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which means the DB is
inaccessible until the user has unlocked the device at least once after a
reboot. If CI needs pre-unlock access, switch to
`kSecAttrAccessibleAlwaysThisDeviceOnly` in debug builds only.

## Info.plist additions required

- `NSCameraUsageDescription` — "Revelio uses the camera to read ingredient
  labels when a barcode isn't in our database."
- `NSPhotoLibraryUsageDescription` — "Revelio can score ingredient labels
  from photos in your library."

(The main session owns Info.plist per the plan, so these strings are
forwarded rather than written here.)

---

## Home-Screen Widget (RevelioWidget)

- **App Group** `group.app.revelio` must be enabled on BOTH targets:
  - Main app target (`Revelio`)
  - Widget extension target (`RevelioWidget`)
  Add via **Signing & Capabilities → + Capability → App Groups**. The shared
  group is how `WidgetDataStore` (main app) hands the household score, streak,
  and last-scan grade over to the widget's `TimelineProvider`.
- **Widget extension target**: a new Widget Extension target named
  `RevelioWidget` must be created in Xcode (File → New → Target → Widget
  Extension). Point it at the existing `ios/RevelioWidget/` directory so the
  Swift files and `Info.plist` are picked up. The target should NOT include
  "Configuration Intent".
- **Deployment target** for the widget extension: iOS 17.0 (matches app).

---

## App Clip (RevelioAppClip)

- **New target**: File → New → Target → **App Clip**. Name it
  `RevelioAppClip`, bundle id `app.revelio.Revelio.Clip` (must match the AASA
  manifest at `backend/src/routes/well-known.ts`).
- Point it at the existing `ios/RevelioAppClip/` directory so the two Swift
  files, `Info.plist`, and `RevelioAppClip.entitlements` are picked up.
- **Signing & Capabilities** → add "Associated Domains" and set it to
  `appclips:revelio.app`. Xcode wires the entitlement into the provisioning
  profile.
- **Parent app identifier** in the entitlements is already set to
  `$(AppIdentifierPrefix)app.revelio.Revelio` — confirm it matches the main
  app's bundle id when you create the target.
- Deployment target: iOS 17.0.
- No SPM dependencies required — the clip deliberately uses plain
  `URLSession` and local model stubs instead of linking against the main
  app's sources (10 MB cap).

---

## watchOS companion (RevelioWatch)

- **New targets** (two):
  1. **Watch App** — File → New → Target → **Watch App** (not the legacy
     "Watch App for iOS App" template). Name it `RevelioWatch`, bundle id
     `app.revelio.Revelio.watchkitapp`. Point it at `ios/RevelioWatch/` so
     `RevelioWatchApp.swift` and `WatchRootView.swift` are picked up.
     Deployment target: watchOS 10.0.
  2. **Watch Widget Extension** (for the complication) — File → New → Target
     → **Widget Extension**, choose "Include Live Activity" = NO, "Include
     Configuration Intent" = NO, and set the "Embed in Application" to the
     Watch app. Name it `RevelioWatchComplication`. Point it at
     `ios/RevelioWatch/Complications/`. Deployment target: watchOS 10.0.
- **App Group** `group.app.revelio` must be enabled on BOTH the watch app
  target AND the watch complication target, same as the main app.
- **No network code**: the watch talks only to the shared App Group and to
  the paired iPhone via `WKExtension.shared().openSystemURL(revelio://scan)`.
- Because the Watch target doesn't link the main app's sources, the payload
  types and App Group keys are duplicated in `WatchRootView.swift` /
  `Complications/RevelioComplicationController.swift`. Keep the keys in
  sync with `ios/Revelio/Services/WidgetDataStore.swift`.

---

## Live Activity (added to existing RevelioWidget bundle)

- `ios/RevelioWidget/ScanLiveActivity.swift` is a NEW file that must be
  added to the **RevelioWidget** extension target (same target as
  `HouseholdScoreWidget.swift`). It is registered as a sibling `Widget` in
  the existing `RevelioWidgetBundle`.
- **Info.plist** on the MAIN app target (`ios/Revelio/Info.plist`) must gain:
  ```xml
  <key>NSSupportsLiveActivities</key>
  <true/>
  ```
  Without this key ActivityKit silently refuses `Activity.request(...)`.
- No capability toggle is required — Live Activities are gated on the
  Info.plist key and the user's system-wide Settings toggle
  (`ActivityAuthorizationInfo().areActivitiesEnabled`), both of which
  `ScanActivityService` checks before every mutation.
- **Model file**: `ios/Revelio/Models/ScanActivityAttributes.swift` must be
  added to BOTH targets (main app + RevelioWidget extension) — the
  `ActivityAttributes` conforming type has to be visible on both sides of
  the IPC.
