import SwiftUI

struct Theme {
    // Backgrounds
    static let background = Color(hex: "FAFAF8")       // warm off-white
    static let surface = Color(hex: "FFFFFF")           // pure white cards
    static let surfaceElevated = Color(hex: "F2F2EE")   // very light warm gray

    // Brand
    static let accent = Color(hex: "00B87C")            // fresh emerald green

    // Text
    static let textPrimary = Color(hex: "111827")       // near-black
    static let textSecondary = Color(hex: "6B7280")     // medium gray
    static let textDim = Color(hex: "9CA3AF")           // light gray

    // Semantic
    static let success = Color(hex: "22C55E")
    static let warning = Color(hex: "F59E0B")
    static let danger = Color(hex: "EF4444")

    // Typography System
    static let fontTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let fontHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let fontBody = Font.system(size: 15, weight: .regular, design: .default)
    static let fontCaption = Font.system(size: 12, weight: .medium, design: .default)
    static let fontLabel = Font.system(size: 10, weight: .semibold, design: .monospaced)

    static func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return Color(hex: "22c55e")
        case "B": return Color(hex: "84cc16")
        case "C": return Color(hex: "f59e0b")
        case "D": return Color(hex: "f97316")
        default:  return Color(hex: "ef4444")
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
