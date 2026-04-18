// ─── ios/Revelio/Views/Explore/HallOfShameView.swift ─────────────────────────
// Track 3.7 — community-driven leaderboard of most voted-against products
// (last 30 days). Reads are public; an optional auth token enables the
// "vote" action inline.

import SwiftUI

// ─── Models ──────────────────────────────────────────────────────────────────

struct HallOfShameEntry: Identifiable, Decodable {
    let barcode: String
    let votes: Int
    let productName: String
    let brand: String
    let imageUrl: String?
    let category: String?
    let grade: String?
    let score: Int?

    var id: String { barcode }
}

struct HallOfShameResponse: Decodable {
    let window: String
    let entries: [HallOfShameEntry]
}

// ─── View ────────────────────────────────────────────────────────────────────

struct HallOfShameView: View {
    let authToken: String?

    @State private var entries: [HallOfShameEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var votingBarcodes: Set<String> = []

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if let err = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.warning)
                        Text(err)
                            .font(Theme.fontBody)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, 40)
                } else if entries.isEmpty {
                    Text("No votes yet in the last 30 days.")
                        .font(Theme.fontBody)
                        .foregroundColor(Theme.textSecondary)
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                            HallOfShameRow(
                                rank: idx + 1,
                                entry: entry,
                                canVote: authToken != nil,
                                isVoting: votingBarcodes.contains(entry.barcode),
                                onVote: { Task { await vote(on: entry.barcode) } }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Hall of Shame")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Most voted against")
                .font(Theme.fontHeadline)
                .foregroundColor(Theme.textPrimary)
            Text("Community-flagged products over the last 30 days.")
                .font(Theme.fontCaption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── Network ──────────────────────────────────────────────────────────────

    private func load() async {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "\(apiBase)/community/hall-of-shame?limit=20") else {
            errorMessage = "Bad URL"; isLoading = false; return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                errorMessage = "Failed to load (\(code))"
                isLoading = false
                return
            }
            let parsed = try JSONDecoder().decode(HallOfShameResponse.self, from: data)
            entries = parsed.entries
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func vote(on barcode: String) async {
        guard let token = authToken else { return }
        guard !votingBarcodes.contains(barcode) else { return }
        votingBarcodes.insert(barcode)
        defer { votingBarcodes.remove(barcode) }

        guard let url = URL(string: "\(apiBase)/community/hall-of-shame/\(barcode)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
        await load()
    }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

private struct HallOfShameRow: View {
    let rank: Int
    let entry: HallOfShameEntry
    let canVote: Bool
    let isVoting: Bool
    let onVote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(rank)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.textDim)
                .frame(width: 44, alignment: .leading)

            // Image
            productImage

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.productName)
                    .font(Theme.fontHeadline)
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                Text(entry.brand)
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.textSecondary)
                HStack(spacing: 8) {
                    if let grade = entry.grade {
                        gradeBadge(grade)
                    }
                    Text("\(entry.votes) vote\(entry.votes == 1 ? "" : "s")")
                        .font(Theme.fontCaption)
                        .foregroundColor(Theme.danger)
                }
            }

            Spacer(minLength: 6)

            // Vote button
            if canVote {
                Button(action: onVote) {
                    if isVoting {
                        ProgressView().tint(Theme.danger)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Theme.danger)
                            .clipShape(Circle())
                    }
                }
                .disabled(isVoting)
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(14)
    }

    @ViewBuilder
    private var productImage: some View {
        if let urlStr = entry.imageUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.1)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.08))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "cube.box.fill")
                        .foregroundColor(Theme.textDim)
                )
        }
    }

    private func gradeBadge(_ grade: String) -> some View {
        Text(grade)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 28, height: 22)
            .background(Theme.gradeColor(grade))
            .cornerRadius(6)
    }
}
