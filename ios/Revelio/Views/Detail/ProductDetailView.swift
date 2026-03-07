import SwiftUI

struct ProductDetailView: View {
    let scan: ScanResult
    @State private var showCitations = Set<String>()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authViewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ProductHeader(scan: scan)
                    ScoreBar(scan: scan).padding(.horizontal, 20).padding(.top, 20)

                    if !scan.flags.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FLAGGED INGREDIENTS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textDim).padding(.horizontal, 20).padding(.top, 24)
                            ForEach(scan.flags) { flag in
                                FlagCard(
                                    flag: flag,
                                    showCitation: showCitations.contains(flag.id),
                                    onToggle: {
                                        if showCitations.contains(flag.id) { showCitations.remove(flag.id) } else { showCitations.insert(flag.id) }
                                    },
                                    productCategory: scan.category.rawValue,
                                    authToken: authViewModel.loadToken(),
                                    isPro: authViewModel.currentUser?.isPro ?? false,
                                    userPriorities: []
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if scan.baseScore < 70 {
                        AlternativesSection().padding(.top, 16)
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { ShareButton() }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.foregroundColor(Theme.textSecondary) }
            }
        }
    }
}

struct ProductHeader: View {
    let scan: ScanResult
    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in image.resizable().aspectRatio(contentMode: .fit) } placeholder: {
                RoundedRectangle(cornerRadius: 12).fill(Theme.surfaceElevated).overlay(Image(systemName: "photo").foregroundColor(Theme.textDim).font(.largeTitle))
            }
            .frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 80)

            VStack(spacing: 6) {
                Text(scan.productName).font(.title2.bold()).foregroundColor(Theme.textPrimary).multilineTextAlignment(.center)
                Text(scan.brand).font(.subheadline).foregroundColor(Theme.textSecondary)
                Text("\(scan.category.icon) \(scan.category.displayName.uppercased())").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.textDim).padding(.horizontal, 10).padding(.vertical, 4).background(Theme.surfaceElevated).cornerRadius(6)
            }
            GradeBadge(grade: scan.grade, score: scan.displayScore, size: .large)
        }
        .padding(20).background(Theme.surface)
    }
}

struct ScoreBar: View {
    let scan: ScanResult
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCORE BREAKDOWN").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textDim)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.success).frame(width: geo.size.width * Double(scan.baseScore) / 100)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.danger).frame(width: geo.size.width * Double(100 - scan.baseScore) / 100)
                }
            }
            .frame(height: 12).background(Theme.surfaceElevated).cornerRadius(6)
            HStack {
                Label("\(scan.baseScore)% clean", systemImage: "checkmark.circle.fill").foregroundColor(Theme.success).font(.caption)
                Spacer()
                Label("\(scan.flags.count) flag\(scan.flags.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill").foregroundColor(Theme.danger).font(.caption)
            }
        }
    }
}

struct FlagCard: View {
    let flag: IngredientFlag
    let showCitation: Bool
    let onToggle: () -> Void
    // AI Explainer context (optional — degrades gracefully if nil)
    var productCategory: String = "general"
    var authToken: String? = nil
    var isPro: Bool = false
    var userPriorities: [String] = []

    @State private var showExplainer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(Color(hex: flag.severityColor)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(flag.ingredient.capitalized).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.textPrimary)
                    Text(flag.category).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: flag.severityColor))
                }
                Spacer()
                Text(flag.severityLabel).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: flag.severityColor))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Color(hex: flag.severityColor).opacity(0.15)).cornerRadius(4)
            }
            Text(flag.reason).font(.subheadline).foregroundColor(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)

            if let title = flag.citationTitle, let url = flag.citationUrl {
                Button(action: onToggle) {
                    HStack { Image(systemName: showCitation ? "chevron.up" : "chevron.down").font(.caption); Text("See the science").font(.caption.bold()) }
                        .foregroundColor(Theme.accent)
                }
                if showCitation {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.caption).italic().foregroundColor(Theme.textSecondary)
                        if let year = flag.citationYear { Text("Published \(year)").font(.caption2).foregroundColor(Theme.textDim) }
                        Link("Read study →", destination: URL(string: url)!).font(.caption.bold()).foregroundColor(Theme.accent)
                    }
                    .padding(10).background(Theme.surfaceElevated).cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // Ask Revelio button (only shown when auth token is available)
            if authToken != nil {
                Button {
                    showExplainer = true
                } label: {
                    HStack(spacing: 6) {
                        Text("🤖")
                            .font(.caption)
                        Text("Ask Revelio")
                            .font(.caption.bold())
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
        .padding(14).background(Theme.surface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: flag.severityColor).opacity(0.3), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: showCitation)
    }
}

struct AlternativesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLEANER OPTIONS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(Theme.textDim).padding(.horizontal, 20)
            ForEach([mockAlt1, mockAlt2]) { alt in AlternativeCard(product: alt).padding(.horizontal, 16) }
        }
    }
}

let mockAlt1 = AlternativeProduct(id: "1", name: "Primal Kitchen Mayo", brand: "Primal Kitchen", score: 88, grade: "A", imageUrl: nil, purchaseUrl: "https://amzn.to/3mock1", affiliateNetwork: "amazon", priceCents: 899)
let mockAlt2 = AlternativeProduct(id: "2", name: "Sir Kensington's Mayo", brand: "Sir Kensington's", score: 79, grade: "B", imageUrl: nil, purchaseUrl: "https://amzn.to/3mock2", affiliateNetwork: "amazon", priceCents: 749)

struct AlternativeCard: View {
    let product: AlternativeProduct
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated).frame(width: 52, height: 52).overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.textPrimary)
                Text(product.brand).font(.caption).foregroundColor(Theme.textSecondary)
                if let price = product.priceDisplay { Text(price).font(.caption).foregroundColor(Theme.textDim) }
            }
            Spacer()
            VStack(spacing: 6) {
                GradeBadge(grade: product.grade, score: product.score)
                Link("Buy", destination: URL(string: product.purchaseUrl)!).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.success).cornerRadius(6)
            }
        }
        .padding(14).background(Theme.surface).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.success.opacity(0.3), lineWidth: 1))
    }
}

struct ShareButton: View {
    var body: some View {
        Button {} label: { Image(systemName: "square.and.arrow.up").foregroundColor(Theme.accent) }
    }
}
