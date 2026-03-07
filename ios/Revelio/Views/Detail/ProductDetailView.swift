import SwiftUI

// ─── Product Detail View ──────────────────────────────────────────────────────

struct ProductDetailView: View {
    let scan: ScanResult
    @State private var showCitations = Set<String>()
    @State private var usePersonalized = true
    @State private var showCleanIngredients = false
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject private var historyManager = HistoryManager.shared
    @ObservedObject private var allergenManager = AllergenProfileManager.shared

    private var allergenMatches: [AllergenMatch] {
        allergenManager.matches(for: scan.ingredients)
    }

    /// Priorities pulled from the current user profile (empty until loaded)
    private var userPriorities: [String] {
        // AuthUser doesn't expose priorities yet — graceful fallback
        return []
    }

    private var displayScore: Int {
        usePersonalized ? scan.personalizedScore : scan.baseScore
    }

    private var hasPersonalization: Bool {
        scan.personalizedScore != scan.baseScore
    }

    private var shareText: String {
        let flagSummary = scan.flags.isEmpty
            ? "No major concerns found."
            : scan.flags.prefix(3).map { "⚠️ \($0.ingredient.capitalized): \($0.reason)" }.joined(separator: "\n")
        return """
        🔍 Revelio Report: \(scan.productName)
        Brand: \(scan.brand)
        Grade: \(scan.grade) (\(scan.displayScore)/100)
        Category: \(scan.category.displayName)

        \(flagSummary)

        Scanned with Revelio — know what's in your products.
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Allergen Warning (if any matches) ─────────────────────
                    if !allergenMatches.isEmpty {
                        AllergenWarningBanner(matches: allergenMatches)
                    }

                    // ── Header ────────────────────────────────────────────────
                    ProductHeader(
                        scan: scan,
                        displayScore: displayScore,
                        usePersonalized: $usePersonalized,
                        hasPersonalization: hasPersonalization
                    )

                    // ── Score Breakdown Bar ───────────────────────────────────
                    ScoreBar(scan: scan, usePersonalized: usePersonalized)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    // ── Flagged Ingredients ───────────────────────────────────
                    if !scan.flags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("FLAGGED INGREDIENTS")
                                .padding(.horizontal, 20)
                                .padding(.top, 24)

                            ForEach(scan.flags) { flag in
                                FlagCard(
                                    flag: flag,
                                    showCitation: showCitations.contains(flag.id),
                                    onToggle: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            if showCitations.contains(flag.id) {
                                                showCitations.remove(flag.id)
                                            } else {
                                                showCitations.insert(flag.id)
                                            }
                                        }
                                    },
                                    productCategory: scan.category.rawValue,
                                    authToken: authViewModel.loadToken(),
                                    isPro: authViewModel.currentUser?.isPro ?? false,
                                    userPriorities: userPriorities
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // ── Clean Ingredients ─────────────────────────────────────
                    CleanIngredientsSection(
                        scan: scan,
                        isExpanded: $showCleanIngredients
                    )
                    .padding(.top, 16)

                    // ── Alternatives (score < 65) ─────────────────────────────
                    if scan.baseScore < 65 {
                        AlternativesSection()
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 16) {
                        // Favorite toggle
                        Button {
                            historyManager.toggleFavorite(scan)
                        } label: {
                            Image(systemName: historyManager.isFavorite(scan.barcode) ? "heart.fill" : "heart")
                                .foregroundColor(historyManager.isFavorite(scan.barcode) ? .pink : Theme.accent)
                        }
                        // Share button
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(Theme.accent)
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [shareText])
            }
        }
    }
}

// ─── Section Label ─────────────────────────────────────────────────────────────

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .foregroundColor(Theme.textDim)
    }
}

// ─── Product Header ────────────────────────────────────────────────────────────

struct ProductHeader: View {
    let scan: ScanResult
    let displayScore: Int
    @Binding var usePersonalized: Bool
    let hasPersonalization: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: Product info
            VStack(alignment: .leading, spacing: 8) {
                // Category chip
                HStack(spacing: 4) {
                    Text(scan.category.icon)
                    Text(scan.category.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.12))
                .cornerRadius(6)
                
                // Product name
                Text(scan.productName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Brand
                Text(scan.brand)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                
                Spacer()
                
                // Personalized toggle if available
                if hasPersonalization {
                    PersonalizationToggle(usePersonalized: $usePersonalized)
                }
            }
            
            Spacer()
            
            // Right: Score badge
            GradeBadge(grade: scan.grade, score: displayScore, size: .large)
        }
        .padding(20)
        .background(Theme.surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// ─── Personalization Toggle ────────────────────────────────────────────────────

private struct PersonalizationToggle: View {
    @Binding var usePersonalized: Bool

    var body: some View {
        HStack(spacing: 0) {
            toggleButton("Base", selected: !usePersonalized) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    usePersonalized = false
                }
            }
            toggleButton("For You ✦", selected: usePersonalized) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    usePersonalized = true
                }
            }
        }
        .background(Theme.surfaceElevated)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private func toggleButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : Theme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Color.clear)
                .cornerRadius(7)
        }
    }
}

// ─── Score Breakdown Bar ───────────────────────────────────────────────────────

struct ScoreBar: View {
    let scan: ScanResult
    let usePersonalized: Bool

    private var score: Int { usePersonalized ? scan.personalizedScore : scan.baseScore }

    /// Unique flag categories with counts
    private var flagCategories: [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for flag in scan.flags { counts[flag.category, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private var flagCount: Int { scan.flags.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCORE BREAKDOWN")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textDim)

            GeometryReader { geo in
                HStack(spacing: 2) {
                    // Green (clean) portion
                    if score > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.success)
                            .frame(width: max(geo.size.width * CGFloat(score) / 100, 4))
                    }

                    // Red segments per flag category
                    if flagCount > 0 && score < 100 {
                        let flagWidth = geo.size.width * CGFloat(100 - score) / 100
                        HStack(spacing: 2) {
                            ForEach(flagCategories, id: \.category) { item in
                                let segWidth = flagWidth * CGFloat(item.count) / CGFloat(flagCount)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(segmentColor(for: item.category))
                                        .frame(width: max(segWidth - 2, 4))
                                }
                            }
                        }
                        .frame(width: flagWidth)
                    } else if score < 100 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.danger)
                            .frame(width: geo.size.width * CGFloat(100 - score) / 100)
                    }
                }
            }
            .frame(height: 12)
            .background(Theme.surfaceElevated)
            .cornerRadius(6)

            // Legend
            HStack(spacing: 0) {
                Label("\(score)% clean", systemImage: "checkmark.circle.fill")
                    .foregroundColor(Theme.success)
                    .font(.caption)
                Spacer()

                // Per-category flag labels
                if flagCategories.count <= 2 {
                    ForEach(flagCategories, id: \.category) { item in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(segmentColor(for: item.category))
                                .frame(width: 6, height: 6)
                            Text(item.category)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.leading, 8)
                    }
                } else {
                    Label("\(flagCount) flag\(flagCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.danger)
                        .font(.caption)
                }
            }
        }
    }

    private func segmentColor(for category: String) -> Color {
        // Vary the red shade by category for visual distinction
        let cat = category.uppercased()
        if cat.contains("DYE") || cat.contains("COLOUR") { return Color(hex: "fb7185") }
        if cat.contains("PRESERV") { return Color(hex: "f97316") }
        if cat.contains("SEED OIL") || cat.contains("OIL") { return Color(hex: "ef4444") }
        if cat.contains("SWEETENER") || cat.contains("SUGAR") { return Color(hex: "fb923c") }
        if cat.contains("PESTICIDE") || cat.contains("HERBICIDE") { return Color(hex: "dc2626") }
        return Theme.danger
    }
}

// ─── Flag Card ─────────────────────────────────────────────────────────────────

struct FlagCard: View {
    let flag: IngredientFlag
    let showCitation: Bool
    let onToggle: () -> Void
    var productCategory: String = "general"
    var authToken: String? = nil
    var isPro: Bool = false
    var userPriorities: [String] = []

    @State private var showExplainer = false

    private var affectsGoals: Bool {
        guard !userPriorities.isEmpty, !flag.priorities.isEmpty else { return false }
        let userSet = Set(userPriorities.map { $0.lowercased() })
        return flag.priorities.contains { userSet.contains($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Top row: severity dot + name + severity label
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: flag.severityColor))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(flag.ingredient.capitalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)

                        // "Affects your goals" badge
                        if affectsGoals {
                            Text("Affects your goals")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }

                    Text(flag.category)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: flag.severityColor))
                }

                Spacer()

                Text(flag.severityLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: flag.severityColor))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: flag.severityColor).opacity(0.15))
                    .cornerRadius(4)
            }

            // Reason
            Text(flag.reason)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // Science citation
            if let title = flag.citationTitle, let url = flag.citationUrl {
                Button(action: onToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: showCitation ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        Text("See the science")
                            .font(.caption.bold())
                    }
                    .foregroundColor(Theme.accent)
                }

                if showCitation {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.caption)
                            .italic()
                            .foregroundColor(Theme.textSecondary)
                        if let year = flag.citationYear {
                            Text("Published \(year)")
                                .font(.caption2)
                                .foregroundColor(Theme.textDim)
                        }
                        Link("Read study →", destination: URL(string: url)!)
                            .font(.caption.bold())
                            .foregroundColor(Theme.accent)
                    }
                    .padding(10)
                    .background(Theme.surfaceElevated)
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Ask Revelio AI button
            if authToken != nil {
                Button {
                    showExplainer = true
                } label: {
                    HStack(spacing: 6) {
                        Text("🤖").font(.caption)
                        Text("Ask Revelio").font(.caption.bold())
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.1))
                    .cornerRadius(8)
                }
                .sheet(isPresented: $showExplainer) {
                    IngredientExplainerSheet(
                        ingredientName: flag.ingredient,
                        productCategory: productCategory,
                        priorities: userPriorities,
                        authToken: authToken ?? "",
                        isPro: isPro
                    )
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: flag.severityColor).opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showCitation)
    }
}

// ─── Clean Ingredients Section ─────────────────────────────────────────────────

struct CleanIngredientsSection: View {
    let scan: ScanResult
    @Binding var isExpanded: Bool

    private var flaggedNames: Set<String> {
        Set(scan.flags.map { $0.ingredient.lowercased() })
    }

    private var cleanIngredients: [String] {
        scan.ingredients.filter { !flaggedNames.contains($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tappable toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("CLEAN INGREDIENTS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textDim)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("\(cleanIngredients.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.success)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textDim)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.surface)
            }
            .buttonStyle(.plain)

            // Expanded ingredient list
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if cleanIngredients.isEmpty {
                        Text("No additional clean ingredients.")
                            .font(.caption)
                            .foregroundColor(Theme.textDim)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    } else {
                        Text(cleanIngredients.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .lineSpacing(4)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 14)
                    }
                }
                .background(Theme.surface)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
    }
}

// ─── Alternatives Section ──────────────────────────────────────────────────────

struct AlternativesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLEANER OPTIONS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.textDim)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.textDim)
                Text("Better alternatives coming soon")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(Theme.surface)
            .cornerRadius(12)
            .padding(.horizontal, 16)
        }
    }
}

struct AlternativeCard: View {
    let product: AlternativeProduct

    var body: some View {
        HStack(spacing: 14) {
            // Product image placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.surfaceElevated)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(Theme.textDim)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(product.brand)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                if let price = product.priceDisplay {
                    Text(price)
                        .font(.caption)
                        .foregroundColor(Theme.textDim)
                }
            }

            Spacer()

            VStack(spacing: 6) {
                GradeBadge(grade: product.grade, score: product.score)
                Link("Buy", destination: URL(string: product.purchaseUrl)!)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.success)
                    .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.success.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

// ─── Share Sheet ───────────────────────────────────────────────────────────────

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// ─── Preview ───────────────────────────────────────────────────────────────────

#if DEBUG
private let previewScan = ScanResult(
    id: "preview-1",
    barcode: "0123456789",
    productName: "Classic Mayonnaise",
    brand: "Hellmann's",
    category: .food,
    imageUrl: nil,
    ingredients: [
        "soybean oil", "water", "whole eggs", "egg yolks",
        "vinegar", "salt", "sugar", "lemon juice",
        "calcium disodium edta", "natural flavors"
    ],
    flags: [
        IngredientFlag(
            id: "f1",
            ingredient: "soybean oil",
            severity: 3,
            category: "SEED OIL",
            reason: "High in omega-6 linoleic acid, linked to systemic inflammation at modern intake levels.",
            citationTitle: "Dietary linoleic acid elevates endogenous 2-AG and anandamide",
            citationUrl: "https://pubmed.ncbi.nlm.nih.gov/example",
            citationYear: 2020,
            priorities: ["anti-inflammatory", "heart health"]
        ),
        IngredientFlag(
            id: "f2",
            ingredient: "calcium disodium edta",
            severity: 1,
            category: "PRESERVATIVE",
            reason: "Synthetic chelating agent; generally regarded as safe at low levels but not a clean-label ingredient.",
            citationTitle: nil,
            citationUrl: nil,
            citationYear: nil,
            priorities: []
        )
    ],
    baseScore: 54,
    personalizedScore: 48,
    grade: "D",
    alternatives: nil,
    scannedAt: Date()
)

#Preview {
    ProductDetailView(scan: previewScan)
        .environmentObject(AuthViewModel())
}
#endif
