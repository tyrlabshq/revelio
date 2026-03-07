import SwiftUI

// ─── API Service ───────────────────────────────────────────────────────────────

private let API_BASE = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8430"

struct ExplainerResponse: Decodable {
    let explanation: String
    let cached: Bool
}

struct ExplainerError: Decodable {
    let error: String
    let upgradeRequired: Bool?
}

enum ExplainResult {
    case explanation(String, cached: Bool)
    case rateLimitHit
    case failed(String)
}

@MainActor
func fetchIngredientExplanation(
    ingredientName: String,
    category: String,
    priorities: [String],
    authToken: String
) async -> ExplainResult {
    let encodedName = ingredientName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ingredientName
    let prioritiesParam = priorities.joined(separator: ",")
    var components = URLComponents(string: "\(API_BASE)/ingredients/\(encodedName)/explain")!
    components.queryItems = [
        URLQueryItem(name: "category", value: category),
        URLQueryItem(name: "priorities", value: prioritiesParam),
    ]

    guard let url = components.url else {
        return .failed("Invalid URL")
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 429 {
            return .rateLimitHit
        }
        if statusCode != 200 {
            let errObj = try? JSONDecoder().decode(ExplainerError.self, from: data)
            return .failed(errObj?.error ?? "Server error (\(statusCode))")
        }

        let decoded = try JSONDecoder().decode(ExplainerResponse.self, from: data)
        return .explanation(decoded.explanation, cached: decoded.cached)
    } catch {
        return .failed(error.localizedDescription)
    }
}

// ─── Explainer Sheet ──────────────────────────────────────────────────────────

struct IngredientExplainerSheet: View {
    let ingredientName: String
    let productCategory: String
    let priorities: [String]
    let authToken: String
    let isPro: Bool

    @State private var loadState: LoadState = .idle
    @Environment(\.dismiss) private var dismiss

    enum LoadState {
        case idle, loading, success(String), rateLimited, failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("🤖")
                            .font(.system(size: 48))
                        Text("Ask Revelio")
                            .font(.title2.bold())
                            .foregroundColor(Theme.textPrimary)
                        Text("AI analysis of \(ingredientName.capitalized)")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Content
                    switch loadState {
                    case .idle:
                        EmptyView()

                    case .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.4)
                                .tint(Theme.accent)
                            Text("Analyzing ingredient...")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)

                    case .success(let explanation):
                        VStack(alignment: .leading, spacing: 16) {
                            Text(explanation)
                                .font(.body)
                                .foregroundColor(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(4)

                            // AI Disclosure
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(Theme.textDim)
                                Text("AI generated · Not medical advice")
                                    .font(.caption2)
                                    .foregroundColor(Theme.textDim)
                            }
                            .padding(.top, 4)
                        }
                        .padding(20)
                        .background(Theme.surface)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
                        )

                    case .rateLimited:
                        VStack(spacing: 16) {
                            Image(systemName: "lock.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.accent)
                            Text("Daily Limit Reached")
                                .font(.title3.bold())
                                .foregroundColor(Theme.textPrimary)
                            Text("Free users get 3 AI explanations per day. Upgrade to Pro for unlimited access.")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Button {
                                // Dismiss to let parent show paywall
                                dismiss()
                            } label: {
                                Label("Upgrade to Pro", systemImage: "star.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                        .padding(20)
                        .background(Theme.surface)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)

                    case .failed(let msg):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.danger)
                            Text("Couldn't load explanation")
                                .font(.headline)
                                .foregroundColor(Theme.textPrimary)
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task { await loadExplanation() }
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }
                        .padding(20)
                        .background(Theme.surface)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .task {
                await loadExplanation()
            }
        }
    }

    private func loadExplanation() async {
        loadState = .loading
        let result = await fetchIngredientExplanation(
            ingredientName: ingredientName,
            category: productCategory,
            priorities: priorities,
            authToken: authToken
        )
        switch result {
        case .explanation(let text, _):
            loadState = .success(text)
        case .rateLimitHit:
            loadState = .rateLimited
        case .failed(let msg):
            loadState = .failed(msg)
        }
    }
}
