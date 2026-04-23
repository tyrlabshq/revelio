// REV-T3.2: Swap Cart — list of dupe swaps for every grade-D/F pantry item
// with a single "Open cart" button that opens the bundled affiliate URL.

import SwiftUI

// MARK: - Models

struct SwapCartDupe: Decodable {
    let barcode: String
    let name: String
    let brand: String
    let score: Int
    let grade: String
    let imageUrl: String?
    let category: String
}

struct SwapCartItem: Identifiable, Decodable {
    let sourceBarcode: String
    let sourceName: String
    let sourceBrand: String
    let sourceGrade: String
    let dupe: SwapCartDupe?
    let affiliateUrl: String
    let priceCents: Int?

    var id: String { sourceBarcode }
}

struct SwapCart: Decodable {
    let items: [SwapCartItem]
    let totalCents: Int
    let affiliateNetwork: String
    let bundledCheckoutUrl: String
}

// MARK: - ViewModel

@MainActor
final class SwapCartViewModel: ObservableObject {
    @Published var cart: SwapCart?
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: String

    init(baseURL: String = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app") {
        self.baseURL = baseURL
    }

    func load(token: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/swap-cart") else {
            error = "Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                error = "Unable to load swap cart"
                return
            }
            cart = try JSONDecoder().decode(SwapCart.self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logClick(source: String, dupe: String?, network: String, token: String?) async {
        guard let url = URL(string: "\(baseURL)/swap-cart/click") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "sourceBarcode": source,
            "dupeBarcode": dupe as Any,
            "affiliateNetwork": network,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - View

struct SwapCartView: View {
    @StateObject private var vm = SwapCartViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView()
                } else if let cart = vm.cart, !cart.items.isEmpty {
                    cartContent(cart)
                } else if let err = vm.error {
                    emptyState(title: "Couldn't load cart", subtitle: err)
                } else {
                    emptyState(title: "No swaps needed", subtitle: "Every pantry item already scores C or better. Nice work.")
                }
            }
            .navigationTitle("Swap Cart")
            .task {
                await vm.load(token: authViewModel.loadToken())
            }
        }
    }

    private func cartContent(_ cart: SwapCart) -> some View {
        VStack(spacing: 0) {
            List {
                ForEach(cart.items) { item in
                    SwapCartRow(item: item)
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Color.gray.opacity(0.12))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // Open cart CTA
            VStack(spacing: 8) {
                Button {
                    if let url = URL(string: cart.bundledCheckoutUrl) {
                        openURL(url)
                    }
                    Task {
                        await vm.logClick(
                            source: "bundle",
                            dupe: nil,
                            network: cart.affiliateNetwork,
                            token: authViewModel.loadToken()
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.fill")
                        Text("Open cart on \(cart.affiliateNetwork.capitalized)")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .cornerRadius(14)
                }
                Text("We earn a small commission. Prices shown at checkout.")
                    .font(.caption2)
                    .foregroundColor(Theme.textDim)
            }
            .padding(16)
        }
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Theme.textDim)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Row

private struct SwapCartRow: View {
    let item: SwapCartItem
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Source
            VStack(alignment: .leading, spacing: 4) {
                Text(item.sourceName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
                Text(item.sourceBrand)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                gradePill(item.sourceGrade)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundColor(Theme.textDim)
                .padding(.top, 6)

            // Dupe
            VStack(alignment: .leading, spacing: 4) {
                if let dupe = item.dupe {
                    Text(dupe.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                    Text(dupe.brand)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                    gradePill(dupe.grade)
                } else {
                    Text("No dupe found")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textDim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: item.affiliateUrl) {
                openURL(url)
            }
            Task {
                await SwapCartViewModel().logClick(
                    source: item.sourceBarcode,
                    dupe: item.dupe?.barcode,
                    network: "amazon",
                    token: authViewModel.loadToken()
                )
            }
        }
    }

    private func gradePill(_ grade: String) -> some View {
        Text(grade)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Theme.gradeColor(grade))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.gradeColor(grade).opacity(0.15))
            .cornerRadius(6)
    }
}

#Preview {
    SwapCartView()
        .environmentObject(AuthViewModel())
}
