import SwiftUI

struct ScanResultCard: View {
    let scan: ScanResult
    let onRescan: () -> Void
    @State private var showDetail = false
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var cardOffset: CGFloat = 300
    @State private var cardOpacity: Double = 0
    @State private var didHaptic = false

    // Respect system Reduce Motion for the reveal animation. When enabled we
    // render the card in its final position immediately rather than springing
    // it up from the bottom.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                // Drag indicator
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 32, height: 4)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                // Header: Image + Info + Score
                HStack(spacing: 16) {
                    // Product image
                    AsyncImage(url: URL(string: scan.imageUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surfaceElevated)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(Theme.textDim)
                                    .accessibilityHidden(true)
                            )
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)

                    // Product info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.productName)
                            .font(.headline)
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)
                        Text(scan.brand)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)

                        // Category chip
                        HStack(spacing: 4) {
                            Text(scan.category.icon)
                                .accessibilityHidden(true)
                            Text(scan.category.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(Theme.textDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceElevated)
                        .cornerRadius(6)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Category: \(scan.category.displayName)")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(scan.productName), by \(scan.brand)")

                    Spacer()

                    // Score badge
                    GradeBadge(grade: scan.grade, score: scan.displayScore, size: .large)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Grade \(scan.grade), \(gradeMeaning(scan.grade)), score \(scan.displayScore) out of 100")
                }

                // Nutri / Nova / Eco badges (Track 2.1–2.3). Rendered only when
                // the server returned any of the fields for this product.
                ScoreBadgesView(
                    nutriScoreGrade: scan.nutriScoreGrade,
                    novaGroup: scan.novaGroup,
                    ecoScoreGrade: scan.ecoScoreGrade
                )

                // Ingredient flags as chips
                if !scan.flags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(scan.flags.prefix(4)) { flag in
                            FlagChip(flag: flag)
                        }
                    }
                }

                // Brand deep-dive entry point.
                NavigationLink("View all products from this brand →", destination: BrandDeepDiveView(brandName: scan.brand))
                    .font(Theme.fontCaption)
                    .foregroundColor(Theme.accent)

                // Action buttons
                VStack(spacing: 12) {
                    Button { showDetail = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .accessibilityHidden(true)
                            Text("View Full Report")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("View full report")
                    .accessibilityHint("Opens the complete ingredient breakdown and citations for this product")

                    Button { onRescan() } label: {
                        Text("Re-scan")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.vertical, 8)
                    }
                    .accessibilityLabel("Re-scan")
                    .accessibilityHint("Dismisses this result and returns to the camera")
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
            if reduceMotion {
                // Snap the card into place without the spring transform.
                cardOffset = 0
                cardOpacity = 1
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    cardOffset = 0
                    cardOpacity = 1
                }
            }
            // Fire the grade-reveal haptic once per scan. Guarded so SwiftUI
            // re-render cycles (state changes inside this view) don't trigger
            // it a second time.
            if !didHaptic {
                didHaptic = true
                HapticsService.shared.gradeReveal(scan.grade)
            }
        }
        .sheet(isPresented: $showDetail) { ProductDetailView(scan: scan).environmentObject(authViewModel) }
    }

    /// Short description of what a grade means for VoiceOver users. Pairs with
    /// the grade letter itself, e.g. "Grade A, clean".
    private func gradeMeaning(_ grade: String) -> String {
        switch grade.uppercased() {
        case "A": return "clean"
        case "B": return "good"
        case "C": return "mixed"
        case "D": return "concerning"
        case "F": return "avoid"
        default:  return "unknown"
        }
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
                .accessibilityHidden(true)
            Text(flag.ingredient.capitalized)
                .font(.caption)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flagged ingredient: \(flag.ingredient.capitalized)")
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
