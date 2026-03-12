import SwiftUI
import StoreKit
import UserNotifications

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

    // RevenueCat / subscription
    @State private var showManageSubsError: String?

    // Restore Purchases
    @State private var isRestoring = false
    @State private var restoreSuccess = false
    @State private var restoreError: String?

    @Environment(\.requestReview) private var requestReview

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
                preferencesSection
                dataSection
                subscriptionSection
                appSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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
                        Text(authViewModel.currentUser?.phone.isEmpty == false
                            ? authViewModel.currentUser!.phone
                            : "Guest")
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

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
}
