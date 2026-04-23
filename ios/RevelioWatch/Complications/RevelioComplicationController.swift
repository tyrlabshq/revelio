import SwiftUI
import WidgetKit

// MARK: - Shared payload (mirrors WidgetDataStore / WatchRootView)

private let kAppGroupSuite = "group.app.revelio"
private let kHouseholdKey = "widget.householdScore.v1"

private struct HouseholdPayload: Decodable {
    let householdScore: Int
    let grade: String
    let streakDays: Int
    let lastScanGrade: String?
    let itemCount: Int?
    let updatedAt: Date
}

private func readHousehold() -> HouseholdPayload? {
    guard let d = UserDefaults(suiteName: kAppGroupSuite),
          let data = d.data(forKey: kHouseholdKey) else { return nil }
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(HouseholdPayload.self, from: data)
}

private func gradeColor(_ grade: String) -> Color {
    switch grade {
    case "A": return Color(red: 0.13, green: 0.77, blue: 0.37)
    case "B": return Color(red: 0.52, green: 0.80, blue: 0.09)
    case "C": return Color(red: 0.96, green: 0.62, blue: 0.04)
    case "D": return Color(red: 0.98, green: 0.45, blue: 0.09)
    default:  return Color(red: 0.94, green: 0.27, blue: 0.27)
    }
}

// MARK: - Timeline

struct HouseholdComplicationEntry: TimelineEntry {
    let date: Date
    let score: Int
    let grade: String
}

struct HouseholdComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> HouseholdComplicationEntry {
        HouseholdComplicationEntry(date: Date(), score: 82, grade: "B")
    }

    func getSnapshot(in context: Context, completion: @escaping (HouseholdComplicationEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HouseholdComplicationEntry>) -> Void) {
        // Pair-app is the source of truth; a 30 minute refresh is plenty
        // since the iPhone also pokes WidgetCenter after every write.
        let entry = currentEntry()
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func currentEntry() -> HouseholdComplicationEntry {
        if let payload = readHousehold() {
            return HouseholdComplicationEntry(
                date: payload.updatedAt,
                score: payload.householdScore,
                grade: payload.grade
            )
        }
        return HouseholdComplicationEntry(date: Date(), score: 0, grade: "-")
    }
}

// MARK: - Views

/// Circular complication: a thick ring whose stroke encodes the score
/// 0–100, overlaid with the letter grade. Chosen because the circular
/// family is supported on the most watch faces (Modular, Infograph,
/// Utilitarian, Siri) and the ring/letter combo is legible even at
/// 24pt.
struct HouseholdComplicationView: View {
    let entry: HouseholdComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCorner:
            cornerBody
        case .accessoryInline:
            inlineBody
        case .accessoryRectangular:
            rectangularBody
        default:
            circularBody
        }
    }

    private var circularBody: some View {
        ZStack {
            Circle()
                .stroke(gradeColor(entry.grade).opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, entry.score))) / 100.0)
                .stroke(gradeColor(entry.grade),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(entry.grade)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(gradeColor(entry.grade))
        }
        .padding(2)
    }

    private var cornerBody: some View {
        Text(entry.grade)
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundColor(gradeColor(entry.grade))
            .widgetLabel {
                Text("Revelio \(entry.score)")
            }
    }

    private var inlineBody: some View {
        Text("Revelio \(entry.grade) · \(entry.score)")
    }

    private var rectangularBody: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(gradeColor(entry.grade).opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, entry.score))) / 100.0)
                    .stroke(gradeColor(entry.grade),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(entry.grade)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(gradeColor(entry.grade))
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Household")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Score \(entry.score)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
    }
}

// MARK: - Widget

/// watchOS 9+ exposes complications as `Widget`s with the same timeline
/// API used on iOS. We supply the four accessory families so users can
/// drop the complication on Modular, Utilitarian, Infograph, and the
/// Smart Stack without us having to ship separate surfaces.
@available(watchOS 9.0, *)
struct RevelioComplication: Widget {
    let kind: String = "RevelioHouseholdComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HouseholdComplicationProvider()) { entry in
            HouseholdComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Household Grade")
        .description("Your household clean score at a glance.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

/// Complication bundle entry point. Registered as the primary target of
/// the Watch app's "Complication" extension. If we add more watch
/// complications later, register them here alongside this one.
@available(watchOS 9.0, *)
@main
struct RevelioComplicationBundle: WidgetBundle {
    var body: some Widget {
        RevelioComplication()
    }
}
