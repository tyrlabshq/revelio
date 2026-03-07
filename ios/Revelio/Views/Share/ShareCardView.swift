import SwiftUI

// ─── Share Card Variant ────────────────────────────────────────────────────────

enum ShareCardVariant {
    case portrait   // 1080×1920 — TikTok / Instagram Stories
    case square     // 1080×1080 — Instagram Feed / Twitter

    /// Logical SwiftUI points (rendered 3× for 1080px output)
    var size: CGSize {
        switch self {
        case .portrait: return CGSize(width: 360, height: 640)
        case .square:   return CGSize(width: 360, height: 360)
        }
    }
}

// ─── Share Card View ──────────────────────────────────────────────────────────
/// Rendered offscreen via ImageRenderer — all layout in SwiftUI points at 360pt wide.
/// Call ShareCardGenerator.render(scan:variant:) to get a UIImage.

struct ShareCardView: View {
    let scan: ScanResult
    let variant: ShareCardVariant
    /// Optional personalization label ("Seed Oil Free")
    var activePriority: String? = nil

    // Derived
    private var topFlags: [IngredientFlag] {
        Array(scan.flags
            .sorted { $0.severity > $1.severity }
            .prefix(3))
    }

    private var gradeBadgeWidth: CGFloat {
        variant.size.width * 0.40
    }

    var body: some View {
        ZStack {
            // ── Background gradient ──────────────────────────────────────────
            LinearGradient(
                colors: [Color(hex: "0a0e1a"), Color(hex: "1a1040")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Subtle grid overlay ──────────────────────────────────────────
            GridOverlay()
                .opacity(0.04)

            // ── Content stack ────────────────────────────────────────────────
            if variant == .portrait {
                PortraitLayout(
                    scan: scan,
                    topFlags: topFlags,
                    gradeBadgeWidth: gradeBadgeWidth,
                    activePriority: activePriority
                )
            } else {
                SquareLayout(
                    scan: scan,
                    topFlags: topFlags,
                    gradeBadgeWidth: gradeBadgeWidth,
                    activePriority: activePriority
                )
            }
        }
        .frame(width: variant.size.width, height: variant.size.height)
    }
}

// ─── Portrait Layout (360×640) ────────────────────────────────────────────────

private struct PortraitLayout: View {
    let scan: ScanResult
    let topFlags: [IngredientFlag]
    let gradeBadgeWidth: CGFloat
    let activePriority: String?

    var body: some View {
        VStack(spacing: 0) {

            // 1. Header
            CardHeader()
                .padding(.top, 28)
                .padding(.horizontal, 24)

            // 2. Product image
            ProductImageBlock(imageUrl: scan.imageUrl)
                .padding(.top, 20)

            // 3. Product name + brand
            VStack(spacing: 4) {
                Text(scan.productName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(scan.brand.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "8892b0"))
                    .tracking(1.5)
            }
            .padding(.top, 14)
            .padding(.horizontal, 24)

            // 4 & 6. Grade badge + score
            GradeScoreBlock(
                grade: scan.grade,
                score: scan.displayScore,
                badgeWidth: gradeBadgeWidth
            )
            .padding(.top, 18)

            // 5. Personalized note
            if let priority = activePriority {
                PersonalizedNote(priority: priority)
                    .padding(.top, 10)
            }

            // 7. Top flags
            if !topFlags.isEmpty {
                FlagsBlock(flags: topFlags)
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            // 8. Bottom CTA
            BottomCTA()
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
        }
    }
}

// ─── Square Layout (360×360) ──────────────────────────────────────────────────

private struct SquareLayout: View {
    let scan: ScanResult
    let topFlags: [IngredientFlag]
    let gradeBadgeWidth: CGFloat
    let activePriority: String?

    var body: some View {
        VStack(spacing: 0) {

            // Header (compact)
            CardHeader(compact: true)
                .padding(.top, 18)
                .padding(.horizontal, 20)

            // Product name + grade in one row
            HStack(alignment: .center, spacing: 16) {
                // Left: name + brand + flags
                VStack(alignment: .leading, spacing: 6) {
                    Text(scan.productName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(scan.brand.uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "8892b0"))
                        .tracking(1.2)

                    if !topFlags.isEmpty {
                        FlagsBlock(flags: Array(topFlags.prefix(2)), compact: true)
                            .padding(.top, 4)
                    }
                }

                Spacer()

                // Right: giant grade
                GradeScoreBlock(
                    grade: scan.grade,
                    score: scan.displayScore,
                    badgeWidth: 110,
                    compact: true
                )
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            // Personalized note
            if let priority = activePriority {
                PersonalizedNote(priority: priority, compact: true)
                    .padding(.horizontal, 20)
            }

            // Bottom CTA (compact)
            BottomCTA(compact: true)
                .padding(.bottom, 16)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
    }
}

// ─── Card Header ──────────────────────────────────────────────────────────────

private struct CardHeader: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Logo mark — stylized "R" in a circle
            ZStack {
                Circle()
                    .fill(Color(hex: "00B87C"))
                    .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                Text("R")
                    .font(.system(size: compact ? 12 : 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("revelio")
                    .font(.system(size: compact ? 14 : 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                if !compact {
                    Text("Know what's really in it")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "8892b0"))
                }
            }

            Spacer()

            // "FREE SCAN" chip
            Text("FREE SCAN")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Color(hex: "00B87C"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "00B87C").opacity(0.18))
                .cornerRadius(4)
        }
    }
}

// ─── Product Image Block ──────────────────────────────────────────────────────

private struct ProductImageBlock: View {
    let imageUrl: String?

    var body: some View {
        Group {
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ProductImagePlaceholder()
                    }
                }
            } else {
                ProductImagePlaceholder()
            }
        }
        .frame(width: 140, height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color(hex: "00B87C").opacity(0.2), radius: 20, x: 0, y: 8)
    }
}

private struct ProductImagePlaceholder: View {
    var body: some View {
        ZStack {
            Color(hex: "1e2a3a")
            Image(systemName: "cube.box.fill")
                .font(.system(size: 40))
                .foregroundColor(Color(hex: "8892b0"))
        }
    }
}

// ─── Grade + Score Block ──────────────────────────────────────────────────────

private struct GradeScoreBlock: View {
    let grade: String
    let score: Int
    let badgeWidth: CGFloat
    var compact: Bool = false

    private var gradeColor: Color {
        Theme.gradeColor(grade)
    }

    var body: some View {
        VStack(spacing: compact ? 4 : 8) {
            // Giant grade letter
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 16 : 20)
                    .fill(gradeColor.opacity(0.15))
                    .frame(width: badgeWidth, height: badgeWidth)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 16 : 20)
                            .stroke(gradeColor.opacity(0.4), lineWidth: 2)
                    )

                Text(grade)
                    .font(.system(size: badgeWidth * 0.62, weight: .black, design: .rounded))
                    .foregroundColor(gradeColor)
            }

            // Score number
            Text("\(score) / 100")
                .font(.system(size: compact ? 16 : 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// ─── Flags Block ──────────────────────────────────────────────────────────────

private struct FlagsBlock: View {
    let flags: [IngredientFlag]
    var compact: Bool = false

    private func dotColor(for flag: IngredientFlag) -> Color {
        switch flag.severity {
        case 3:   return Color(hex: "ef4444")   // danger  → red
        case 2:   return Color(hex: "f97316")   // caution → orange
        default:  return Color(hex: "f59e0b")   // warning → yellow
        }
    }

    private func labelColor(for flag: IngredientFlag) -> String {
        switch flag.severity {
        case 3:   return "AVOID"
        case 2:   return "CAUTION"
        default:  return "WATCH"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            if !compact {
                Text("TOP FLAGS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "8892b0"))
                    .tracking(1.5)
            }

            ForEach(flags) { flag in
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor(for: flag))
                        .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)

                    Text(flag.ingredient.capitalized)
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(labelColor(for: flag))
                        .font(.system(size: compact ? 7 : 8, weight: .bold, design: .monospaced))
                        .foregroundColor(dotColor(for: flag))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(dotColor(for: flag).opacity(0.15))
                        .cornerRadius(3)
                }
            }
        }
        .padding(compact ? 8 : 12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// ─── Personalized Note ────────────────────────────────────────────────────────

private struct PersonalizedNote: View {
    let priority: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("🎯")
                .font(.system(size: compact ? 10 : 12))
            Text("Scored for: \(priority)")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundColor(Color(hex: "00B87C"))
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 5 : 7)
        .background(Color(hex: "00B87C").opacity(0.12))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "00B87C").opacity(0.25), lineWidth: 1)
        )
    }
}

// ─── Bottom CTA ───────────────────────────────────────────────────────────────

private struct BottomCTA: View {
    var compact: Bool = false

    var body: some View {
        HStack {
            // Scan icon badge
            HStack(spacing: 5) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundColor(Color(hex: "00B87C"))

                VStack(alignment: .leading, spacing: 0) {
                    Text("Scan yours →")
                        .font(.system(size: compact ? 10 : 12, weight: .bold))
                        .foregroundColor(.white)
                    Text("revelio.app")
                        .font(.system(size: compact ? 9 : 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "00B87C"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "00B87C").opacity(0.3), lineWidth: 1)
            )

            Spacer()

            // QR-style decoration using SF Symbols
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(hex: "00B87C").opacity(0.4), lineWidth: 1.5)
                    .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                Image(systemName: "qrcode")
                    .font(.system(size: compact ? 18 : 22))
                    .foregroundColor(Color(hex: "00B87C").opacity(0.6))
            }
        }
    }
}

// ─── Grid Overlay (Subtle Texture) ────────────────────────────────────────────

private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 32
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            var path = Path()
            for col in 0...cols {
                let x = CGFloat(col) * spacing
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...rows {
                let y = CGFloat(row) * spacing
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.white), lineWidth: 0.5)
        }
    }
}

// ─── Preview ──────────────────────────────────────────────────────────────────

#if DEBUG
#Preview("Portrait") {
    ShareCardView(
        scan: ShareCardPreviewData.scan,
        variant: .portrait,
        activePriority: "Seed Oil Free"
    )
    .background(Color.black)
}

#Preview("Square") {
    ShareCardView(
        scan: ShareCardPreviewData.scan,
        variant: .square,
        activePriority: "Seed Oil Free"
    )
    .background(Color.black)
}

enum ShareCardPreviewData {
    static let scan = ScanResult(
        id: "share-preview",
        barcode: "0123456789",
        productName: "Classic Mayonnaise",
        brand: "Hellmann's",
        category: .food,
        imageUrl: nil,
        ingredients: ["soybean oil", "water", "whole eggs", "vinegar", "salt", "calcium disodium edta"],
        flags: [
            IngredientFlag(
                id: "f1", ingredient: "soybean oil", severity: 3,
                category: "SEED OIL",
                reason: "High omega-6, linked to inflammation.",
                citationTitle: nil, citationUrl: nil, citationYear: nil,
                priorities: ["anti-inflammatory"]
            ),
            IngredientFlag(
                id: "f2", ingredient: "calcium disodium edta", severity: 1,
                category: "PRESERVATIVE",
                reason: "Synthetic chelating agent.",
                citationTitle: nil, citationUrl: nil, citationYear: nil,
                priorities: []
            )
        ],
        baseScore: 34,
        personalizedScore: 28,
        grade: "F",
        alternatives: nil,
        scannedAt: Date()
    )
}
#endif
