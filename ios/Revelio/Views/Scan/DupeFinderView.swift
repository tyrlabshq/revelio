// REV-T3.4: Dupe Finder — horizontal carousel on the scan result screen.
// Each card shows image, brand, name, grade, a short "why it matches"
// one-liner, and an affiliate CTA. The one-liner is fetched lazily from an
// ingredient-explain-style endpoint and cached aggressively in-memory.

import SwiftUI

// MARK: - Model

struct DupeResult: Identifiable, Decodable {
    let barcode: String
    let name: String
    let brand: String
    let category: String
    let imageUrl: String?
    let score: Int
    let grade: String
    let affiliateUrl: String
    let affiliateNetwork: String

    var id: String { barcode }
}

private struct DupesResponse: Decodable {
    let sourceBarcode: String?
    let sourceScore: Int?
    let sourceGrade: String?
    let dupes: [DupeResult]
}

// MARK: - ViewModel

@MainActor
final class DupeFinderViewModel: ObservableObject {
    @Published var dupes: [DupeResult] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    // In-memory cache for the "Why it matches" blurb, keyed by
    // "sourceBarcode|dupeBarcode".
    @Published private(set) var whyCache: [String: String] = [:]

    private let baseURL: String

    init(baseURL: String = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app") {
        self.baseURL = baseURL
    }

    func fetch(barcode: String, token: String?, limit: Int = 3) async {
        guard !barcode.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/products/\(barcode)/dupes?limit=\(limit)") else {
            error = "Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                error = "Unable to load dupes"
                return
            }
            let decoded = try JSONDecoder().decode(DupesResponse.self, from: data)
            self.dupes = decoded.dupes
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadWhy(source: String, dupe: DupeResult, token: String?) async {
        let key = "\(source)|\(dupe.barcode)"
        if whyCache[key] != nil { return }

        // Reuse the ingredient explain endpoint: ask for a one-liner about
        // "why this product matches". Aggressive caching means we only hit
        // OpenAI once per (source, dupe) pair per app session.
        guard let url = URL(string: "\(baseURL)/ingredients/match-\(dupe.barcode)/explain?priorities=dupe_match&category=\(dupe.category)") else {
            return
        }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = obj["explanation"] as? String {
                whyCache[key] = text
            }
        } catch {
            // Non-fatal: silently fall back to the generic one-liner.
        }
    }
}

// MARK: - View

struct DupeFinderView: View {
    let sourceBarcode: String
    @StateObject private var vm = DupeFinderViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if vm.isLoading {
                loadingRow
            } else if let err = vm.error, vm.dupes.isEmpty {
                errorRow(err)
            } else if vm.dupes.isEmpty {
                emptyRow
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.dupes) { dupe in
                            DupeCard(
                                dupe: dupe,
                                whyBlurb: vm.whyCache["\(sourceBarcode)|\(dupe.barcode)"],
                                onAppear: {
                                    Task {
                                        await vm.loadWhy(source: sourceBarcode, dupe: dupe, token: authViewModel.loadToken())
                                    }
                                }
                            )
                            .frame(width: 240)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task {
            await vm.fetch(barcode: sourceBarcode, token: authViewModel.loadToken())
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cleaner Dupes")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text("Same flavor, better grade")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, 16)
    }

    private var loadingRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.surfaceElevated)
                    .frame(width: 240, height: 220)
                    .overlay(ProgressView())
            }
        }
        .padding(.horizontal, 16)
    }

    private func errorRow(_ msg: String) -> some View {
        Text(msg)
            .font(.caption)
            .foregroundColor(Theme.textDim)
            .padding(.horizontal, 16)
    }

    private var emptyRow: some View {
        Text("No cleaner dupes found in this category yet.")
            .font(.caption)
            .foregroundColor(Theme.textDim)
            .padding(.horizontal, 16)
    }
}

// MARK: - Card

private struct DupeCard: View {
    let dupe: DupeResult
    let whyBlurb: String?
    let onAppear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Image
            AsyncImage(url: URL(string: dupe.imageUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.surfaceElevated)
                        .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Brand + Name
            VStack(alignment: .leading, spacing: 2) {
                Text(dupe.brand)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Text(dupe.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            }

            // Grade badge + score
            HStack {
                ZStack {
                    Circle()
                        .fill(Theme.gradeColor(dupe.grade).opacity(0.15))
                        .frame(width: 34, height: 34)
                    Text(dupe.grade)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.gradeColor(dupe.grade))
                }
                Text("\(dupe.score)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }

            // Why it matches
            Text(whyBlurb ?? "Similar flavor profile and use-case in \(dupe.category).")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(3)

            // CTA
            Link(destination: URL(string: dupe.affiliateUrl) ?? URL(string: "https://revelio.app")!) {
                HStack(spacing: 6) {
                    Image(systemName: "cart.fill")
                    Text("Shop")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.accent)
                .cornerRadius(10)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .onAppear(perform: onAppear)
    }
}

#Preview {
    DupeFinderView(sourceBarcode: "049000006346")
        .environmentObject(AuthViewModel())
}
