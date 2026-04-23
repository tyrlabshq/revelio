import SwiftUI
import WatchKit

// MARK: - Shared payloads (mirrors WidgetDataStore in the main app)
//
// The Watch target doesn't link against the iPhone app's source, so we
// redeclare the payload types here. Keys must stay in sync with
// `WidgetDataStore.swift`.

private let kAppGroupSuite = "group.app.revelio"
private let kHouseholdKey = "widget.householdScore.v1"
private let kLastScansKey = "widget.lastScans.v1"

private struct HouseholdPayload: Decodable {
    let householdScore: Int
    let grade: String
    let streakDays: Int
    let lastScanGrade: String?
    let itemCount: Int?
    let updatedAt: Date
}

private struct RecentScanPayload: Decodable, Identifiable {
    let barcode: String
    let name: String
    let grade: String
    let scannedAt: Date
    var id: String { barcode + "|" + scannedAt.timeIntervalSince1970.description }
}

private enum WatchStore {
    static func readHousehold() -> HouseholdPayload? {
        guard let d = UserDefaults(suiteName: kAppGroupSuite),
              let data = d.data(forKey: kHouseholdKey) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(HouseholdPayload.self, from: data)
    }

    static func readRecentScans() -> [RecentScanPayload] {
        guard let d = UserDefaults(suiteName: kAppGroupSuite),
              let data = d.data(forKey: kLastScansKey) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([RecentScanPayload].self, from: data)) ?? []
    }
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

// MARK: - Root

struct WatchRootView: View {
    var body: some View {
        TabView {
            HouseholdGlanceView()
                .tag(0)
            QuickScanHandoffView()
                .tag(1)
            RecentScansListView()
                .tag(2)
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Tab 1: Household Score Glance

struct HouseholdGlanceView: View {
    @State private var payload: HouseholdPayload?

    var body: some View {
        VStack(spacing: 6) {
            Text("Household")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            if let payload {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(payload.householdScore)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(gradeColor(payload.grade))
                    Text(payload.grade)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(gradeColor(payload.grade))
                }

                if payload.streakDays > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(payload.streakDays)-day streak")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                if let last = payload.lastScanGrade {
                    HStack(spacing: 4) {
                        Text("Last scan")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(last)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(gradeColor(last))
                    }
                }
            } else {
                Text("No data yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Open Revelio on your iPhone")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear { payload = WatchStore.readHousehold() }
    }
}

// MARK: - Tab 2: Quick Scan Handoff

struct QuickScanHandoffView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(gradeColor("A"))

            Text("Scan on iPhone")
                .font(.system(size: 15, weight: .bold))

            Text("Tap to open the scanner on your paired iPhone.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: handoff) {
                Text("Scan →")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(gradeColor("A"))
        }
        .padding()
    }

    /// WatchKit's `openSystemURL` is the official way to route a URL to
    /// the paired iPhone when the scheme isn't handled on-watch. The
    /// iPhone app registers `revelio://scan` in Info.plist and hands it
    /// to `UniversalLinkHandler`.
    private func handoff() {
        guard let url = URL(string: "revelio://scan") else { return }
        WKExtension.shared().openSystemURL(url)
    }
}

// MARK: - Tab 3: Recent Scans

struct RecentScansListView: View {
    @State private var scans: [RecentScanPayload] = []

    var body: some View {
        List {
            Section(header: Text("Recent")) {
                if scans.isEmpty {
                    Text("No scans yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(scans) { scan in
                        HStack(spacing: 8) {
                            Text(scan.grade)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(gradeColor(scan.grade)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scan.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(scan.scannedAt, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { scans = WatchStore.readRecentScans() }
    }
}
