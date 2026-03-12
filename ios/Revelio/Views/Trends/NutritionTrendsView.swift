import SwiftUI
import Charts

// MARK: - View Model

@MainActor
class NutritionTrendsViewModel: ObservableObject {
    @Published private(set) var weeklyScans: [ScanResult] = []

    private let historyManager = HistoryManager.shared

    // MARK: Computed: Summary

    var scanCount: Int { weeklyScans.count }

    var averageScore: Int {
        guard !weeklyScans.isEmpty else { return 0 }
        let total = weeklyScans.reduce(0) { $0 + $1.displayScore }
        return total / weeklyScans.count
    }

    var averageGrade: String {
        scoreToGrade(averageScore)
    }

    // MARK: Computed: Grade Distribution

    var gradeDistribution: [(grade: String, count: Int)] {
        let grades = ["A", "B", "C", "D", "F"]
        return grades.map { g in
            (grade: g, count: weeklyScans.filter { $0.grade == g }.count)
        }
    }

    // MARK: Computed: Category Breakdown

    var categoryBreakdown: [(category: ProductCategory, count: Int, avgGrade: String, avgScore: Int)] {
        ProductCategory.allCases.compactMap { cat in
            let items = weeklyScans.filter { $0.category == cat }
            guard !items.isEmpty else { return nil }
            let avg = items.reduce(0) { $0 + $1.displayScore } / items.count
            return (category: cat, count: items.count, avgGrade: scoreToGrade(avg), avgScore: avg)
        }
        .sorted { $0.count > $1.count }
    }

    // MARK: Computed: Top Ingredients

    var topIngredients: [(name: String, count: Int)] {
        var tally: [String: Int] = [:]
        for scan in weeklyScans {
            for ingredient in scan.ingredients {
                let key = ingredient.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                tally[key, default: 0] += 1
            }
        }
        return tally
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key.capitalized, count: $0.value) }
    }

    // MARK: Computed: Flagged Ingredients (severity >= 2)

    var flaggedThisWeek: [(name: String, count: Int, maxSeverity: Int, reason: String)] {
        var tally: [String: (count: Int, maxSeverity: Int, reason: String)] = [:]
        for scan in weeklyScans {
            for flag in scan.flags where flag.severity >= 2 {
                let key = flag.ingredient.lowercased()
                let existing = tally[key]
                let newSeverity = max(existing?.maxSeverity ?? 0, flag.severity)
                tally[key] = (
                    count: (existing?.count ?? 0) + 1,
                    maxSeverity: newSeverity,
                    reason: flag.reason
                )
            }
        }
        return tally
            .sorted { $0.value.maxSeverity > $1.value.maxSeverity || ($0.value.maxSeverity == $1.value.maxSeverity && $0.value.count > $1.value.count) }
            .prefix(5)
            .map { (name: $0.key.capitalized, count: $0.value.count, maxSeverity: $0.value.maxSeverity, reason: $0.value.reason) }
    }

    // MARK: Computed: Most Common Flagged (for summary card)

    var mostCommonFlagged: String? {
        flaggedThisWeek.first?.name
    }

    // MARK: - Refresh

    func refresh() {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        weeklyScans = historyManager.history.filter { $0.scannedAt >= weekAgo }
    }

    // MARK: - Helpers

    private func scoreToGrade(_ score: Int) -> String {
        switch score {
        case 85...: return "A"
        case 70..<85: return "B"
        case 55..<70: return "C"
        case 40..<55: return "D"
        default: return "F"
        }
    }
}

// MARK: - Main View

struct NutritionTrendsView: View {
    @StateObject private var vm = NutritionTrendsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if vm.scanCount == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Weekly summary
                            WeeklySummaryCard(vm: vm)
                                .padding(.horizontal, 16)

                            // Grade distribution chart
                            GradeDistributionCard(distribution: vm.gradeDistribution)
                                .padding(.horizontal, 16)

                            // Category breakdown
                            if !vm.categoryBreakdown.isEmpty {
                                CategoryBreakdownCard(breakdown: vm.categoryBreakdown)
                                    .padding(.horizontal, 16)
                            }

                            // Top ingredients
                            if !vm.topIngredients.isEmpty {
                                TopIngredientsCard(ingredients: vm.topIngredients)
                                    .padding(.horizontal, 16)
                            }

                            // Flagged callout
                            if !vm.flaggedThisWeek.isEmpty {
                                FlaggedCalloutCard(flagged: vm.flaggedThisWeek)
                                    .padding(.horizontal, 16)
                            }

                            Spacer().frame(height: 32)
                        }
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
            .task { vm.refresh() }
            .refreshable { vm.refresh() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(Theme.textDim)
            Text("No data yet this week")
                .font(.title3.weight(.bold))
                .foregroundColor(Theme.textPrimary)
            Text("Scan some products and your weekly nutrition trends will appear here.")
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    @ObservedObject var vm: NutritionTrendsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Week")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textDim)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text("Weekly Summary")
                        .font(.headline.weight(.bold))
                        .foregroundColor(Theme.textPrimary)
                }
                Spacer()
                Text("Last 7 days")
                    .font(.caption2)
                    .foregroundColor(Theme.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceElevated)
                    .cornerRadius(6)
            }

            Divider().background(Color.gray.opacity(0.12))

            // Stats row
            HStack(spacing: 0) {
                summaryStatColumn(
                    value: "\(vm.scanCount)",
                    label: "Scanned",
                    icon: "barcode.viewfinder",
                    color: Theme.accent
                )

                Divider().frame(height: 50).background(Color.gray.opacity(0.15))

                summaryStatColumn(
                    value: vm.averageGrade,
                    label: "Avg Grade",
                    icon: nil,
                    color: Theme.gradeColor(vm.averageGrade),
                    isGrade: true
                )

                Divider().frame(height: 50).background(Color.gray.opacity(0.15))

                summaryStatColumn(
                    value: vm.mostCommonFlagged ?? "None",
                    label: "Top Flag",
                    icon: "exclamationmark.triangle.fill",
                    color: Theme.danger,
                    isSmallText: true
                )
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    @ViewBuilder
    private func summaryStatColumn(
        value: String,
        label: String,
        icon: String?,
        color: Color,
        isGrade: Bool = false,
        isSmallText: Bool = false
    ) -> some View {
        VStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(value)
                .font(isGrade
                      ? .system(size: 28, weight: .black, design: .rounded)
                      : isSmallText
                        ? .system(size: 12, weight: .bold)
                        : .system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Grade Distribution Card (Swift Charts)

struct GradeDistributionCard: View {
    let distribution: [(grade: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Grade Distribution",
                icon: "chart.bar.fill",
                color: Theme.accent
            )

            Chart(distribution, id: \.grade) { item in
                BarMark(
                    x: .value("Grade", item.grade),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Theme.gradeColor(item.grade))
                .cornerRadius(6)
                .annotation(position: .top) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.gradeColor(item.grade))
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let grade = value.as(String.self) {
                            Text(grade)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.gradeColor(grade))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text("\(count)")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textDim)
                        }
                    }
                }
            }
            .frame(height: 180)
            .chartYScale(domain: 0...(maxCount + 2))
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var maxCount: Int {
        distribution.map(\.count).max() ?? 1
    }
}

// MARK: - Category Breakdown Card

struct CategoryBreakdownCard: View {
    let breakdown: [(category: ProductCategory, count: Int, avgGrade: String, avgScore: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "By Category",
                icon: "square.grid.2x2.fill",
                color: Theme.accent
            )

            VStack(spacing: 10) {
                ForEach(breakdown, id: \.category) { item in
                    CategoryRow(
                        category: item.category,
                        count: item.count,
                        avgGrade: item.avgGrade,
                        avgScore: item.avgScore
                    )
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

struct CategoryRow: View {
    let category: ProductCategory
    let count: Int
    let avgGrade: String
    let avgScore: Int

    var body: some View {
        HStack(spacing: 12) {
            // Icon bubble
            Text(category.icon)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Theme.surfaceElevated)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("\(count) product\(count == 1 ? "" : "s") scanned")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            // Score bar
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(avgScore)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.gradeColor(avgGrade))
                    Text(avgGrade)
                        .font(.system(size: 11, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.gradeColor(avgGrade))
                        .cornerRadius(4)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surfaceElevated)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.gradeColor(avgGrade))
                            .frame(width: geo.size.width * CGFloat(avgScore) / 100, height: 4)
                    }
                }
                .frame(width: 80, height: 4)
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Top Ingredients Card

struct TopIngredientsCard: View {
    let ingredients: [(name: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Most Scanned Ingredients",
                icon: "list.number",
                color: Theme.accent
            )

            let maxCount = ingredients.first?.count ?? 1

            VStack(spacing: 10) {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 12) {
                        // Rank
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(idx == 0 ? Theme.accent : Theme.textDim)
                            .frame(width: 20, alignment: .center)

                        // Bar + name
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.surfaceElevated)
                                        .frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(idx == 0 ? Theme.accent : Theme.accent.opacity(0.45))
                                        .frame(
                                            width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount),
                                            height: 5
                                        )
                                }
                            }
                            .frame(height: 5)
                        }

                        // Count pill
                        Text("\(item.count)×")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surfaceElevated)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Flagged This Week Callout

struct FlaggedCalloutCard: View {
    let flagged: [(name: String, count: Int, maxSeverity: Int, reason: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with warning tone
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.danger)
                Text("Flagged This Week")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Text("Ingredients to watch")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Theme.danger.opacity(0.7))
            }

            Text("These ingredients appeared in products you scanned and may warrant attention.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            Divider().background(Color.gray.opacity(0.1))

            VStack(spacing: 8) {
                ForEach(Array(flagged.enumerated()), id: \.offset) { _, item in
                    FlaggedIngredientRow(item: item)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.danger.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Theme.danger.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

struct FlaggedIngredientRow: View {
    let item: (name: String, count: Int, maxSeverity: Int, reason: String)

    private var severityLabel: String {
        switch item.maxSeverity {
        case 3: return "AVOID"
        case 2: return "CAUTION"
        default: return "WATCH"
        }
    }

    private var severityColor: Color {
        switch item.maxSeverity {
        case 3: return Theme.danger
        case 2: return Theme.warning
        default: return Color(hex: "f59e0b")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Severity dot
            Circle()
                .fill(severityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.reason)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(severityLabel)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(severityColor)
                    .cornerRadius(4)
                Text("\(item.count)× scanned")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textDim)
            }
        }
        .padding(10)
        .background(severityColor.opacity(0.06))
        .cornerRadius(8)
    }
}

// MARK: - Shared Section Header Helper

private func sectionHeader(title: String, icon: String, color: Color) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Theme.textPrimary)
        Spacer()
    }
}

// MARK: - Preview

#Preview {
    NutritionTrendsView()
}
