import SwiftUI

struct Theme {
    static let background = Color(hex: "0a0e1a")
    static let surface = Color(hex: "111827")
    static let surfaceElevated = Color(hex: "1f2937")
    static let accent = Color(hex: "6c63ff")
    static let success = Color(hex: "22c55e")
    static let warning = Color(hex: "f59e0b")
    static let danger = Color(hex: "ef4444")
    static let textPrimary = Color(hex: "f1f5f9")
    static let textSecondary = Color(hex: "94a3b8")
    static let textDim = Color(hex: "475569")

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
