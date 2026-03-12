import SwiftUI

// MARK: - Filter

enum PantryGradeFilter: String, CaseIterable {
    case all     = "All"
    case good    = "A–B"
    case bad     = "C–F"
    case flagged = "Flagged"

    var label: String { rawValue }

    func matches(_ item: PantryItem) -> Bool {
        switch self {
        case .all:     return true
        case .good:    return item.grade == "A" || item.grade == "B"
        case .bad:     return ["C", "D", "F"].contains(item.grade)
        case .flagged: return !item.flaggedIngredients.isEmpty
        }
    }
}

// MARK: - Main View

struct PantryView: View {
    @ObservedObject private var pantryManager = PantryManager.shared
    @State private var activeFilter: PantryGradeFilter = .all
    @State private var showScanner = false

    // MARK: Computed

    private var filteredItems: [PantryItem] {
        pantryManager.items.filter { activeFilter.matches($0) }
    }

    private var householdScore: Int {
        let all = pantryManager.items
        guard !all.isEmpty else { return 0 }
        var totalWeight = 0.0
        var weightedSum = 0.0
        for item in all {
            let w: Double = item.grade == "F" ? 3 : item.grade == "D" ? 2 : 1
            weightedSum += Double(item.score) * w
            totalWeight += w
        }
        return Int(weightedSum / totalWeight)
    }

    private var householdGrade: String {
        switch householdScore {
        case 85...: return "A"
        case 70..<85: return "B"
        case 55..<70: return "C"
        case 40..<55: return "D"
        default: return "F"
        }
    }

    private var cleanPercent: Double {
        let all = pantryManager.items
        guard !all.isEmpty else { return 0 }
        return Double(all.filter { $0.grade == "A" || $0.grade == "B" }.count) / Double(all.count)
    }

    private var badPercent: Double {
        let all = pantryManager.items
        guard !all.isEmpty else { return 0 }
        return Double(all.filter { ["C", "D", "F"].contains($0.grade) }.count) / Double(all.count)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Compact score bar (only when items exist)
                    if !pantryManager.items.isEmpty {
                        PantryScoreBar(
                            score: householdScore,
                            grade: householdGrade,
                            cleanPercent: cleanPercent,
                            badPercent: badPercent,
                            itemCount: pantryManager.items.count
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }

                    // Filter bar
                    PantryFilterBar(active: $activeFilter)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    Divider()
                        .background(Color.gray.opacity(0.15))

                    // Content
                    if pantryManager.items.isEmpty {
                        PantryEmptyState(showScanner: $showScanner)
                    } else if filteredItems.isEmpty {
                        PantryFilterEmptyState(filter: activeFilter)
                    } else {
                        pantryList
                    }
                }
            }
            .navigationTitle("Pantry")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Theme.accent)
                            .font(.system(size: 22))
                    }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            PantryManualScanSheet()
        }
    }

    // MARK: - List

    private var pantryList: some View {
        List {
            ForEach(filteredItems) { item in
                PantryRow(item: item)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Color.gray.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                pantryManager.removeItems(at: offsets, from: filteredItems)
            }
        }
        .listStyle(.plain)
        .background(Theme.background)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Filter Bar

struct PantryFilterBar: View {
    @Binding var active: PantryGradeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PantryGradeFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { active = filter }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(active == filter ? .white : Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                active == filter
                                    ? filterActiveColor(filter)
                                    : Theme.surfaceElevated
                            )
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterActiveColor(_ filter: PantryGradeFilter) -> Color {
        switch filter {
        case .all:     return Theme.accent
        case .good:    return Theme.success
        case .bad:     return Theme.danger
        case .flagged: return Theme.warning
        }
    }
}

// MARK: - Score Bar

struct PantryScoreBar: View {
    let score: Int
    let grade: String
    let cleanPercent: Double
    let badPercent: Double
    let itemCount: Int

    var body: some View {
        HStack(spacing: 16) {
            // Circular grade badge
            ZStack {
                Circle()
                    .stroke(Theme.surfaceElevated, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        Theme.gradeColor(grade),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(Theme.textPrimary)
                    Text(grade)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.gradeColor(grade))
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pantry Score")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                HStack(spacing: 12) {
                    scoreStatLabel(color: Theme.success, label: "Clean", pct: cleanPercent)
                    scoreStatLabel(color: Theme.danger, label: "Avoid", pct: badPercent)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(itemCount)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Theme.textPrimary)
                Text("items")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func scoreStatLabel(color: Color, label: String, pct: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(Int(pct * 100))% \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

// MARK: - Pantry Row

struct PantryRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            // Product image
            AsyncImage(url: URL(string: item.imageUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surfaceElevated)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(Theme.textDim)
                            .font(.caption)
                    )
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info column
            VStack(alignment: .leading, spacing: 4) {
                Text(item.productName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                if !item.brand.isEmpty {
                    Text(item.brand)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if !item.flaggedIngredients.isEmpty {
                        Label("\(item.flaggedIngredients.count) flagged", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.warning)
                    }
                    (Text(item.addedAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textDim)
                    + Text(" ago")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textDim))
                }
            }

            Spacer()

            // Animated grade badge
            GradeBadge(grade: item.grade, score: item.score, size: .small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty States

struct PantryEmptyState: View {
    @Binding var showScanner: Bool

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "refrigerator")
                    .font(.system(size: 64, weight: .ultraLight))
                    .foregroundColor(Theme.textDim)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Your pantry is empty")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Scan products to track what's in your kitchen and see how healthy your pantry really is.")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    showScanner = true
                } label: {
                    Label("Scan your first product", systemImage: "barcode.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(14)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8, x: 0, y: 4)
                }
            }
            Spacer()
        }
    }
}

struct PantryFilterEmptyState: View {
    let filter: PantryGradeFilter

    var body: some View {
        VStack {
            VStack(spacing: 16) {
                Image(systemName: filterIcon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Theme.textDim)
                    .padding(.top, 60)
                Text(filterMessage)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    private var filterIcon: String {
        switch filter {
        case .all:     return "tray"
        case .good:    return "checkmark.seal"
        case .bad:     return "xmark.seal"
        case .flagged: return "exclamationmark.triangle"
        }
    }

    private var filterMessage: String {
        switch filter {
        case .all:     return "No items in your pantry yet."
        case .good:    return "No A or B grade products yet. Scan some healthier picks!"
        case .bad:     return "Great — no C, D, or F products. Your pantry is clean."
        case .flagged: return "No products with flagged ingredients. Nice work."
        }
    }
}

// MARK: - Scan Sheet (redirect to Scan tab info)

struct PantryManualScanSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundColor(Theme.accent)

                    VStack(spacing: 8) {
                        Text("Scan to Add")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Use the Scan tab to scan a product — it will automatically appear in your Pantry.")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Add to Pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}

#Preview {
    PantryView()
}
