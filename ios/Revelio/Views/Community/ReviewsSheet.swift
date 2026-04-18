// ─── ios/Revelio/Views/Community/ReviewsSheet.swift ──────────────────────────
// Track 3.7 — community reviews bottom sheet, presented from the scan-result
// screen. Lists existing reviews and lets phone-verified users post one.

import SwiftUI

// ─── Models ──────────────────────────────────────────────────────────────────

struct CommunityReview: Identifiable, Decodable {
    let rating: Int
    let body: String?
    let createdAt: String

    var id: String { createdAt + String(rating) + (body ?? "") }
}

struct ReviewsResponse: Decodable {
    let barcode: String
    let avg: Double
    let count: Int
    let reviews: [CommunityReview]
}

// ─── Sheet ───────────────────────────────────────────────────────────────────

struct ReviewsSheet: View {
    let barcode: String
    let productName: String
    let authToken: String?  // nil → write form disabled

    @State private var avg: Double = 0
    @State private var count: Int = 0
    @State private var reviews: [CommunityReview] = []

    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    @State private var draftRating: Int = 0
    @State private var draftBody: String = ""
    @State private var isSubmitting = false
    @State private var submitError: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var apiBase: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Summary card
                    VStack(spacing: 10) {
                        Text(productName)
                            .font(Theme.fontHeadline)
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            StarRow(rating: avg, size: 20)
                            Text(String(format: "%.1f", avg))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.textPrimary)
                            Text("(\(count))")
                                .font(Theme.fontCaption)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Theme.surface)
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    // Write a review
                    if authToken != nil {
                        writeForm
                    } else {
                        Text("Sign in to write a review.")
                            .font(Theme.fontCaption)
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.surfaceElevated)
                            .cornerRadius(10)
                            .padding(.horizontal, 20)
                    }

                    // List
                    if isLoading {
                        ProgressView().padding(.top, 40)
                    } else if let err = errorMessage {
                        Text(err).font(Theme.fontCaption).foregroundColor(Theme.danger)
                    } else if reviews.isEmpty {
                        Text("No reviews yet — be the first.")
                            .font(Theme.fontBody)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.top, 20)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(reviews) { r in
                                ReviewRow(review: r)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 14)
            }
            .background(Theme.background)
            .navigationTitle("Reviews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .task { await loadReviews() }
    }

    // ── Write form ────────────────────────────────────────────────────────────

    private var writeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WRITE A REVIEW")
                .font(Theme.fontLabel)
                .foregroundColor(Theme.textDim)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        draftRating = i
                    } label: {
                        Image(systemName: i <= draftRating ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundColor(i <= draftRating ? Theme.warning : Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            TextEditor(text: $draftBody)
                .frame(height: 100)
                .font(Theme.fontBody)
                .padding(8)
                .background(Theme.surfaceElevated)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )

            if let err = submitError {
                Text(err).font(Theme.fontCaption).foregroundColor(Theme.danger)
            }

            Button {
                Task { await submitReview() }
            } label: {
                HStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(isSubmitting ? "Submitting…" : "Post review")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(draftRating == 0 ? Theme.textDim : Theme.accent)
                .cornerRadius(10)
            }
            .disabled(draftRating == 0 || isSubmitting)
        }
        .padding(.horizontal, 20)
    }

    // ── Network ──────────────────────────────────────────────────────────────

    private func loadReviews() async {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "\(apiBase)/community/reviews/\(barcode)") else {
            errorMessage = "Bad URL"; isLoading = false; return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 {
                errorMessage = "Could not load reviews (\(code))"
                isLoading = false
                return
            }
            let parsed = try JSONDecoder().decode(ReviewsResponse.self, from: data)
            avg = parsed.avg
            count = parsed.count
            reviews = parsed.reviews
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitReview() async {
        guard let token = authToken else { return }
        guard draftRating >= 1 && draftRating <= 5 else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        guard let url = URL(string: "\(apiBase)/community/reviews") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let bodyTrimmed = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "barcode": barcode,
            "rating": draftRating,
            "body": bodyTrimmed,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 201 || code == 200 {
                draftBody = ""
                draftRating = 0
                await loadReviews()
            } else {
                submitError = "Server error (\(code))"
            }
        } catch {
            submitError = error.localizedDescription
        }
    }
}

// ─── Row ─────────────────────────────────────────────────────────────────────

private struct ReviewRow: View {
    let review: CommunityReview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StarRow(rating: Double(review.rating), size: 14)
                Spacer()
                Text(prettyDate(review.createdAt))
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.textDim)
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
                    .font(Theme.fontBody)
                    .foregroundColor(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .cornerRadius(12)
    }

    private func prettyDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let rf = RelativeDateTimeFormatter()
            rf.unitsStyle = .short
            return rf.localizedString(for: d, relativeTo: Date())
        }
        return ""
    }
}

// ─── Star row ────────────────────────────────────────────────────────────────

private struct StarRow: View {
    let rating: Double
    let size: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let threshold = Double(i) + 0.5
                Image(systemName: rating >= Double(i + 1)
                      ? "star.fill"
                      : (rating >= threshold ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundColor(rating >= threshold ? Theme.warning : Theme.textDim)
            }
        }
    }
}
