import SwiftUI
#if canImport(Charts)
import Charts
#endif

// MARK: - Wire models
//
// Mirror of the JSON shape returned by GET /brands/:slug/summary. We decode
// snake_case the same way the Explore feed does so that the backend
// BrandSummary type in backend/src/services/brandSummary.ts lines up 1:1.

struct BrandProductCard: Identifiable, Codable {
    let barcode: String
    let name: String
    let brand: String
    let imageUrl: String?
    let grade: String
    let score: Int

    var id: String { barcode }
}

struct BrandSummary: Codable {
    let slug: String
    let totalProducts: Int
    let distribution: GradeDistribution
    let cleanestPercent: Int
    let topCleanest: [BrandProductCard]
    let worstProducts: [BrandProductCard]
    let cachedAt: String

    struct GradeDistribution: Codable {
        let A: Int
        let B: Int
        let C: Int
        let D: Int
        let F: Int

        var counts: [(grade: String, count: Int)] {
            [("A", A), ("B", B), ("C", C), ("D", D), ("F", F)]
        }

        var total: Int { A + B + C + D + F }
    }
}

// MARK: - Header view

struct BrandSummaryHeader: View {
    let slug: String
    let summary: BrandSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Brand title — slug is the URL-safe token; we display the brand name
            // off the first product card so the header reads "HELLMANN'S" rather
            // than "hellmanns".
            VStack(alignment: .leading, spacing: 4) {
                Text(displayBrand)
                    .font(Theme.fontTitle)
                    .foregroundColor(Theme.textPrimary)
                Text("\(summary.totalProducts) products in our database")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }

            distributionSection
            cleanestPercentStat

            if !summary.topCleanest.isEmpty {
                horizontalRow(title: "Top 5 cleanest", products: summary.topCleanest)
            }
            if !summary.worstProducts.isEmpty {
                horizontalRow(title: "Worst 5 scored", products: summary.worstProducts)
            }
        }
        .padding(20)
        .background(Theme.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var displayBrand: String {
        summary.topCleanest.first?.brand
            ?? summary.worstProducts.first?.brand
            ?? slug.uppercased()
    }

    // MARK: - Distribution

    @ViewBuilder
    private var distributionSection: some View {
        if #available(iOS 16.0, *) {
            donutChart
        } else {
            stackedBarFallback
        }
    }

    @available(iOS 16.0, *)
    private var donutChart: some View {
        // Compile the chart closure under a #if so build targets that strip
        // the Charts module (e.g. minimum-deployment configs) still compile
        // via the stacked-bar fallback in `else` below.
        #if canImport(Charts)
        return Chart(summary.distribution.counts, id: \.grade) { item in
            SectorMark(
                angle: .value("Products", item.count),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(Theme.gradeColor(item.grade))
        }
        .frame(height: 180)
        .accessibilityLabel("Grade distribution")
        .accessibilityValue(distributionAccessibility)
        #else
        return stackedBarFallback
        #endif
    }

    private var stackedBarFallback: some View {
        let total = max(1, summary.distribution.total)
        return HStack(spacing: 0) {
            ForEach(summary.distribution.counts, id: \.grade) { item in
                if item.count > 0 {
                    Rectangle()
                        .fill(Theme.gradeColor(item.grade))
                        .frame(width: CGFloat(item.count) / CGFloat(total) * UIScreen.main.bounds.width * 0.8)
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityLabel("Grade distribution")
        .accessibilityValue(distributionAccessibility)
    }

    private var distributionAccessibility: String {
        summary.distribution.counts
            .filter { $0.count > 0 }
            .map { "\($0.count) grade \($0.grade)" }
            .joined(separator: ", ")
    }

    private var cleanestPercentStat: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(summary.cleanestPercent)%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(Theme.accent)
            Text("clean (A or B)")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.cleanestPercent) percent of products are grade A or B")
    }

    // MARK: - Horizontal rows

    private func horizontalRow(title: String, products: [BrandProductCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(products) { product in
                        BrandMiniCard(product: product)
                    }
                }
            }
        }
    }
}

// MARK: - Mini card

struct BrandMiniCard: View {
    let product: BrandProductCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: product.imageUrl ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            Theme.surfaceElevated
                            Image(systemName: "photo").foregroundColor(Theme.textDim)
                        }
                    }
                }
                .frame(width: 120, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                GradeBadge(grade: product.grade, score: product.score, size: .small)
                    .padding(4)
            }

            Text(product.name)
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
        .frame(width: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), grade \(product.grade), score \(product.score)")
    }
}
