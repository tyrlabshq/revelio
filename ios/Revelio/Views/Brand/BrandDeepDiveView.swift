import SwiftUI

// Container view for a brand's full product catalogue. Pairs with
// `BrandSummaryHeader` (donut + cleanest / worst) above a grade-filtered
// grid of products.
//
// Data contract: `GET /brands/:slug?page=1&limit=24&grade=A` returns
// `{ products: BrandProductCard[], page, limit, total, hasMore }`. Grade is
// optional; when .all we send no grade param.

struct BrandDeepDiveView: View {
    let slug: String
    let authToken: String?

    @State private var summary: BrandSummary?
    @State private var products: [BrandProductCard] = []
    @State private var selectedGrade: GradeFilter = .all
    @State private var page: Int = 1
    @State private var hasMore: Bool = true
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum GradeFilter: String, CaseIterable, Identifiable {
        case all, a, b, c, d, f
        var id: String { rawValue }
        var display: String { self == .all ? "All" : rawValue.uppercased() }
        var query: String? { self == .all ? nil : rawValue.uppercased() }
    }

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 160), spacing: 12)]
    private let baseURL: String = {
        // Same pattern as the other API-consuming views — env override in dev,
        // prod default. Kept inline to avoid a new shared config struct.
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let summary {
                    BrandSummaryHeader(summary: summary)
                        .padding(.horizontal)
                }

                gradeFilterBar
                    .padding(.horizontal)

                if let err = loadError, products.isEmpty {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding()
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(products) { product in
                        NavigationLink {
                            Text(product.name)
                                .navigationTitle(product.brand)
                        } label: {
                            productCard(product)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(product.name), grade \(product.grade)")
                        .onAppear {
                            if product.id == products.last?.id && hasMore && !isLoading {
                                Task { await loadMore() }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView().padding()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(slug.capitalized.replacingOccurrences(of: "-", with: " "))
        .task { await initialLoad() }
        .onChange(of: selectedGrade) { _, _ in
            Task { await resetAndLoad() }
        }
    }

    private var gradeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GradeFilter.allCases) { filter in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                            selectedGrade = filter
                        }
                    } label: {
                        Text(filter.display)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    selectedGrade == filter ? Color.accentColor : Color(.secondarySystemBackground)
                                )
                            )
                            .foregroundStyle(selectedGrade == filter ? Color.white : Color.primary)
                    }
                    .accessibilityLabel("Filter by grade \(filter.display)")
                }
            }
        }
    }

    private func productCard(_ p: BrandProductCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Text(p.grade)
                        .font(.caption.weight(.bold))
                        .padding(6)
                        .background(Circle().fill(Color.accentColor.opacity(0.85)))
                        .foregroundStyle(.white)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            Text(p.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("Score \(p.score)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func initialLoad() async {
        await resetAndLoad()
    }

    private func resetAndLoad() async {
        page = 1
        hasMore = true
        products = []
        loadError = nil
        await fetchSummary()
        await fetchPage(1)
    }

    private func loadMore() async {
        guard hasMore, !isLoading else { return }
        let next = page + 1
        await fetchPage(next)
    }

    private func fetchSummary() async {
        guard let url = URL(string: "\(baseURL)/brands/\(slug)/summary") else { return }
        do {
            var req = URLRequest(url: url)
            if let t = authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            let (data, _) = try await URLSession.shared.data(for: req)
            summary = try JSONDecoder().decode(BrandSummary.self, from: data)
        } catch {
            // Summary is nice-to-have; swallow errors and keep the grid.
        }
    }

    private func fetchPage(_ target: Int) async {
        var comps = URLComponents(string: "\(baseURL)/brands/\(slug)")
        var query = [URLQueryItem(name: "page", value: "\(target)"), URLQueryItem(name: "limit", value: "24")]
        if let g = selectedGrade.query { query.append(URLQueryItem(name: "grade", value: g)) }
        comps?.queryItems = query
        guard let url = comps?.url else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            var req = URLRequest(url: url)
            if let t = authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(BrandPage.self, from: data)
            products.append(contentsOf: resp.products)
            page = resp.page
            hasMore = resp.hasMore
        } catch {
            loadError = "Couldn't load products. Try again."
        }
    }
}

private struct BrandPage: Codable {
    let products: [BrandProductCard]
    let page: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
}
