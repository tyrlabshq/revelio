import WidgetKit
import SwiftUI

// MARK: - Constants

/// App Group shared with the main Revelio target. Must be added to both target
/// capabilities in Xcode before the widget can read any data.
private let kAppGroupSuite = "group.app.revelio"
private let kWidgetPayloadKey = "widget.householdScore.v1"

// MARK: - TimelineProvider

struct HouseholdScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> HouseholdScoreEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HouseholdScoreEntry) -> Void) {
        completion(readEntry() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HouseholdScoreEntry>) -> Void) {
        let entry = readEntry() ?? .empty
        // Refresh every 30 minutes; the main app additionally calls
        // WidgetCenter.shared.reloadAllTimelines() whenever it writes new data.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Decode the shared payload written by `WidgetDataStore` in the main app.
    private func readEntry() -> HouseholdScoreEntry? {
        guard let defaults = UserDefaults(suiteName: kAppGroupSuite),
              let data = defaults.data(forKey: kWidgetPayloadKey) else {
            return nil
        }
        struct Payload: Decodable {
            let householdScore: Int
            let grade: String
            let streakDays: Int
            let lastScanGrade: String?
            let itemCount: Int?
            let updatedAt: Date
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            return nil
        }
        return HouseholdScoreEntry(
            date: payload.updatedAt,
            householdScore: payload.householdScore,
            householdGrade: payload.grade,
            streakDays: payload.streakDays,
            lastScanGrade: payload.lastScanGrade,
            itemCount: payload.itemCount ?? 0
        )
    }
}

// MARK: - Grade color helper

private func gradeColor(_ grade: String) -> Color {
    switch grade {
    case "A": return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "B": return Color(red: 0.52, green: 0.80, blue: 0.09)
    case "C": return Color(red: 0.96, green: 0.62, blue: 0.04)
    case "D": return Color(red: 0.98, green: 0.45, blue: 0.09)
    default:  return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}

// MARK: - Views

struct HouseholdScoreWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HouseholdScoreEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Household")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if entry.streakDays > 0 {
                    Label("\(entry.streakDays)", systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(.orange)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.householdScore)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(gradeColor(entry.householdGrade))
                Text(entry.householdGrade)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(gradeColor(entry.householdGrade))
            }

            Spacer(minLength: 0)

            if let last = entry.lastScanGrade {
                Text("Last scan · \(last)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text("No scans yet")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            // Score block
            VStack(alignment: .leading, spacing: 6) {
                Text("Household Clean Score")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.householdScore)")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(gradeColor(entry.householdGrade))
                    Text(entry.householdGrade)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(gradeColor(entry.householdGrade))
                }
                if entry.itemCount > 0 {
                    Text("\(entry.itemCount) items tracked")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            // Streak + last scan
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    Text("\(entry.streakDays)-day")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Text("streak")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                if let last = entry.lastScanGrade {
                    HStack(spacing: 4) {
                        Text("Last scan")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(last)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(gradeColor(last))
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Widget

struct HouseholdScoreWidget: Widget {
    let kind: String = "HouseholdScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HouseholdScoreProvider()) { entry in
            if #available(iOS 17.0, *) {
                HouseholdScoreWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                HouseholdScoreWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("Household Score")
        .description("Your household's clean score, streak, and last scan at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
