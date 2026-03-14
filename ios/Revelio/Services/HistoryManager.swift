import SwiftUI
import Foundation

/// Persists scan history and favorites locally using UserDefaults JSON storage.
@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var history: [ScanResult] = []
    @Published private(set) var favorites: Set<String> = [] // barcode strings

    private let historyKey = "scan_history_v1"
    private let favoritesKey = "favorites_barcodes_v1"
    private let maxHistory = 100

    private init() {
        if CommandLine.arguments.contains("UI_TESTING") {
            loadSampleData()
        } else {
            load()
        }
    }

    // MARK: - Sample Data for Screenshots

    private func loadSampleData() {
        let now = Date()
        func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

        func flag(_ ingredient: String, _ severity: Int, _ category: String, _ reason: String) -> IngredientFlag {
            IngredientFlag(id: "flag_\(ingredient.prefix(6))", ingredient: ingredient,
                           severity: severity, category: category, reason: reason,
                           citationTitle: nil, citationUrl: nil, citationYear: nil, priorities: [])
        }

        history = [
            ScanResult(id: "s1", barcode: "007017700576", productName: "Greek Yogurt Plain",
                       brand: "Chobani", category: .food, imageUrl: nil,
                       ingredients: ["Cultured Grade A Nonfat Milk", "Live and Active Cultures"],
                       flags: [], baseScore: 92, personalizedScore: 92, grade: "A",
                       alternatives: nil, scannedAt: hoursAgo(1)),
            ScanResult(id: "s2", barcode: "003800017977", productName: "Cheez-It Original",
                       brand: "Sunshine Snacks", category: .food, imageUrl: nil,
                       ingredients: ["Enriched Flour", "Vegetable Oil", "Soybean Oil", "Salt", "TBHQ"],
                       flags: [flag("TBHQ", 2, "Preservatives", "Synthetic antioxidant, immune disruption"),
                               flag("Soybean Oil", 1, "Oils", "High omega-6 inflammatory oil")],
                       baseScore: 55, personalizedScore: 55, grade: "C",
                       alternatives: nil, scannedAt: hoursAgo(4)),
            ScanResult(id: "s3", barcode: "004119600048", productName: "Extra Virgin Olive Oil",
                       brand: "California Olive Ranch", category: .food, imageUrl: nil,
                       ingredients: ["Extra Virgin Olive Oil"],
                       flags: [], baseScore: 95, personalizedScore: 95, grade: "A",
                       alternatives: nil, scannedAt: hoursAgo(8)),
            ScanResult(id: "s4", barcode: "001600027528", productName: "Nature Valley Granola Bar",
                       brand: "General Mills", category: .food, imageUrl: nil,
                       ingredients: ["Whole Grain Oats", "Sugar", "High Fructose Corn Syrup", "Artificial Flavors"],
                       flags: [flag("High Fructose Corn Syrup", 3, "Sweeteners", "Highly processed, metabolic risk"),
                               flag("Artificial Flavors", 1, "Additives", "Undisclosed chemical compounds")],
                       baseScore: 48, personalizedScore: 48, grade: "D",
                       alternatives: nil, scannedAt: hoursAgo(12)),
            ScanResult(id: "s5", barcode: "008523904948", productName: "Almond Breeze Unsweetened",
                       brand: "Blue Diamond", category: .food, imageUrl: nil,
                       ingredients: ["Filtered Water", "Almonds", "Calcium Carbonate", "Sea Salt"],
                       flags: [], baseScore: 78, personalizedScore: 78, grade: "B",
                       alternatives: nil, scannedAt: hoursAgo(24)),
            ScanResult(id: "s6", barcode: "000496340600", productName: "Organic Whole Milk",
                       brand: "Horizon Organic", category: .food, imageUrl: nil,
                       ingredients: ["Organic Grade A Whole Milk", "Vitamin D3"],
                       flags: [], baseScore: 88, personalizedScore: 88, grade: "A",
                       alternatives: nil, scannedAt: hoursAgo(36)),
            ScanResult(id: "s7", barcode: "001700008950", productName: "Tide Pods Laundry",
                       brand: "Tide", category: .cleaning, imageUrl: nil,
                       ingredients: ["Nonionic Surfactants", "Fragrances", "Optical Brighteners", "Enzymes"],
                       flags: [flag("Fragrances", 2, "Chemicals", "Undisclosed chemicals, potential allergens"),
                               flag("Optical Brighteners", 2, "Chemicals", "Synthetic chemicals accumulate in skin")],
                       baseScore: 35, personalizedScore: 35, grade: "D",
                       alternatives: nil, scannedAt: hoursAgo(48)),
        ]
    }

    // MARK: - History

    func addScan(_ scan: ScanResult) {
        // Remove any prior entry for same barcode, insert fresh at front
        var updated = history.filter { $0.barcode != scan.barcode }
        updated.insert(scan, at: 0)
        if updated.count > maxHistory {
            updated = Array(updated.prefix(maxHistory))
        }
        history = updated
        save()
    }

    func clearHistory() {
        history = []
        save()
    }

    func removeScan(_ scan: ScanResult) {
        history.removeAll { $0.id == scan.id }
        save()
    }

    // MARK: - Favorites

    func isFavorite(_ barcode: String) -> Bool {
        favorites.contains(barcode)
    }

    func toggleFavorite(_ scan: ScanResult) {
        if favorites.contains(scan.barcode) {
            favorites.remove(scan.barcode)
        } else {
            favorites.insert(scan.barcode)
            // Ensure it's stored in history so we can display it
            if !history.contains(where: { $0.barcode == scan.barcode }) {
                var updated = history
                updated.insert(scan, at: 0)
                history = updated
            }
        }
        save()
    }

    var favoriteScans: [ScanResult] {
        history.filter { favorites.contains($0.barcode) }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? decoder.decode([ScanResult].self, from: data) {
            history = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            favorites = Set(decoded)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
        if let data = try? JSONEncoder().encode(Array(favorites)) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
