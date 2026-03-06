import SwiftUI

struct ScanResultCard: View {
    let scan: ScanResult
    let onRescan: () -> Void
    @State private var showDetail = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceElevated)
                            .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.productName).font(.headline).foregroundColor(Theme.textPrimary).lineLimit(2)
                        Text(scan.brand).font(.subheadline).foregroundColor(Theme.textSecondary)
                        Text("\(scan.category.icon) \(scan.category.displayName)").font(.caption).foregroundColor(Theme.textDim)
                    }
                    Spacer()
                    GradeBadge(grade: scan.grade, score: scan.displayScore, size: .large)
                }

                if !scan.flags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(scan.flags.prefix(2)) { flag in
                            HStack(spacing: 8) {
                                Circle().fill(Color(hex: flag.severityColor)).frame(width: 8, height: 8)
                                Text(flag.ingredient.capitalized).font(.caption).foregroundColor(Theme.textSecondary)
                                Spacer()
                                Text(flag.severityLabel).font(.caption2).foregroundColor(Color(hex: flag.severityColor))
                            }
                        }
                    }
                    .padding(12)
                    .background(Theme.surfaceElevated)
                    .cornerRadius(10)
                }

                HStack(spacing: 12) {
                    Button { onRescan() } label: { Label("Re-scan", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .tint(Theme.textSecondary)
                    Button { showDetail = true } label: { Label("Full Report", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
            .padding(20)
            .background(Theme.surface)
            .cornerRadius(24, corners: [.topLeft, .topRight])
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showDetail) { ProductDetailView(scan: scan) }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
