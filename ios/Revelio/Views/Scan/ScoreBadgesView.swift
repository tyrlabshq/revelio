import SwiftUI

/// Horizontal stack of Nutri-Score / Nova / Eco-Score pills shown on the scan
/// result. Each badge is only rendered when the corresponding field is
/// non-nil (OFF doesn't always populate all three). Tapping any pill reveals a
/// short legend explaining what the badge means and where the data comes from.
struct ScoreBadgesView: View {
    let nutriScoreGrade: String?
    let novaGroup: Int?
    let ecoScoreGrade: String?

    @State private var showLegend: LegendItem? = nil

    var body: some View {
        // Only render the container if we have at least one badge.
        if nutriScoreGrade != nil || novaGroup != nil || ecoScoreGrade != nil {
            HStack(spacing: 8) {
                if let g = nutriScoreGrade {
                    NutriScorePill(grade: g)
                        .onTapGesture { showLegend = .nutri }
                }
                if let nova = novaGroup {
                    NovaGroupPill(group: nova)
                        .onTapGesture { showLegend = .nova }
                }
                if let eg = ecoScoreGrade {
                    EcoScorePill(grade: eg)
                        .onTapGesture { showLegend = .eco }
                }
                Spacer()
            }
            .sheet(item: $showLegend) { item in
                ScoreLegendSheet(item: item)
                    .presentationDetents([.medium])
            }
        }
    }
}

// ─── Nutri-Score pill (A-E colored) ──────────────────────────────────────────

struct NutriScorePill: View {
    let grade: String

    var body: some View {
        HStack(spacing: 6) {
            Text("NUTRI")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Text(grade.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(nutriColor(grade))
        .clipShape(Capsule())
        .accessibilityLabel("Nutri-Score grade \(grade)")
    }

    private func nutriColor(_ g: String) -> Color {
        switch g.uppercased() {
        case "A": return Color(hex: "038141")
        case "B": return Color(hex: "85bb2f")
        case "C": return Color(hex: "fecb02")
        case "D": return Color(hex: "ee8100")
        case "E": return Color(hex: "e63e11")
        default:  return Color(hex: "9ca3af")
        }
    }
}

// ─── Nova Group pill (1-4 processed-ness) ────────────────────────────────────

struct NovaGroupPill: View {
    let group: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("NOVA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Text("\(group)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(processedLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(novaColor)
        .clipShape(Capsule())
        .accessibilityLabel("Nova group \(group), \(processedLabel)")
    }

    private var processedLabel: String {
        switch group {
        case 1: return "Unprocessed"
        case 2: return "Culinary"
        case 3: return "Processed"
        case 4: return "Ultra-processed"
        default: return ""
        }
    }

    private var novaColor: Color {
        switch group {
        case 1: return Color(hex: "15803d")
        case 2: return Color(hex: "65a30d")
        case 3: return Color(hex: "ea580c")
        case 4: return Color(hex: "b91c1c")
        default: return Color(hex: "9ca3af")
        }
    }
}

// ─── Eco-Score pill (A-E colored) ────────────────────────────────────────────

struct EcoScorePill: View {
    let grade: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Text("ECO")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Text(grade.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ecoColor(grade))
        .clipShape(Capsule())
        .accessibilityLabel("Eco-Score grade \(grade)")
    }

    private func ecoColor(_ g: String) -> Color {
        switch g.uppercased() {
        case "A": return Color(hex: "1b5e20")
        case "B": return Color(hex: "388e3c")
        case "C": return Color(hex: "689f38")
        case "D": return Color(hex: "f57c00")
        case "E": return Color(hex: "bf360c")
        default:  return Color(hex: "9ca3af")
        }
    }
}

// ─── Legend sheet ────────────────────────────────────────────────────────────

enum LegendItem: String, Identifiable {
    case nutri, nova, eco
    var id: String { rawValue }
}

struct ScoreLegendSheet: View {
    let item: LegendItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(Theme.fontTitle)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
            }
            Text(body_)
                .font(Theme.fontBody)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(legendRows, id: \.0) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(row.1)
                            .frame(width: 14, height: 14)
                        Text(row.2)
                            .font(Theme.fontBody)
                            .foregroundColor(Theme.textPrimary)
                    }
                }
            }
            .padding(.top, 4)

            Text(source)
                .font(Theme.fontCaption)
                .foregroundColor(Theme.textDim)
                .padding(.top, 4)

            Spacer()
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
    }

    private var title: String {
        switch item {
        case .nutri: return "Nutri-Score"
        case .nova: return "Nova Group"
        case .eco: return "Eco-Score"
        }
    }

    private var body_: String {
        switch item {
        case .nutri:
            return "France's official at-a-glance nutrition grade, covering energy, saturated fat, sugar, salt, fiber, protein, and fruit/veg content per 100g."
        case .nova:
            return "A 1-4 classification of how industrially processed a food is. NOVA 1 is unprocessed whole food; NOVA 4 is ultra-processed."
        case .eco:
            return "Environmental impact grade combining packaging, origin, production, and transport. A = lowest footprint."
        }
    }

    private var legendRows: [(String, Color, String)] {
        switch item {
        case .nutri:
            return [
                ("A", Color(hex: "038141"), "A — excellent nutritional quality"),
                ("B", Color(hex: "85bb2f"), "B — good"),
                ("C", Color(hex: "fecb02"), "C — average"),
                ("D", Color(hex: "ee8100"), "D — poor"),
                ("E", Color(hex: "e63e11"), "E — unfavorable"),
            ]
        case .nova:
            return [
                ("1", Color(hex: "15803d"), "1 — Unprocessed / minimally processed"),
                ("2", Color(hex: "65a30d"), "2 — Processed culinary ingredients"),
                ("3", Color(hex: "ea580c"), "3 — Processed foods"),
                ("4", Color(hex: "b91c1c"), "4 — Ultra-processed"),
            ]
        case .eco:
            return [
                ("A", Color(hex: "1b5e20"), "A — very low impact"),
                ("B", Color(hex: "388e3c"), "B — low"),
                ("C", Color(hex: "689f38"), "C — moderate"),
                ("D", Color(hex: "f57c00"), "D — high"),
                ("E", Color(hex: "bf360c"), "E — very high"),
            ]
        }
    }

    private var source: String {
        switch item {
        case .nutri: return "Source: Open Food Facts / Santé publique France"
        case .nova: return "Source: Monteiro et al., NOVA classification"
        case .eco: return "Source: Open Food Facts Eco-Score consortium"
        }
    }
}

// ─── Preview ─────────────────────────────────────────────────────────────────

#Preview {
    VStack(spacing: 16) {
        ScoreBadgesView(nutriScoreGrade: "D", novaGroup: 4, ecoScoreGrade: "C")
        ScoreBadgesView(nutriScoreGrade: "A", novaGroup: 1, ecoScoreGrade: nil)
        ScoreBadgesView(nutriScoreGrade: nil, novaGroup: nil, ecoScoreGrade: nil)
    }
    .padding()
    .background(Theme.background)
}
