import SwiftUI

struct ScanResultCard: View {
    let scan: ScanResult
    let onRescan: () -> Void
    @State private var showDetail = false
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var cardOffset: CGFloat = 300
    @State private var cardOpacity: Double = 0

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                // Drag indicator
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 32, height: 4)
                    .padding(.top, 8)
                
                // Header: Image + Info + Score
                HStack(spacing: 16) {
                    // Product image
                    AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surfaceElevated)
                            .overlay(Image(systemName: "photo").foregroundColor(Theme.textDim))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Product info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.productName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)
                        Text(scan.brand)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Theme.textSecondary)
                        
                        // Category chip
                        HStack(spacing: 4) {
                            Text(scan.category.icon)
                            Text(scan.category.displayName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Theme.textDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // Score badge
                    GradeBadge(grade: scan.grade, score: scan.displayScore, size: .large)
                }
                
                // Ingredient flags as chips
                if !scan.flags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(scan.flags.prefix(4)) { flag in
                            FlagChip(flag: flag)
                        }
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button { showDetail = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View Full Report")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(12)
                    }
                    
                    Button { onRescan() } label: {
                        Text("Re-scan")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(20)
            .background(Theme.surface)
            .cornerRadius(28, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -4)
            .offset(y: cardOffset)
            .opacity(cardOpacity)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                cardOffset = 0
                cardOpacity = 1
            }
        }
        .sheet(isPresented: $showDetail) { ProductDetailView(scan: scan).environmentObject(authViewModel) }
    }
}

// Flag chip component
struct FlagChip: View {
    let flag: IngredientFlag
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: flag.severityColor))
                .frame(width: 6, height: 6)
            Text(flag.ingredient.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceElevated)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: flag.severityColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// Flow layout for chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
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

#Preview {
    ScanResultCard(scan: ScanResult(
        id: "1", barcode: "123",
        productName: "Test Product", brand: "Test Brand",
        category: .food, imageUrl: nil,
        ingredients: ["water", "sugar"],
        flags: [IngredientFlag(id: "1", ingredient: "sugar", severity: 1, category: "SWEETENER", reason: "High sugar content", citationTitle: nil, citationUrl: nil, citationYear: nil, priorities: [])],
        baseScore: 75, personalizedScore: 75, grade: "B",
        alternatives: nil, scannedAt: Date()
    ), onRescan: {})
}
