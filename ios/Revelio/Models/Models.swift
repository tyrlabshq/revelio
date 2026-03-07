import Foundation

struct ScanResult: Identifiable, Codable {
    let id: String
    let barcode: String
    let productName: String
    let brand: String
    let category: ProductCategory
    let imageUrl: String?
    let ingredients: [String]
    let flags: [IngredientFlag]
    let baseScore: Int
    let personalizedScore: Int
    let grade: String
    let alternatives: [AlternativeProduct]?
    let scannedAt: Date

    var displayScore: Int { personalizedScore }
}

enum ProductCategory: String, Codable, CaseIterable {
    case food, cosmetics, cleaning, supplements
    var displayName: String {
        switch self {
        case .food: return "Food"
        case .cosmetics: return "Cosmetic"
        case .cleaning: return "Cleaning"
        case .supplements: return "Supplement"
        }
    }
    var icon: String {
        switch self {
        case .food: return "🍎"
        case .cosmetics: return "💄"
        case .cleaning: return "🧴"
        case .supplements: return "💊"
        }
    }
}

struct IngredientFlag: Identifiable, Codable {
    let id: String
    let ingredient: String
    let severity: Int
    let category: String
    let reason: String
    let citationTitle: String?
    let citationUrl: String?
    let citationYear: Int?
    let priorities: [String]
    // REV-08: EU E-number and multi-citation support
    var eNumber: String? = nil
    var citations: [String]? = nil

    /// Severity label conforming to SAFE | CAUTION | AVOID spectrum
    var severityRating: String {
        switch severity {
        case 0, 1: return "SAFE"
        case 2: return "CAUTION"
        case 3: return "AVOID"
        default: return "SAFE"
        }
    }

    var severityColor: String {
        switch severity {
        case 1: return "f59e0b"
        case 2: return "f97316"
        case 3: return "ef4444"
        default: return "22c55e"
        }
    }
    var severityLabel: String {
        switch severity {
        case 1: return "WATCH"
        case 2: return "CONCERNING"
        case 3: return "AVOID"
        default: return "FINE"
        }
    }
}

struct AlternativeProduct: Identifiable, Codable {
    let id: String
    let name: String
    let brand: String
    let score: Int
    let grade: String
    let imageUrl: String?
    let purchaseUrl: String
    let affiliateNetwork: String
    let priceCents: Int?
    var priceDisplay: String? {
        guard let cents = priceCents else { return nil }
        return String(format: "$%.2f", Double(cents) / 100)
    }
}

struct UserProfile: Codable {
    var id: String
    var name: String
    var phone: String
    var tier: String
    var priorities: [String]
    var allergies: [String]
    var dietaryRestrictions: [String]
    var isPro: Bool { tier == "pro" }
}

struct PantryItem: Identifiable, Codable {
    let id: String
    let barcode: String
    let productName: String
    let brand: String
    let score: Int
    let grade: String
    let imageUrl: String?
    let quantity: Int
    let addedAt: Date
}
