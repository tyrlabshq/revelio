import SwiftUI
import Foundation
import GRDB

/// Persists scan history and favorites locally in an encrypted SQLite
/// database (GRDB + SQLCipher). See `LocalDatabase` for the schema.
///
/// The public API is identical to the previous UserDefaults-backed
/// implementation so call sites across the app don't need to change:
///   • `history` / `favorites` / `favoriteScans`
///   • `addScan`, `clearHistory`, `removeScan`
///   • `isFavorite`, `toggleFavorite`
@MainActor
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var history: [ScanResult] = []
    @Published private(set) var favorites: Set<String> = [] // barcode strings

    private let maxHistory = 500
    private let dbWriter: DatabaseWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        self.dbWriter = LocalDatabase.shared.queue

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        if CommandLine.arguments.contains("UI_TESTING") {
            loadSampleData()
        } else {
            migrateFromUserDefaultsIfNeeded()
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

    // MARK: - History (public API)

    func addScan(_ scan: ScanResult) {
        // In-memory: dedupe by barcode, insert at front, cap length.
        var updated = history.filter { $0.barcode != scan.barcode }
        updated.insert(scan, at: 0)
        if updated.count > maxHistory {
            updated = Array(updated.prefix(maxHistory))
        }
        history = updated

        // Persist: upsert the row and trim excess in a single write.
        do {
            let payload = try encoder.encode(scan)
            try dbWriter.write { db in
                try db.execute(sql: """
                    INSERT INTO scan_history
                        (id, barcode, product_name, brand, category, score, grade, image_url, scanned_at, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        barcode=excluded.barcode,
                        product_name=excluded.product_name,
                        brand=excluded.brand,
                        category=excluded.category,
                        score=excluded.score,
                        grade=excluded.grade,
                        image_url=excluded.image_url,
                        scanned_at=excluded.scanned_at,
                        payload=excluded.payload
                """, arguments: [
                    scan.id,
                    scan.barcode,
                    scan.productName,
                    scan.brand,
                    scan.category.rawValue,
                    scan.displayScore,
                    scan.grade,
                    scan.imageUrl,
                    scan.scannedAt,
                    payload
                ])
                // Dedup by barcode: delete older rows with same barcode but different id.
                try db.execute(sql: """
                    DELETE FROM scan_history
                    WHERE barcode = ? AND id <> ?
                """, arguments: [scan.barcode, scan.id])
                // Trim excess rows beyond maxHistory.
                try db.execute(sql: """
                    DELETE FROM scan_history
                    WHERE id NOT IN (
                        SELECT id FROM scan_history ORDER BY scanned_at DESC LIMIT ?
                    )
                """, arguments: [maxHistory])
            }
        } catch {
            NSLog("[HistoryManager] addScan persist failed: \(error)")
        }
    }

    func clearHistory() {
        history = []
        do {
            _ = try dbWriter.write { db in
                try db.execute(sql: "DELETE FROM scan_history")
            }
        } catch {
            NSLog("[HistoryManager] clearHistory failed: \(error)")
        }
    }

    func removeScan(_ scan: ScanResult) {
        history.removeAll { $0.id == scan.id }
        do {
            try dbWriter.write { db in
                try db.execute(sql: "DELETE FROM scan_history WHERE id = ?", arguments: [scan.id])
            }
        } catch {
            NSLog("[HistoryManager] removeScan failed: \(error)")
        }
    }

    // MARK: - Favorites (public API)

    func isFavorite(_ barcode: String) -> Bool {
        favorites.contains(barcode)
    }

    func toggleFavorite(_ scan: ScanResult) {
        if favorites.contains(scan.barcode) {
            favorites.remove(scan.barcode)
            do {
                try dbWriter.write { db in
                    try db.execute(sql: "DELETE FROM favorites WHERE barcode = ?", arguments: [scan.barcode])
                }
            } catch {
                NSLog("[HistoryManager] remove favorite failed: \(error)")
            }
        } else {
            favorites.insert(scan.barcode)
            if !history.contains(where: { $0.barcode == scan.barcode }) {
                // Ensure favorited scans are also in history so views can render them.
                var updated = history
                updated.insert(scan, at: 0)
                history = updated
                do {
                    let payload = try encoder.encode(scan)
                    try dbWriter.write { db in
                        try db.execute(sql: """
                            INSERT OR IGNORE INTO scan_history
                                (id, barcode, product_name, brand, category, score, grade, image_url, scanned_at, payload)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, arguments: [
                            scan.id, scan.barcode, scan.productName, scan.brand,
                            scan.category.rawValue, scan.displayScore, scan.grade,
                            scan.imageUrl, scan.scannedAt, payload
                        ])
                    }
                } catch {
                    NSLog("[HistoryManager] favorite history insert failed: \(error)")
                }
            }
            do {
                try dbWriter.write { db in
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO favorites (barcode, added_at) VALUES (?, ?)
                    """, arguments: [scan.barcode, Date()])
                }
            } catch {
                NSLog("[HistoryManager] favorite insert failed: \(error)")
            }
        }
    }

    var favoriteScans: [ScanResult] {
        history.filter { favorites.contains($0.barcode) }
    }

    // MARK: - Load from disk

    private func load() {
        do {
            let snapshot: (history: [ScanResult], favorites: Set<String>) = try dbWriter.read { db in
                var scans: [ScanResult] = []
                let rows = try Row.fetchAll(db, sql: """
                    SELECT payload FROM scan_history ORDER BY scanned_at DESC LIMIT ?
                """, arguments: [self.maxHistory])
                for row in rows {
                    if let data: Data = row["payload"] {
                        if let scan = try? self.decoder.decode(ScanResult.self, from: data) {
                            scans.append(scan)
                        }
                    }
                }
                let favRows = try String.fetchAll(db, sql: "SELECT barcode FROM favorites")
                return (scans, Set(favRows))
            }
            self.history = snapshot.history
            self.favorites = snapshot.favorites
        } catch {
            NSLog("[HistoryManager] load failed: \(error)")
        }
    }

    // MARK: - UserDefaults → SQLite migration

    private static let migratedFlagKey = "history_migrated_to_grdb_v1"
    private let legacyHistoryKey = "scan_history_v1"
    private let legacyFavoritesKey = "favorites_barcodes_v1"

    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.migratedFlagKey) { return }
        defer {
            defaults.set(true, forKey: Self.migratedFlagKey)
            // Purge legacy keys once migration is noted.
            defaults.removeObject(forKey: legacyHistoryKey)
            defaults.removeObject(forKey: legacyFavoritesKey)
        }

        let jsonDec = JSONDecoder()
        jsonDec.dateDecodingStrategy = .iso8601

        var legacyScans: [ScanResult] = []
        if let data = defaults.data(forKey: legacyHistoryKey),
           let decoded = try? jsonDec.decode([ScanResult].self, from: data) {
            legacyScans = decoded
        }
        var legacyFavs: [String] = []
        if let data = defaults.data(forKey: legacyFavoritesKey),
           let decoded = try? jsonDec.decode([String].self, from: data) {
            legacyFavs = decoded
        }
        guard !legacyScans.isEmpty || !legacyFavs.isEmpty else { return }

        do {
            try dbWriter.write { db in
                for scan in legacyScans {
                    let payload = try self.encoder.encode(scan)
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO scan_history
                            (id, barcode, product_name, brand, category, score, grade, image_url, scanned_at, payload)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        scan.id, scan.barcode, scan.productName, scan.brand,
                        scan.category.rawValue, scan.displayScore, scan.grade,
                        scan.imageUrl, scan.scannedAt, payload
                    ])
                }
                for barcode in legacyFavs {
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO favorites (barcode, added_at) VALUES (?, ?)
                    """, arguments: [barcode, Date()])
                }
            }
        } catch {
            NSLog("[HistoryManager] migration failed: \(error)")
        }
    }
}
