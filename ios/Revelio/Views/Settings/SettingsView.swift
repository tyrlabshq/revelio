import SwiftUI
import StoreKit
import UserNotifications
import UIKit

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    // Preferences
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("weeklyReportEnabled") private var weeklyReportEnabled: Bool = false
    @AppStorage("defaultCategory") private var defaultCategoryRaw: String = ProductCategory.food.rawValue

    // Data section alerts
    @State private var showClearHistoryAlert = false
    @State private var showExportConfirmation = false
    @State private var exportError: String?
    @State private var isClearingHistory = false

    // Export my data (GDPR)
    @State private var isExportingAccount = false
    @State private var accountExportURL: IdentifiableURL?
    @State private var accountExportError: String?

    // Delete account (GDPR, triple-confirmation)
    @State private var showDeleteConfirm1 = false
    @State private var showDeleteConfirm2 = false
    @State private var showDeleteTypePrompt = false
    @State private var deleteTypedConfirmation = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    // Recalls badge — fetched once on load, refreshed on appear.
    @State private var recallUnreadCount: Int = 0

    // RevenueCat / subscription
    @State private var showManageSubsError: String?

    // Restore Purchases
    @State private var isRestoring = false
    @State private var restoreSuccess = false
    @State private var restoreError: String?

    @Environment(\.requestReview) private var requestReview

    private let authAPI = AuthAPI()

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    private var defaultCategory: Binding<ProductCategory> {
        Binding(
            get: { ProductCategory(rawValue: defaultCategoryRaw) ?? .food },
            set: { defaultCategoryRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                safetySection
                preferencesSection
                dataSection
                privacySection
                subscriptionSection
                appSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .task { await refreshRecallBadge() }
        }
        .alert("Clear Scan History?", isPresented: $showClearHistoryAlert) {
            Button("Clear", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your local scan history. This can't be undone.")
        }
        .alert("Export Ready", isPresented: $showExportConfirmation) {
            Button("OK") {}
        } message: {
            Text("Your scan history has been exported. Check the Files app.")
        }
        .alert("Purchases Restored 🎉", isPresented: $restoreSuccess) {
            Button("OK") {}
        } message: {
            Text("Your Pro subscription has been restored.")
        }
        // ─── Delete account: alert 1 ──────────────────────────────────────
        .alert("Delete account?", isPresented: $showDeleteConfirm1) {
            Button("Continue", role: .destructive) { showDeleteConfirm2 = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases your scans, pantry, goals, and family profiles forever.")
        }
        // ─── Delete account: alert 2 ──────────────────────────────────────
        .alert("Are you sure?", isPresented: $showDeleteConfirm2) {
            Button("Yes, continue", role: .destructive) {
                deleteTypedConfirmation = ""
                showDeleteTypePrompt = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        // ─── Delete account: alert 3 (type-to-confirm) ────────────────────
        .alert("Type DELETE to confirm", isPresented: $showDeleteTypePrompt) {
            TextField("DELETE", text: $deleteTypedConfirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
            Button("Delete my account", role: .destructive) {
                if deleteTypedConfirmation == "DELETE" {
                    Task { await performDeleteAccount() }
                }
            }
            .disabled(deleteTypedConfirmation != "DELETE")
            Button("Cancel", role: .cancel) { deleteTypedConfirmation = "" }
        } message: {
            Text("Type DELETE in all caps to permanently remove your account.")
        }
        // ─── Share sheet for /auth/export payload ─────────────────────────
        .sheet(item: $accountExportURL) { wrapped in
            ShareSheet(activityItems: [wrapped.url])
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "person.fill")
                        .foregroundColor(Theme.accent)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(authViewModel.currentUser?.name ?? authViewModel.currentUser?.email ?? authViewModel.currentUser?.phone ?? "Guest")
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)

                        if authViewModel.currentUser?.isPro == true {
                            ProBadge()
                        }
                    }
                    Text(authViewModel.currentUser?.tier == "pro" ? "Pro Member" : "Free Plan")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)

            Button(role: .destructive) {
                authViewModel.signOut()
            } label: {
                HStack {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Safety Section

    private var safetySection: some View {
        Section("Safety") {
            NavigationLink {
                RecallsView()
                    .environmentObject(authViewModel)
            } label: {
                HStack {
                    Label("Recall Alerts", systemImage: "exclamationmark.triangle")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if recallUnreadCount > 0 {
                        Text("\(recallUnreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.danger)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    @MainActor
    private func refreshRecallBadge() async {
        guard let token = authViewModel.loadToken() else { return }
        let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
        guard let url = URL(string: "\(apiBase)/recalls/mine") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoded = try JSONDecoder.revelio.decode(RecallsResponse.self, from: data)
            recallUnreadCount = decoded.unreadCount
        } catch { /* non-fatal */ }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        Section("Preferences") {
            // Scan notifications
            Toggle(isOn: $notificationsEnabled) {
                Label("Scan Alerts", systemImage: "bell")
                    .foregroundColor(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .onChange(of: notificationsEnabled) { _, enabled in
                if enabled { requestNotificationPermission() }
            }

            // Weekly report notification
            Toggle(isOn: $weeklyReportEnabled) {
                Label("Weekly Report", systemImage: "chart.bar")
                    .foregroundColor(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .onChange(of: weeklyReportEnabled) { _, enabled in
                if enabled { scheduleWeeklyReport() } else { cancelWeeklyReport() }
            }

            // Default scan category
            Picker(selection: defaultCategory) {
                ForEach(ProductCategory.allCases, id: \.self) { cat in
                    Label(cat.displayName, systemImage: categorySystemImage(cat))
                        .tag(cat)
                }
            } label: {
                Label("Default Category", systemImage: "square.grid.2x2")
                    .foregroundColor(Theme.textPrimary)
            }
            .tint(Theme.accent)
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section("Data") {
            // Export CSV
            Button {
                exportHistory()
            } label: {
                HStack {
                    Label("Export Scan History", systemImage: "square.and.arrow.up")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            // Clear History
            Button(role: .destructive) {
                showClearHistoryAlert = true
            } label: {
                HStack {
                    if isClearingHistory {
                        ProgressView()
                            .tint(Theme.danger)
                        Text("Clearing...")
                            .foregroundColor(Theme.danger)
                    } else {
                        Label("Clear Scan History", systemImage: "trash")
                    }
                    Spacer()
                }
            }
            .disabled(isClearingHistory)

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        }
    }

    // MARK: - Privacy Section (GDPR)

    private var privacySection: some View {
        Section {
            // Export my data — GET /auth/export → share sheet
            Button {
                Task { await performExportMyData() }
            } label: {
                HStack {
                    if isExportingAccount {
                        ProgressView()
                            .tint(Theme.accent)
                        Text("Preparing export...")
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        Label("Export my data", systemImage: "square.and.arrow.down.on.square")
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    if !isExportingAccount {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Theme.textDim)
                    }
                }
            }
            .disabled(isExportingAccount || isDeletingAccount)

            if let err = accountExportError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }

            // Delete account — triple-confirm → DELETE /auth/account → nuke local state
            Button(role: .destructive) {
                showDeleteConfirm1 = true
            } label: {
                HStack {
                    if isDeletingAccount {
                        ProgressView()
                            .tint(Theme.danger)
                        Text("Deleting...")
                            .foregroundColor(Theme.danger)
                    } else {
                        Label("Delete account", systemImage: "trash.slash")
                    }
                    Spacer()
                }
            }
            .disabled(isExportingAccount || isDeletingAccount)

            if let err = deleteAccountError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("You can download a copy of your data or permanently delete your account at any time. Account deletion is immediate and irreversible.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Section("Subscription") {
            Button {
                manageSubscription()
            } label: {
                HStack {
                    Label("Manage Subscription", systemImage: "creditcard")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            if let subError = showManageSubsError {
                Text(subError)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    if isRestoring {
                        ProgressView()
                            .tint(Theme.accent)
                        Text("Restoring...")
                            .foregroundColor(Theme.textSecondary)
                    } else {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                            .foregroundColor(Theme.textPrimary)
                    }
                    Spacer()
                    if !isRestoring {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Theme.textDim)
                    }
                }
            }
            .disabled(isRestoring)

            if let err = restoreError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Theme.danger)
            }
        }
    }

    // MARK: - App Section

    private var appSection: some View {
        Section("App") {
            // Rate App
            Button {
                requestReview()
            } label: {
                HStack {
                    Label("Rate Revelio", systemImage: "star")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            // Privacy Policy
            Link(destination: URL(string: "https://revelio.app/privacy")!) {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            // Terms of Service
            Link(destination: URL(string: "https://revelio.app/terms")!) {
                HStack {
                    Label("Terms of Service", systemImage: "doc.text")
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            // Version
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text(appVersion)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted { notificationsEnabled = false }
            }
        }
    }

    private func scheduleWeeklyReport() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { weeklyReportEnabled = false }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Your Weekly Food Report 🥗"
            content.body  = "See how your choices stacked up this week — tap to view your score card."
            content.sound = .default
            content.userInfo = ["deeplink": "revelio://history/weekly"]

            var dateComponents = DateComponents()
            dateComponents.weekday = 1 // Sunday
            dateComponents.hour    = 10
            dateComponents.minute  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "revelio.weekly.report", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    private func cancelWeeklyReport() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["revelio.weekly.report"])
    }

    private func exportHistory() {
        exportError = nil
        let history = HistoryManager.shared.history

        var csv = "Product,Brand,Category,Grade,Score,Barcode,Scanned At\n"
        let formatter = ISO8601DateFormatter()
        for scan in history {
            let line = "\"\(scan.productName)\",\"\(scan.brand)\",\"\(scan.category.displayName)\",\(scan.grade),\(scan.displayScore),\(scan.barcode),\(formatter.string(from: scan.scannedAt))\n"
            csv.append(line)
        }

        let fileName = "revelio-export-\(Int(Date().timeIntervalSince1970)).csv"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: tmpURL, atomically: true, encoding: .utf8)
            // Present share sheet
            DispatchQueue.main.async {
                let av = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    av.popoverPresentationController?.sourceView = root.view
                    root.present(av, animated: true)
                }
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        isClearingHistory = true
        HistoryManager.shared.clearHistory()
        isClearingHistory = false
    }

    // MARK: - GDPR: Export my data

    private func performExportMyData() async {
        accountExportError = nil
        isExportingAccount = true
        defer { isExportingAccount = false }

        do {
            let data = try await authAPI.exportData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("revelio-export.json")
            try data.write(to: url, options: .atomic)
            accountExportURL = IdentifiableURL(url: url)
        } catch {
            accountExportError = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - GDPR: Delete account

    private func performDeleteAccount() async {
        deleteAccountError = nil
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await authAPI.deleteAccount()
        } catch {
            deleteAccountError = "Could not delete account: \(error.localizedDescription)"
            return
        }

        // Server accepted (204). Scrub everything on-device.
        clearAllLocalState()

        // Drop the session — ContentView will switch back to OnboardingView /
        // PhoneEntryView because isAuthenticated flips to false.
        authViewModel.signOut()
    }

    /// Wipes every local cache touched by the GDPR delete flow.
    private func clearAllLocalState() {
        let defaults = UserDefaults.standard
        for key in [
            "scan_history_v1",
            "favorites_barcodes_v1",
            "pantry_items_v1",
            "revelio_personalization_v1"
        ] {
            defaults.removeObject(forKey: key)
        }

        // In-memory caches too, so the UI doesn't flash stale data on the
        // way out.
        HistoryManager.shared.clearHistory()
    }

    private func restorePurchases() async {
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await authViewModel.refreshUser()
            if authViewModel.currentUser?.isPro == true {
                restoreSuccess = true
            } else {
                restoreError = "No active subscription found."
            }
        } catch {
            restoreError = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func manageSubscription() {
        showManageSubsError = nil
        Task {
            do {
                // StoreKit 2 — opens Apple subscription management sheet
                try await AppStore.showManageSubscriptions(in: UIApplication.shared.connectedScenes.first as! UIWindowScene)
            } catch {
                showManageSubsError = "Could not open subscription management. Please go to Settings > Apple ID > Subscriptions."
            }
        }
    }

    // MARK: - Helpers

    private func categorySystemImage(_ cat: ProductCategory) -> String {
        switch cat {
        case .food:        return "fork.knife"
        case .cosmetics:   return "sparkles"
        case .cleaning:    return "bubbles.and.sparkles"
        case .supplements: return "pills"
        }
    }
}

// MARK: - Share sheet bridge
//
// UIActivityViewController wrapped for SwiftUI so we can present the export
// JSON file for AirDrop / Mail / Save to Files / etc.

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Box so we can drive a `.sheet(item:)` from a URL value.
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
