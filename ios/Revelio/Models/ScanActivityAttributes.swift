import ActivityKit
import Foundation

/// Live Activity schema for in-progress scans. An Activity is what
/// powers the Lock Screen banner, the compact Dynamic Island leading /
/// trailing pills, and the expanded Dynamic Island layout while a scan
/// is in flight.
///
/// Lifecycle:
///   1. `ScanViewModel.handleBarcode` → `.start(barcode:)` → phase = `.scanning`
///   2. Network call kicks off   → `.updateFetching()`    → phase = `.fetching`
///   3a. 200 OK                  → `.finish(grade:…)`      → phase = `.scored`
///   3b. 404 / network fail       → `.fail()`              → phase = `.failed`
///
/// Static attributes (`ScanActivityAttributes`) do not change over the
/// life of the activity — right now there's nothing we need to stash
/// there, so the struct is intentionally empty but retained for future
/// fields (e.g. kid-safe target, family member profile id).
struct ScanActivityAttributes: ActivityAttributes {
    /// Protocol requires `ContentState` to be a `Codable & Hashable`
    /// nested type; see ActivityKit docs. Only ContentState can be
    /// updated after the activity starts.
    public struct ContentState: Codable, Hashable {
        enum Phase: String, Codable {
            case scanning   // camera detected a barcode, about to POST
            case fetching   // network call in flight
            case scored     // 200 OK, show the grade
            case failed     // 404 or network error
        }

        var phase: Phase
        var barcode: String
        var productName: String?
        var grade: String?
    }

    // No static attributes today. The struct is retained so we can add
    // fields (e.g. an activity id, scan origin) without migrating the
    // ActivityKit wire format later.
}
