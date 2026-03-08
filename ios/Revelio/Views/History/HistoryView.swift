import SwiftUI
import UserNotifications

// MARK: - Insights Model

struct ScanInsights: Codable {
    let weekAvgScore: Int
    let weekAvgGrade: String
    let lastWeekAvgScore: Int
    let improvement: Int
    let scanCountThisWeek: Int
    let topCategory: TopCategory?
    let mostAvoidedIngredient: String?
    let topCleanProduct: TopCleanProduct?

    struct TopCategory: Codable {
        let name: String
        let pct: Int
    }
    struct TopCleanProduct: Codable {
        let name: String
        let grade: String
        let score: Int
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @EnvironmentObject private var authViewModel: AuthViewModel

    // Pagination
    @State private var page = 1
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var remoteScans: [ScanResult] = []
    @State private var isRefreshing = false

    // Filters
    @State private var searchText = ""
    @State private var selectedCategory: ProductCategory? = nil
    @State private var selectedGrade: String? = nil
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var showFilters = false

    // Insights
    @State private var insights: ScanInsights? = nil
    @State private var insightsLoading = false

    // Navigation
    @State private var selectedScan: ScanResult? = nil

    // Weekly report
    @State private var weeklyReportEnabled: Bool = UserDefaults.standard.bool(forKey: "weeklyReportEnabled")

    private var displayedScans: [ScanResult] {
        if remoteScans.isEmpty {
            return filteredLocal
        }
        return remoteScans
    }

    private var filteredLocal: [ScanResult] {
        historyManager.history.filter { scan in
            let matchesSearch = searchText.isEmpty ||
                scan.productName.localizedCaseInsensitiveContains(searchText) ||
                scan.brand.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || scan.category == selectedCategory
            let matchesGrade = selectedGrade == nil || scan.grade == selectedGrade
            return matchesSearch && matchesCategory && matchesGrade
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // Insights card
                        if let ins = insights {
                            InsightsCard(insights: ins)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        } else if insightsLoading {
                            InsightsCardSkeleton()
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }

                        // Filter chips
                        if showFilters {
                            FilterPanel(
                                selectedCategory: $selectedCategory,
                                selectedGrade: $selectedGrade,
                                dateFrom: $dateFrom,
                                dateTo: $dateTo
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }

                        if displayedScans.isEmpty && !isRefreshing {
                            emptyState
                                .padding(.top, 60)
                        } else {
                            ForEach(displayedScans) { scan in
                                Button { selectedScan = scan } label: {
                                    HistoryRow(scan: scan, isFavorite: historyManager.isFavorite(scan.barcode))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteScan(scan)
                                    } label: {
                                        Label("Delete from History", systemImage: "trash")
                                    }
                                }

                                Divider()
                                    .padding(.horizontal, 16)
                            }

                            // Load more trigger
                            if hasMore {
                                ProgressView()
                                    .padding()
                                    .onAppear { loadMore() }
                            }
                        }
                    }
                }
                .refreshable {
                    await refreshAll()
                }
            }
            .searchable(text: $searchText, prompt: "Search products or brands")
            .onChange(of: searchText) { _, _ in applyFilters() }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(hasActiveFilters ? Theme.accent : Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    weeklyReportToggle
                }
            }
            .sheet(item: $selectedScan) { scan in
                ProductDetailView(scan: scan)
                    .environmentObject(authViewModel)
            }
        }
        .task {
            await refreshAll()
        }
    }

    // MARK: - Subviews

    private var weeklyReportToggle: some View {
        Menu {
            Toggle(isOn: $weeklyReportEnabled) {
                Label("Weekly Report", systemImage: "bell")
            }
            .onChange(of: weeklyReportEnabled) { _, enabled in
                UserDefaults.standard.set(enabled, forKey: "weeklyReportEnabled")
                if enabled { requestWeeklyNotification() } else { cancelWeeklyNotification() }
            }
        } label: {
            Image(systemName: weeklyReportEnabled ? "bell.fill" : "bell")
                .foregroundColor(weeklyReportEnabled ? Theme.accent : Theme.textSecondary)
        }
    }

    private var hasActiveFilters: Bool {
        selectedCategory != nil || selectedGrade != nil || dateFrom != nil || dateTo != nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Theme.textDim)
            Text("No scans yet")
                .font(.headline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Start scanning products to build your history")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Data Loading

    @MainActor
    func refreshAll() async {
        isRefreshing = true
        page = 1
        remoteScans = []
        hasMore = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchHistory(reset: true) }
            group.addTask { await self.fetchInsights() }
        }
        isRefreshing = false
    }

    func loadMore() {
        guard !isLoadingMore && hasMore else { return }
        isLoadingMore = true
        page += 1
        Task { await fetchHistory(reset: false) }
    }

    func applyFilters() {
        page = 1
        remoteScans = []
        hasMore = true
        Task { await fetchHistory(reset: true) }
    }

    @MainActor
    func fetchHistory(reset: Bool) async {
        guard let userId = authViewModel.currentUser?.id else {
            isLoadingMore = false
            return
        }

        let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8430"
        var components = URLComponents(string: "\(apiBase)/scans")!
        var items: [URLQueryItem] = [
            .init(name: "userId", value: userId),
            .init(name: "page",   value: "\(reset ? 1 : page)"),
            .init(name: "limit",  value: "20"),
        ]
        if let cat = selectedCategory { items.append(.init(name: "category", value: cat.rawValue)) }
        if let g   = selectedGrade    { items.append(.init(name: "grade",    value: g)) }
        if let q   = searchText.nonEmpty { items.append(.init(name: "q", value: q)) }
        if let from = dateFrom {
            items.append(.init(name: "from", value: ISO8601DateFormatter().string(from: from)))
        }
        if let to = dateTo {
            items.append(.init(name: "to", value: ISO8601DateFormatter().string(from: to)))
        }
        components.queryItems = items

        guard let url = components.url else { isLoadingMore = false; return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct HistoryPage: Codable {
                let data: [RemoteScan]
                let hasMore: Bool
            }
            let page = try JSONDecoder.revelio.decode(HistoryPage.self, from: data)
            let mapped = page.data.map { $0.toScanResult() }
            if reset { remoteScans = mapped } else { remoteScans.append(contentsOf: mapped) }
            hasMore = page.hasMore
        } catch {
            // Fall back to local if remote fails
            if reset { remoteScans = [] }
            hasMore = false
        }
        isLoadingMore = false
    }

    @MainActor
    func fetchInsights() async {
        guard let userId = authViewModel.currentUser?.id else { return }
        insightsLoading = true
        let apiBase2 = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8430"
        var components = URLComponents(string: "\(apiBase2)/scans/insights")!
        components.queryItems = [.init(name: "userId", value: userId)]
        guard let url = components.url else { insightsLoading = false; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            insights = try JSONDecoder.revelio.decode(ScanInsights.self, from: data)
        } catch { /* insights optional */ }
        insightsLoading = false
    }

    func deleteScan(_ scan: ScanResult) {
        // Local delete
        historyManager.removeScan(scan)
        remoteScans.removeAll { $0.id == scan.id }
        // Remote delete
        guard let userId = authViewModel.currentUser?.id else { return }
        let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8430"
        guard let url = URL(string: "\(apiBase)/scans/\(scan.id)?userId=\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - Notifications

    func requestWeeklyNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { scheduleWeeklySundayNotification() }
        }
    }

    func cancelWeeklyNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["revelio.weekly.report"])
    }
}

// MARK: - Schedule Weekly Notification

private func scheduleWeeklySundayNotification() {
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

// MARK: - Remote Scan DTO

struct RemoteScan: Codable {
    let id: String
    let barcode: String
    let productName: String
    let brand: String?
    let category: String?
    let imageUrl: String?
    let score: Int
    let grade: String
    let scannedAt: Date

    func toScanResult() -> ScanResult {
        ScanResult(
            id: id,
            barcode: barcode,
            productName: productName,
            brand: brand ?? "",
            category: ProductCategory(rawValue: category ?? "food") ?? .food,
            imageUrl: imageUrl,
            ingredients: [],
            flags: [],
            baseScore: score,
            personalizedScore: score,
            grade: grade,
            alternatives: nil,
            scannedAt: scannedAt
        )
    }
}

// MARK: - Insights Card

struct InsightsCard: View {
    let insights: ScanInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("This Week's Insights")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("7-day rolling")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textDim)
            }

            // Score row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Avg Score")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(insights.weekAvgScore)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Theme.gradeColor(insights.weekAvgGrade))
                        Text("(\(insights.weekAvgGrade))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.gradeColor(insights.weekAvgGrade))
                    }
                }

                Spacer()

                if insights.improvement != 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("vs last week")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textDim)
                        HStack(spacing: 2) {
                            Image(systemName: insights.improvement > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(insights.improvement > 0 ? Theme.success : Theme.danger)
                            Text("\(abs(insights.improvement)) pts")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(insights.improvement > 0 ? Theme.success : Theme.danger)
                        }
                    }
                }
            }

            Divider()

            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if let topCat = insights.topCategory {
                    insightTile(
                        icon: categoryIcon(topCat.name),
                        label: "Top Category",
                        value: "\(topCat.name.capitalized) (\(topCat.pct)%)"
                    )
                }
                if let avoided = insights.mostAvoidedIngredient {
                    insightTile(icon: "🚫", label: "Most Avoided", value: avoided)
                }
                if let top = insights.topCleanProduct {
                    insightTile(
                        icon: "🏆",
                        label: "Cleanest Pick",
                        value: "\(top.name) — \(top.grade)"
                    )
                }
                insightTile(
                    icon: "📦",
                    label: "Scans This Week",
                    value: "\(insights.scanCountThisWeek)"
                )
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func insightTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
        .cornerRadius(10)
    }

    private func categoryIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "food":        return "🍎"
        case "cosmetics":   return "💄"
        case "cleaning":    return "🧴"
        case "supplements": return "💊"
        default:            return "📦"
        }
    }
}

struct InsightsCardSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Theme.surface)
            .frame(height: 180)
            .overlay(
                ProgressView()
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Filter Panel

struct FilterPanel: View {
    @Binding var selectedCategory: ProductCategory?
    @Binding var selectedGrade: String?
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?

    private let grades = ["A", "B", "C", "D", "F"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category filters
            Text("Category")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(ProductCategory.allCases, id: \.self) { cat in
                        filterChip(
                            label: cat.icon + " " + cat.displayName,
                            isSelected: selectedCategory == cat
                        ) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
            }

            // Grade filters
            Text("Grade")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textDim)
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: selectedGrade == nil) {
                    selectedGrade = nil
                }
                ForEach(grades, id: \.self) { g in
                    filterChip(label: g, isSelected: selectedGrade == g, color: Theme.gradeColor(g)) {
                        selectedGrade = selectedGrade == g ? nil : g
                    }
                }
            }

            // Date range (compact)
            HStack(spacing: 12) {
                DatePicker("From", selection: Binding(
                    get: { dateFrom ?? Date() },
                    set: { dateFrom = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 12))

                Text("→").foregroundColor(Theme.textDim)

                DatePicker("To", selection: Binding(
                    get: { dateTo ?? Date() },
                    set: { dateTo = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .font(.system(size: 12))

                Spacer()

                if dateFrom != nil || dateTo != nil {
                    Button("Clear") {
                        dateFrom = nil
                        dateTo = nil
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.danger)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func filterChip(label: String, isSelected: Bool, color: Color = Theme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Theme.surfaceElevated)
                .cornerRadius(20)
        }
    }
}

// MARK: - HistoryRow

struct HistoryRow: View {
    let scan: ScanResult
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Product image
            AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated)
                    .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(scan.productName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                    }
                }
                Text(scan.brand)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Text(scan.category.icon + " " + scan.category.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.accent)
                (Text(scan.scannedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim)
                + Text(" ago")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textDim))
            }

            Spacer()

            GradeBadge(grade: scan.grade, score: scan.displayScore, size: .small)
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Helpers

extension JSONDecoder {
    static var revelio: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#Preview {
    HistoryView()
        .environmentObject(AuthViewModel())
}
