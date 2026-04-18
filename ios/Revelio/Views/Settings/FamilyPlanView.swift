import SwiftUI

// ─── Models ───────────────────────────────────────────────────────────────────

struct FamilyPlanResponse: Codable {
    let plan: FamilyPlan?
    let members: [FamilyMember]
    let tier: String?
}

struct FamilyPlan: Codable, Identifiable {
    let id: String
    let ownerId: String
    let maxMembers: Int
    let createdAt: String
    let role: String   // "owner" | "member"
}

struct FamilyMember: Codable, Identifiable {
    let userId: String
    let role: String
    let joinedAt: String
    let phone: String?

    var id: String { userId }
}

struct FamilyInviteResponse: Codable {
    let code: String
    let expiresAt: String
}

// ─── ViewModel ────────────────────────────────────────────────────────────────

@MainActor
final class FamilyPlanViewModel: ObservableObject {
    @Published var plan: FamilyPlan?
    @Published var members: [FamilyMember] = []
    @Published var tier: String = "free"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var latestInviteCode: String?

    private let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"

    private func authHeader() -> String? {
        guard let token = UserDefaults.standard.string(forKey: "auth_token") else { return nil }
        return "Bearer \(token)"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(apiBase)/family-plan") else { return }
        var req = URLRequest(url: url)
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Failed to load plan"
                return
            }
            let decoded = try JSONDecoder().decode(FamilyPlanResponse.self, from: data)
            self.plan = decoded.plan
            self.members = decoded.members
            self.tier = decoded.tier ?? "free"
        } catch {
            errorMessage = "Could not load family plan"
        }
    }

    func createPlan() async {
        guard let url = URL(string: "\(apiBase)/family-plan") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Could not create family plan (Pro required)"
                return
            }
            await load()
        } catch {
            errorMessage = "Network error creating plan"
        }
    }

    func generateInvite() async {
        guard let url = URL(string: "\(apiBase)/family-plan/invite") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Could not generate invite"
                return
            }
            let decoded = try JSONDecoder().decode(FamilyInviteResponse.self, from: data)
            self.latestInviteCode = decoded.code
        } catch {
            errorMessage = "Network error generating invite"
        }
    }

    func joinWithCode(_ code: String) async {
        guard let url = URL(string: "\(apiBase)/family-plan/join") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code])

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Invite invalid or expired"
                return
            }
            await load()
        } catch {
            errorMessage = "Network error joining plan"
        }
    }

    func removeMember(_ userId: String) async {
        guard let url = URL(string: "\(apiBase)/family-plan/members/\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if let h = authHeader() { req.setValue(h, forHTTPHeaderField: "Authorization") }

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                errorMessage = "Could not remove member"
                return
            }
            await load()
        } catch {
            errorMessage = "Network error removing member"
        }
    }
}

// ─── View ─────────────────────────────────────────────────────────────────────

struct FamilyPlanView: View {
    @StateObject private var viewModel = FamilyPlanViewModel()
    @State private var joinCode: String = ""
    @State private var showingShareSheet: Bool = false
    @State private var shareText: String = ""

    var body: some View {
        List {
            if viewModel.isLoading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let plan = viewModel.plan {
                planHeaderSection(plan: plan)
                membersSection(plan: plan)
                if plan.role == "owner" {
                    inviteSection
                }
            } else {
                noPlanSection
                joinSection
            }

            if let err = viewModel.errorMessage {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Family Plan")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
        .sheet(isPresented: $showingShareSheet) {
            ActivityShareSheet(items: [shareText])
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func planHeaderSection(plan: FamilyPlan) -> some View {
        Section("Your Plan") {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.role == "owner" ? "You own this plan" : "You joined a family plan")
                        .font(.headline)
                    Text("Up to \(plan.maxMembers) members share Pro.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func membersSection(plan: FamilyPlan) -> some View {
        Section("Members (\(viewModel.members.count)/\(plan.maxMembers))") {
            ForEach(viewModel.members) { member in
                HStack {
                    Image(systemName: member.role == "owner" ? "crown.fill" : "person.fill")
                        .foregroundColor(member.role == "owner" ? .yellow : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.phone ?? member.userId.prefix(8).description)
                            .font(.subheadline)
                        Text(member.role.capitalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if plan.role == "owner" && member.role != "owner" {
                        Button(role: .destructive) {
                            Task { await viewModel.removeMember(member.userId) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        Section("Invite") {
            Button {
                Task { await viewModel.generateInvite() }
            } label: {
                Label("Generate Invite Code", systemImage: "plus.circle")
            }

            if let code = viewModel.latestInviteCode {
                HStack {
                    Text(code)
                        .font(.system(.title3, design: .monospaced))
                    Spacer()
                    Button {
                        shareText = "Join my Revelio family plan with code: \(code)"
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Text("Expires in 7 days. Share with a family member.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var noPlanSection: some View {
        Section("Start a Family Plan") {
            Text("Pro subscribers can share Pro access with up to 6 family members.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button {
                Task { await viewModel.createPlan() }
            } label: {
                Label("Create Family Plan", systemImage: "person.3")
            }
        }
    }

    @ViewBuilder
    private var joinSection: some View {
        Section("Join an Existing Plan") {
            TextField("Invite code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
            Button {
                let trimmed = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    await viewModel.joinWithCode(trimmed)
                    joinCode = ""
                }
            } label: {
                Label("Join Plan", systemImage: "arrow.right.circle")
            }
            .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// ─── Share Sheet Wrapper ──────────────────────────────────────────────────────

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        FamilyPlanView()
    }
}
