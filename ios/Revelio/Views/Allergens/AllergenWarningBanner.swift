import SwiftUI

// ─── Allergen Warning Banner ──────────────────────────────────────────────────
// Shown at the top of ProductDetailView when allergens are detected.

struct AllergenWarningBanner: View {
    let matches: [AllergenMatch]
    @State private var isExpanded = true

    private var highestSeverity: AllergenSeverity {
        if matches.contains(where: { $0.allergen.severity == .avoid }) { return .avoid }
        if matches.contains(where: { $0.allergen.severity == .caution }) { return .caution }
        return .note
    }

    private var bannerColor: Color {
        Color(hex: highestSeverity.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(highestSeverity == .avoid ? "🚫" : highestSeverity == .caution ? "⚠️" : "📝")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headerTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(bannerColor)
                        Text("\(matches.count) match\(matches.count == 1 ? "" : "es") for \(matches.first?.profileName ?? "your profile")")
                            .font(.caption)
                            .foregroundColor(bannerColor.opacity(0.8))
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(bannerColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Expanded match list
            if isExpanded {
                Divider()
                    .background(bannerColor.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(matches) { match in
                        HStack(spacing: 8) {
                            Text(match.allergen.severity.emoji)
                                .font(.subheadline)

                            Text(match.ingredient.capitalized)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)

                            Text("→")
                                .foregroundColor(Theme.textDim)
                                .font(.caption)

                            Text(match.allergen.name.capitalized)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)

                            Spacer()

                            Text(match.allergen.severity.label)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: match.allergen.severity.colorHex))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(Color(hex: match.allergen.severity.colorHex).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(bannerColor.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(bannerColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: bannerColor.opacity(0.1), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var headerTitle: String {
        switch highestSeverity {
        case .avoid: return "Contains allergens to AVOID"
        case .caution: return "Contains allergens — CAUTION"
        case .note: return "Allergen presence noted"
        }
    }
}
