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
