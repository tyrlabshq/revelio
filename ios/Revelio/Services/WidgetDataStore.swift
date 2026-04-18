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
}
