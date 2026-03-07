import SwiftUI

// MARK: - Models

struct CreatorStats: Codable {
    let code: String
    let shareUrl: String
    let status: String
    let referredCount: Int
    let activeSubscribers: Int
    let totalEarningsCents: Int
    let pendingPayoutCents: Int
    let monthEarningsCents: Int
}

struct CreatorApplicationResponse: Codable {
    let success: Bool
    let code: String?
    let status: String
    let shareUrl: String?
    let message: String
}

struct CreatorApplyRequest: Codable {
    let user_id: String
    let follower_count: Int
    let platform: String
    let social_handle: String
}

// MARK: - ViewModel

@MainActor
class CreatorViewModel: ObservableObject {
    @Published var stats: CreatorStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var applicationStatus: String? // nil = not applied yet
    @Published var appliedCode: String?

    private let baseURL = "https://api.revelio.app"

    func loadStats(userId: String) {
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/referrals/my-stats")!)
                request.addValue(userId, forHTTPHeaderField: "x-user-id")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }

                if http.statusCode == 404 {
                    applicationStatus = nil
                    return
                }

                let decoded = try JSONDecoder().decode(CreatorStats.self, from: data)
                self.stats = decoded
                self.applicationStatus = decoded.status
                self.appliedCode = decoded.code
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func applyForCreator(userId: String, followerCount: Int, platform: String, handle: String) {
        isLoading = true
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                var request = URLRequest(url: URL(string: "\(baseURL)/referrals/creator-apply")!)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = CreatorApplyRequest(
                    user_id: userId,
                    follower_count: followerCount,
                    platform: platform,
                    social_handle: handle
                )
                request.httpBody = try JSONEncoder().encode(body)

                let (data, _) = try await URLSession.shared.data(for: request)
                let decoded = try JSONDecoder().decode(CreatorApplicationResponse.self, from: data)

                self.applicationStatus = decoded.status
                self.appliedCode = decoded.code
                if decoded.status == "approved" {
                    await loadStats(userId: userId)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Creator Badge

struct CreatorBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "megaphone.fill")
                .font(.caption2)
            Text("Creator")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.15))
        .foregroundColor(.purple)
        .clipShape(Capsule())
    }
}

// MARK: - Application Form

struct CreatorApplicationForm: View {
    @ObservedObject var viewModel: CreatorViewModel
    let userId: String

    @State private var followerCountText = ""
    @State private var platform = "TikTok"
    @State private var socialHandle = ""

    let platforms = ["TikTok", "Instagram", "YouTube", "X (Twitter)", "Other"]

    var followerCount: Int { Int(followerCountText) ?? 0 }
    var autoApprove: Bool { followerCount >= 1000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                    Text("Become a Creator")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                }
                Text("Earn 20% recurring commission on every subscription you drive. Your audience trusts you. Get paid for it.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }

            Divider()

            // Perks
            VStack(alignment: .leading, spacing: 12) {
                Label("20% of every subscription, forever", systemImage: "dollarsign.circle.fill")
                    .foregroundColor(Theme.textPrimary)
                Label("Unique link: revelio.app/ref/YOURCODE", systemImage: "link")
                    .foregroundColor(Theme.textPrimary)
                Label("Real-time dashboard + payout history", systemImage: "chart.bar.fill")
                    .foregroundColor(Theme.textPrimary)
                Label("Pre-built TikTok captions + banner images", systemImage: "photo.fill")
                    .foregroundColor(Theme.textPrimary)
            }
            .font(.subheadline)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Details")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)

                Picker("Platform", selection: $platform) {
                    ForEach(platforms, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)

                TextField("@yourhandle", text: $socialHandle)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                TextField("Follower count", text: $followerCountText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)

                if followerCount > 0 {
                    HStack {
                        Image(systemName: autoApprove ? "checkmark.circle.fill" : "clock.fill")
                            .foregroundColor(autoApprove ? .green : .orange)
                        Text(autoApprove
                            ? "Instant approval — you're in!"
                            : "Manual review — we'll reach out within 48h")
                            .font(.caption)
                            .foregroundColor(autoApprove ? .green : .orange)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                viewModel.applyForCreator(
                    userId: userId,
                    followerCount: followerCount,
                    platform: platform,
                    handle: socialHandle
                )
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Apply Now — It's Free")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(socialHandle.isEmpty || followerCountText.isEmpty ? Color.gray : Color.purple)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(socialHandle.isEmpty || followerCountText.isEmpty || viewModel.isLoading)
        }
        .padding()
    }
}

// MARK: - Stats Dashboard

struct CreatorDashboard: View {
    let stats: CreatorStats
    @State private var showShareSheet = false
    @State private var shareText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with badge and code
                VStack(spacing: 8) {
                    CreatorBadge()
                    Text("revelio.app/ref/\(stats.code)")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                        .monospaced()

                    Button {
                        shareText = "🔬 I use Revelio to scan ingredients for hidden junk. Try it free: \(stats.shareUrl)"
                        showShareSheet = true
                    } label: {
                        Label("Share Your Link", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        UIPasteboard.general.string = stats.shareUrl
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                }
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    CreatorStatCard(
                        title: "Referred Users",
                        value: "\(stats.referredCount)",
                        icon: "person.2.fill",
                        color: .blue
                    )
                    CreatorStatCard(
                        title: "Active Subs",
                        value: "\(stats.activeSubscribers)",
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                    CreatorStatCard(
                        title: "This Month",
                        value: formatCents(stats.monthEarningsCents),
                        icon: "calendar",
                        color: .orange
                    )
                    CreatorStatCard(
                        title: "Pending Payout",
                        value: formatCents(stats.pendingPayoutCents),
                        icon: "dollarsign.circle.fill",
                        color: .purple
                    )
                }

                // Lifetime earnings
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Lifetime Earnings")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        Text(formatCents(stats.totalEarningsCents))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.title)
                        .foregroundColor(.yellow)
                }
                .padding()
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Share kit
                ShareKitSection(code: stats.code, shareUrl: stats.shareUrl)
            }
            .padding()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareText])
        }
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - Stat Card

struct CreatorStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Share Kit

struct ShareKitSection: View {
    let code: String
    let shareUrl: String
    @State private var showingTemplate = false
    @State private var selectedTemplate = 0

    let captions = [
        "🔬 Finally found an app that actually tells me what's IN my food. Scan any barcode and it flags every sketchy ingredient with real research behind it. No BS. Link in bio 👇 revelio.app/ref/CODE",
        "POV: you thought your \"healthy\" granola bar was fine 😬 Revelio just exposed 4 seed oils and a dye linked to hyperactivity. Get it free: revelio.app/ref/CODE",
        "I've been scanning everything at Whole Foods with this app and I'm horrified. It flags ingredients with actual peer-reviewed studies. Try it → revelio.app/ref/CODE"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share Kit")
                .font(.headline)
                .foregroundColor(Theme.textPrimary)

            Text("TikTok Caption Templates")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)

            TabView(selection: $selectedTemplate) {
                ForEach(Array(captions.enumerated()), id: \.offset) { index, caption in
                    let adjusted = caption.replacingOccurrences(of: "CODE", with: code)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(adjusted)
                            .font(.caption)
                            .foregroundColor(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            UIPasteboard.general.string = adjusted
                        } label: {
                            Label("Copy Caption", systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding()
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 180)
        }
        .padding()
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Pending Review View

struct CreatorPendingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Application Under Review")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Theme.textPrimary)

            Text("We'll review your application and reach out within 48 hours. Once approved, you'll get your unique link and start earning immediately.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Main CreatorView

struct CreatorView: View {
    @StateObject private var viewModel = CreatorViewModel()
    let userId: String

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.stats == nil {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let stats = viewModel.stats, stats.status == "approved" {
                    CreatorDashboard(stats: stats)
                } else if viewModel.applicationStatus == "pending" {
                    CreatorPendingView()
                } else {
                    ScrollView {
                        CreatorApplicationForm(viewModel: viewModel, userId: userId)
                    }
                }
            }
            .navigationTitle("Creator Program")
            .navigationBarTitleDisplayMode(.large)
            .background(Theme.background.ignoresSafeArea())
        }
        .task {
            viewModel.loadStats(userId: userId)
        }
    }
}
