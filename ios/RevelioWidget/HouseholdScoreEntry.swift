import WidgetKit
import Foundation

/// Timeline entry describing a household-score snapshot for the home-screen widget.
/// Produced by `HouseholdScoreProvider` from the shared App Group container that the
/// main app writes via `WidgetDataStore`.
struct HouseholdScoreEntry: TimelineEntry {
    let date: Date
    let householdScore: Int
    let householdGrade: String
    let streakDays: Int
    let lastScanGrade: String?
    let itemCount: Int

    static let placeholder = HouseholdScoreEntry(
        date: Date(),
        householdScore: 82,
        householdGrade: "B",
        streakDays: 3,
        lastScanGrade: "A",
        itemCount: 12
    )

    static let empty = HouseholdScoreEntry(
        date: Date(),
        householdScore: 0,
        householdGrade: "—",
        streakDays: 0,
        lastScanGrade: nil,
        itemCount: 0
    )
}
