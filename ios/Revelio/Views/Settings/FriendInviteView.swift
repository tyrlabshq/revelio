import SwiftUI

// ─── Models ───────────────────────────────────────────────────────────────────

private struct FriendInviteResponse: Codable {
    let code: String
    let expiresAt: String
    let shareUrl: String
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

@MainActor
final class FriendInviteViewModel: ObservableObject {
    @Published var inviteCode: String?
    @Published var inviteURL: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"

    private func authHeader() -> String? {
        guard let token = UserDefaults.standard.string(forKey: "auth_token") else { return nil }
        return "Bearer \(token)"
    }

    func generateInvite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(apiBase)/friend-invites") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Could not generate invite"
                return
            }
            let decoded = try JSONDecoder().decode(FriendInviteResponse.self, from: data)
            self.inviteCode = decoded.code
            self.inviteURL = decoded.shareUrl
        } catch {
            errorMessage = "Network error — please try again"
        }
    }
}

// ─── View ─────────────────────────────────────────────────────────────────────

struct FriendInviteView: View {
    @StateObject private var viewModel = FriendInviteViewModel()
    @State private var showingShareSheet: Bool = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    Text("Invite a friend, both get a free week of Pro")
                        .font(.headline)
                    Text("Share your personal link. When they sign up, Revelio Pro unlocks for both of you for 7 days — no payment required.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section {
                if viewModel.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let code = viewModel.inviteCode, let url = viewModel.inviteURL {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your code")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(code)
                                .font(.system(.title3, design: .monospaced))
                        }
                        HStack {
                            Text("Link")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(url)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share with a friend", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button {
                        Task { await viewModel.generateInvite() }
                    } label: {
                        Label("Generate my invite link", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let err = viewModel.errorMessage {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Invite a Friend")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingShareSheet) {
            if let url = viewModel.inviteURL {
                ActivityShareSheetForInvite(items: [
                    "Try Revelio with me — we both get a free week of Pro: \(url)"
                ])
            }
        }
    }
}

// ─── Share Sheet Wrapper ──────────────────────────────────────────────────────

private struct ActivityShareSheetForInvite: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        FriendInviteView()
    }
}
