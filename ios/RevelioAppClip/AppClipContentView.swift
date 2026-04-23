import SwiftUI

// MARK: - Local models (intentionally duplicated from the main app)
//
// App Clips have a 10 MB cap, so we deliberately decode only the fields
// the score card needs rather than pulling in the full `ScanResult` from
// `ios/Revelio/Models/Models.swift`. If the server payload grows new
// required fields, add them here too.

struct ClipScanResult: Decodable {
    let barcode: String
    let productName: String
    let brand: String
    let grade: String
    let personalizedScore: Int
    let imageUrl: String?
    let flags: [ClipFlag]?
}

struct ClipFlag: Decodable, Identifiable {
    let id: String
    let ingredient: String
    let severity: Int
    let reason: String
}

// MARK: - View

/// Top-level UI for the App Clip. Three visual states — loading,
/// success (compact score card), and error. No pantry, no history, no
/// auth; we hit the public `/scan/:barcode` endpoint and render.
struct AppClipContentView: View {
    @EnvironmentObject private var state: AppClipState

    @State private var isLoading = false
    @State private var result: ClipScanResult?
    @State private var errorMessage: String?

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                header
                Spacer()
                content
                Spacer()
                installPrompt
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .onChange(of: state.barcode) { _, newValue in
            if let barcode = newValue {
                Task { await fetch(barcode: barcode) }
            }
        }
        .onAppear {
            if let barcode = state.barcode, result == nil {
                Task { await fetch(barcode: barcode) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Revelio")
                .font(.system(size: 22, weight: .black, design: .rounded))
            Spacer()
            Text("Instant Scan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Analyzing…")
                .progressViewStyle(.circular)
        } else if let result {
            scoreCard(result)
        } else if let errorMessage {
            errorCard(errorMessage)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.secondary)
            Text("Open a revelio.app/p/<barcode> link to get an instant score.")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    private func scoreCard(_ result: ClipScanResult) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(gradeColor(result.grade).opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(result.personalizedScore) / 100.0)
                    .stroke(gradeColor(result.grade),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(result.personalizedScore)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                    Text(result.grade)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(gradeColor(result.grade))
                }
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 4) {
                Text(result.productName)
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(result.brand)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if let flags = result.flags, !flags.isEmpty {
                let top = Array(flags.sorted(by: { $0.severity > $1.severity }).prefix(3))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(top) { flag in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(severityColor(flag.severity))
                                .frame(width: 8, height: 8)
                            Text(flag.ingredient)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }

    // MARK: Install prompt

    private var installPrompt: some View {
        VStack(spacing: 6) {
            Text("Want personalized scores, Dupe Finder, and history?")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Text("Get Revelio")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                )
        }
    }

    // MARK: Fetch

    private func fetch(barcode: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(apiBase)/scan/\(barcode)") else {
            errorMessage = "Invalid barcode."
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "No response from server."
                return
            }
            if http.statusCode == 404 {
                errorMessage = "We don't have this product yet."
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Server error (\(http.statusCode))."
                return
            }
            let decoded = try JSONDecoder().decode(ClipScanResult.self, from: data)
            result = decoded
        } catch {
            errorMessage = "Couldn't reach Revelio. Check your connection."
        }
    }

    // MARK: Colors

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "B": return Color(red: 0.52, green: 0.80, blue: 0.09)
        case "C": return Color(red: 0.96, green: 0.62, blue: 0.04)
        case "D": return Color(red: 0.98, green: 0.45, blue: 0.09)
        default:  return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }

    private func severityColor(_ severity: Int) -> Color {
        switch severity {
        case 3: return .red
        case 2: return .orange
        case 1: return .yellow
        default: return .green
        }
    }
}
