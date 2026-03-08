import SwiftUI

// MARK: - Models

struct ExploreProduct: Identifiable, Codable {
    let id: String
    let barcode: String?
    let productName: String
    let brand: String
    let category: String
    let imageUrl: String?
    let score: Int
    let grade: String

    enum CodingKeys: String, CodingKey {
        case id, barcode, productName = "product_name", brand, category
        case imageUrl = "image_url", score, grade
    }
}

struct SearchResponse: Codable {
    let results: [ExploreProduct]
}

struct ProductListResponse: Codable {
    let products: [ExploreProduct]
}

// MARK: - ViewModel

@MainActor
class ExploreViewModel: ObservableObject {
    @Published var searchResults: [ExploreProduct] = []
    @Published var trending: [ExploreProduct] = []
    @Published var hallOfShame: [ExploreProduct] = []
    @Published var hiddenGems: [ExploreProduct] = []
    @Published var recentlyAdded: [ExploreProduct] = []

    @Published var isSearching = false
    @Published var isLoadingFeed = false
    @Published var searchError: String? = nil

    private let apiBase: String
    private var searchTask: Task<Void, Never>? = nil

    init() {
        apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
    }

    // MARK: - Search (debounced 300ms)

    func onQueryChanged(_ q: String) {
        searchTask?.cancel()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search(q: q, category: nil)
        }
    }

    func search(q: String, category: String?) async {
        isSearching = true
        searchError = nil
        var comps = URLComponents(string: "\(apiBase)/products/search")!
        var items: [URLQueryItem] = [URLQueryItem(name: "q", value: q)]
        if let cat = category { items.append(URLQueryItem(name: "category", value: cat)) }
        comps.queryItems = items
        guard let url = comps.url else { isSearching = false; return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
            searchResults = resp.results
        } catch {
            if !Task.isCancelled {
                searchError = "Search failed"
                searchResults = []
            }
        }
        isSearching = false
    }

    // MARK: - Feed

    func loadFeed() async {
        guard !isLoadingFeed else { return }
        isLoadingFeed = true
        async let t = fetchList("/products/trending?limit=20")
        async let h = fetchList("/products/hall-of-shame?limit=20")
        async let g = fetchList("/products/hidden-gems?limit=20")
        async let r = fetchList("/products/recently-added?limit=20")
        trending = await t
        hallOfShame = await h
        hiddenGems = await g
        recentlyAdded = await r
        isLoadingFeed = false
    }

    private func fetchList(_ path: String) async -> [ExploreProduct] {
        guard let url = URL(string: "\(apiBase)\(path)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(ProductListResponse.self, from: data)
            return resp.products
        } catch {
            return []
        }
    }
}

// MARK: - ExploreView

struct ExploreView: View {
    @StateObject private var vm = ExploreViewModel()
    @State private var query = ""
    @State private var selectedCategory: ProductCategory? = nil
    @State private var showCategoryBrowse = false

    var isSearchActive: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // ── Search bar ──────────────────────────────
                        searchBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 12)

                        if isSearchActive {
                            searchResultsSection
                        } else {
                            feedSections
                        }
                    }
                }
                .refreshable { await vm.loadFeed() }
            }
            .navigationTitle("Explore")
            .task { await vm.loadFeed() }
            .navigationDestination(isPresented: $showCategoryBrowse) {
                if let cat = selectedCategory {
                    CategoryBrowseView(category: cat)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textDim)
            TextField("Search products, brands, ingredients...", text: $query)
                .foregroundColor(Theme.textPrimary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newVal in vm.onQueryChanged(newVal) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textDim)
                }
            }
        }
        .padding(12)
        .background(Theme.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if vm.isSearching {
            ProgressView()
                .padding(.top, 48)
        } else if let err = vm.searchError {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundColor(Theme.textDim)
                Text(err).foregroundColor(Theme.textSecondary).font(.subheadline)
            }
            .padding(.top, 48)
        } else if vm.searchResults.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundColor(Theme.textDim)
                Text("No results for \"\(query)\"")
                    .font(.headline).foregroundColor(Theme.textSecondary)
            }
            .padding(.top, 48)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(vm.searchResults) { product in
                    ExploreProductRow(product: product)
                    Divider().padding(.leading, 72)
                }
            }
            .background(Theme.surface)
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Feed

    private var feedSections: some View {
        VStack(spacing: 24) {
            categoriesSection
            if !vm.trending.isEmpty { trendingSection }
            if !vm.hallOfShame.isEmpty { hallOfShameSection }
            if !vm.hiddenGems.isEmpty { hiddenGemsSection }
            if !vm.recentlyAdded.isEmpty { recentlyAddedSection }
            if vm.isLoadingFeed && vm.trending.isEmpty {
                feedSkeleton
            }
            Color.clear.frame(height: 32)
        }
    }

    // MARK: - Categories Grid

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExploreSectionHeader(title: "Browse by Category")
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ProductCategory.allCases, id: \.self) { cat in
                    CategoryTile(category: cat)
                        .onTapGesture {
                            selectedCategory = cat
                            showCategoryBrowse = true
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Trending

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExploreSectionHeader(title: "🔥 Trending Scans", subtitle: "Most scanned this week")
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.trending) { product in
                        ProductCard(product: product)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Hall of Shame

    private var hallOfShameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExploreSectionHeader(title: "🚨 Hall of Shame", subtitle: "Famous brands, terrible scores")
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.hallOfShame) { product in
                        ProductCard(product: product, badgeAccent: true)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Hidden Gems

    private var hiddenGemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExploreSectionHeader(title: "✨ Hidden Gems", subtitle: "Clean swaps you didn't know existed")
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.hiddenGems) { product in
                        ProductCard(product: product)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Recently Added

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExploreSectionHeader(title: "🆕 Recently Added", subtitle: "Fresh to our database")
                .padding(.horizontal)

            LazyVStack(spacing: 0) {
                ForEach(vm.recentlyAdded) { product in
                    ExploreProductRow(product: product)
                    if product.id != vm.recentlyAdded.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Theme.surface)
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    private var feedSkeleton: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .frame(height: 80)
                    .padding(.horizontal)
                    .shimmer()
            }
        }
    }
}

// MARK: - Supporting Views

struct ExploreSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(Theme.textPrimary)
            if let sub = subtitle {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

struct CategoryTile: View {
    let category: ProductCategory

    var body: some View {
        HStack(spacing: 10) {
            Text(category.icon)
                .font(.title2)
            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textDim)
        }
        .padding(14)
        .background(Theme.surface)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

struct ProductCard: View {
    let product: ExploreProduct
    var badgeAccent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Product image
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
                .frame(width: 130, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                GradeBadge(grade: product.grade, score: product.score, size: .small)
                    .padding(6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(product.productName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                    .frame(width: 130, alignment: .leading)
                Text(product.brand)
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 130)
    }
}

struct ExploreProductRow: View {
    let product: ExploreProduct

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: product.imageUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    ZStack {
                        Theme.surfaceElevated
                        Image(systemName: "photo").foregroundColor(Theme.textDim).font(.caption)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.productName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(product.brand)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
            GradeBadge(grade: product.grade, score: product.score, size: .small)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Category Browse

struct CategoryBrowseView: View {
    let category: ProductCategory
    @StateObject private var vm = ExploreViewModel()
    @State private var results: [ExploreProduct] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if results.isEmpty {
                VStack(spacing: 8) {
                    Text(category.icon).font(.system(size: 48))
                    Text("No products yet in \(category.displayName)")
                        .foregroundColor(Theme.textSecondary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { product in
                            ExploreProductRow(product: product)
                            Divider().padding(.leading, 72)
                        }
                    }
                    .background(Theme.surface)
                    .cornerRadius(12)
                    .padding()
                }
            }
        }
        .navigationTitle("\(category.icon) \(category.displayName)")
        .task {
            await vm.search(q: "", category: category.rawValue)
            results = vm.searchResults
            isLoading = false
        }
    }
}

// MARK: - Shimmer Modifier (lightweight)

extension View {
    func shimmer() -> some View {
        self.opacity(0.5)
    }
}

#Preview {
    ExploreView()
}
