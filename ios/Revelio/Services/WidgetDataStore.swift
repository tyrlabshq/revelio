import Foundation
import WidgetKit

/// Writes a small summary payload to the shared App Group container that the
/// `RevelioWidget` extension reads from. After each write we poke WidgetKit
/// so the timeline is rebuilt immediately rather than waiting 30 minutes.
///
/// Callers: `PantryManager` (on score recompute) and `HistoryManager`
/// (on scan recorded).
enum WidgetDataStore {
    static let appGroup = "group.app.revelio"
    static let payloadKey = "widget.householdScore.v1"

    struct Payload: Codable {
        let householdScore: Int
        let grade: String
        let streakDays: Int
        let lastScanGrade: String?
        let itemCount: Int
        let updatedAt: Date
    }

    /// Persist the latest snapshot and reload all timelines. Safe to call
    /// frequently — the underlying `UserDefaults` write is cheap.
    static func write(
        householdScore: Int,
        grade: String,
        streakDays: Int,
        lastScanGrade: String?,
        itemCount: Int
    ) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            // App Group not yet enabled in Xcode — silently skip.
            return
        }
        let payload = Payload(
            householdScore: householdScore,
            grade: grade,
            streakDays: streakDays,
            lastScanGrade: lastScanGrade,
            itemCount: itemCount,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            defaults.set(data, forKey: payloadKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Read the most recently written payload (useful for tests / debug UI).
    static func read() -> Payload? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: payloadKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Payload.self, from: data)
    }

    // MARK: - Recent scans (Watch + widget surface)

    /// Key under which the rolling "last 5 scans" list is persisted in the
    /// same App Group. The Watch app's Recent Scans tab reads this, and a
    /// future Smart Stack widget can surface it too.
    static let lastScansKey = "widget.lastScans.v1"

    /// One entry in the capped rolling history. Kept intentionally tiny —
    /// no ingredients, no flags, no images. The Watch app only needs name
    /// + grade to render a list row.
    struct RecentScan: Codable, Identifiable {
        let barcode: String
        let name: String
        let grade: String
        let scannedAt: Date
        var id: String { barcode + "|" + scannedAt.timeIntervalSince1970.description }
    }

    /// Append a new scan to the `lastScans` ring, dedup-ing on barcode and
    /// capping at 5 entries (most-recent-first). Call this from the main
    /// app's scan success path — safe to call often.
    static func writeLastScan(barcode: String, name: String, grade: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var existing: [RecentScan] = []
        if let data = defaults.data(forKey: lastScansKey),
           let decoded = try? decoder.decode([RecentScan].self, from: data) {
            existing = decoded
        }

        // Drop any prior entry for the same barcode so the rolling list
        // always reflects the latest scan of that product, not a stale row.
        existing.removeAll { $0.barcode == barcode }

        let entry = RecentScan(barcode: barcode, name: name, grade: grade, scannedAt: Date())
        existing.insert(entry, at: 0)
        if existing.count > 5 { existing = Array(existing.prefix(5)) }

        if let data = try? encoder.encode(existing) {
            defaults.set(data, forKey: lastScansKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Read the rolling "last 5 scans" list. Returns an empty array if the
    /// App Group has not yet been populated.
    static func readLastScans() -> [RecentScan] {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: lastScansKey) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecentScan].self, from: data)) ?? []
    }
}
