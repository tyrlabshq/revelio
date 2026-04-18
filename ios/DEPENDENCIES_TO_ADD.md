# iOS Dependencies / Capabilities To Add Manually

Track anything that can't be configured purely from source — Xcode UI is
required. Append-only; do not rewrite historical entries.

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
