import Foundation
import SwiftUI
import GRDB

/// Persists pantry items locally in an encrypted SQLite database
/// (GRDB + SQLCipher). See `LocalDatabase` for the schema.
///
/// Products are deduplicated by barcode — rescanning updates the scan date.
/// The public API is preserved from the prior UserDefaults implementation:
///   • `items`
///   • `addItem(from:)`
///   • `removeItem(_:)`
///   • `removeItems(at:from:)`
@MainActor
class PantryManager: ObservableObject {
    static let shared = PantryManager()

    @Published private(set) var items: [PantryItem] = []

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
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        items = [
            PantryItem(id: "p1", barcode: "007017700576", productName: "Greek Yogurt Plain",
                       brand: "Chobani", score: 92, grade: "A", imageUrl: nil, quantity: 2,
                       addedAt: twoDaysAgo, ingredients: ["Cultured Nonfat Milk", "Live Cultures"],
                       flaggedIngredients: []),
            PantryItem(id: "p2", barcode: "004119600048", productName: "Extra Virgin Olive Oil",
                       brand: "California Olive Ranch", score: 95, grade: "A", imageUrl: nil, quantity: 1,
                       addedAt: twoDaysAgo, ingredients: ["Extra Virgin Olive Oil"],
                       flaggedIngredients: []),
            PantryItem(id: "p3", barcode: "003800017977", productName: "Cheez-It Original",
                       brand: "Sunshine Snacks", score: 55, grade: "C", imageUrl: nil, quantity: 1,
                       addedAt: twoDaysAgo, ingredients: ["Enriched Flour", "Soybean Oil", "TBHQ"],
                       flaggedIngredients: ["TBHQ", "Soybean Oil"]),
            PantryItem(id: "p4", barcode: "008523904948", productName: "Almond Breeze Unsweetened",
                       brand: "Blue Diamond", score: 78, grade: "B", imageUrl: nil, quantity: 1,
                       addedAt: twoDaysAgo, ingredients: ["Filtered Water", "Almonds", "Calcium Carbonate"],
                       flaggedIngredients: []),
            PantryItem(id: "p5", barcode: "001700008950", productName: "Tide Pods Laundry",
                       brand: "Tide", score: 35, grade: "D", imageUrl: nil, quantity: 1,
                       addedAt: twoDaysAgo, ingredients: ["Nonionic Surfactants", "Fragrances"],
                       flaggedIngredients: ["Fragrances", "Optical Brighteners"]),
        ]
    }

    // MARK: - Public API

    /// Recomputes the household score and pushes a fresh snapshot to the
    /// home-screen widget via the shared App Group. Safe to call frequently.
    func refreshWidget(streakDays: Int = 0, lastScanGrade: String? = nil) {
        guard !items.isEmpty else {
            WidgetDataStore.write(
                householdScore: 0,
                grade: "—",
                streakDays: streakDays,
                lastScanGrade: lastScanGrade,
                itemCount: 0
            )
            return
        }
        var totalWeight = 0.0
        var weightedSum = 0.0
        for item in items {
            let w: Double = item.grade == "F" ? 3 : item.grade == "D" ? 2 : 1
            weightedSum += Double(item.score) * w
            totalWeight += w
        }
        let score = Int(weightedSum / max(totalWeight, 1))
        let grade: String
        switch score {
        case 85...: grade = "A"
        case 70..<85: grade = "B"
        case 55..<70: grade = "C"
        case 40..<55: grade = "D"
        default: grade = "F"
        }
        WidgetDataStore.write(
            householdScore: score,
            grade: grade,
            streakDays: streakDays,
            lastScanGrade: lastScanGrade ?? items.first?.grade,
            itemCount: items.count
        )
    }

    /// Add or update a product from a successful scan.
    /// If the barcode already exists, updates the scan date and latest data.
    func addItem(from scan: ScanResult) {
        let flagged = scan.flags.map { $0.ingredient }
        let scanDate = Date()

        let updatedItem: PantryItem
        if let existingIndex = items.firstIndex(where: { $0.barcode == scan.barcode }) {
            let existing = items[existingIndex]
            updatedItem = PantryItem(
                id: existing.id,
                barcode: existing.barcode,
                productName: scan.productName,
                brand: scan.brand,
                score: scan.displayScore,
                grade: scan.grade,
                imageUrl: scan.imageUrl,
                quantity: existing.quantity,
                addedAt: scanDate,
                ingredients: scan.ingredients,
                flaggedIngredients: flagged
            )
            items[existingIndex] = updatedItem
        } else {
            updatedItem = PantryItem(
                id: UUID().uuidString,
                barcode: scan.barcode,
                productName: scan.productName,
                brand: scan.brand,
                score: scan.displayScore,
                grade: scan.grade,
                imageUrl: scan.imageUrl,
                quantity: 1,
                addedAt: scanDate,
                ingredients: scan.ingredients,
                flaggedIngredients: flagged
            )
            items.insert(updatedItem, at: 0)
        }

        persist(updatedItem, category: scan.category.rawValue)
        refreshWidget(lastScanGrade: scan.grade)
    }

    func removeItem(_ item: PantryItem) {
        items.removeAll { $0.id == item.id }
        do {
            try dbWriter.write { db in
                try db.execute(sql: "DELETE FROM pantry_items WHERE id = ?", arguments: [item.id])
            }
        } catch {
            NSLog("[PantryManager] removeItem failed: \(error)")
        }
        refreshWidget()
    }

    /// Used by List.onDelete — offsets map into the filtered list, not the full items array.
    func removeItems(at offsets: IndexSet, from filtered: [PantryItem]) {
        let ids = offsets.map { filtered[$0].id }
        items.removeAll { ids.contains($0.id) }
        do {
            try dbWriter.write { db in
                for id in ids {
                    try db.execute(sql: "DELETE FROM pantry_items WHERE id = ?", arguments: [id])
                }
            }
        } catch {
            NSLog("[PantryManager] removeItems failed: \(error)")
        }
        refreshWidget()
    }

    // MARK: - Persistence

    private func persist(_ item: PantryItem, category: String) {
        do {
            let payload = try encoder.encode(item)
            try dbWriter.write { db in
                try db.execute(sql: """
                    INSERT INTO pantry_items
                        (id, barcode, product_name, brand, category, score, grade, image_url, quantity, added_at, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(barcode) DO UPDATE SET
                        product_name=excluded.product_name,
                        brand=excluded.brand,
                        category=excluded.category,
                        score=excluded.score,
                        grade=excluded.grade,
                        image_url=excluded.image_url,
                        added_at=excluded.added_at,
                        payload=excluded.payload
                """, arguments: [
                    item.id, item.barcode, item.productName, item.brand, category,
                    item.score, item.grade, item.imageUrl, item.quantity, item.addedAt, payload
                ])
            }
        } catch {
            NSLog("[PantryManager] persist failed: \(error)")
        }
    }

    private func load() {
        do {
            let loaded: [PantryItem] = try dbWriter.read { db in
                var out: [PantryItem] = []
                let rows = try Row.fetchAll(db, sql: """
                    SELECT payload FROM pantry_items ORDER BY added_at DESC
                """)
                for row in rows {
                    if let data: Data = row["payload"],
                       let decoded = try? self.decoder.decode(PantryItem.self, from: data) {
                        out.append(decoded)
                    }
                }
                return out
            }
            self.items = loaded
        } catch {
            NSLog("[PantryManager] load failed: \(error)")
        }
    }

    // MARK: - UserDefaults → SQLite migration

    private static let migratedFlagKey = "pantry_migrated_to_grdb_v1"
    private let legacyStorageKey = "pantry_items_v1"

    private func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.migratedFlagKey) { return }
        defer {
            defaults.set(true, forKey: Self.migratedFlagKey)
            defaults.removeObject(forKey: legacyStorageKey)
        }

        let jsonDec = JSONDecoder()
        jsonDec.dateDecodingStrategy = .iso8601
        guard let data = defaults.data(forKey: legacyStorageKey),
              let legacy = try? jsonDec.decode([PantryItem].self, from: data),
              !legacy.isEmpty else { return }

        do {
            try dbWriter.write { db in
                for item in legacy {
                    let payload = try self.encoder.encode(item)
                    try db.execute(sql: """
                        INSERT OR IGNORE INTO pantry_items
                            (id, barcode, product_name, brand, category, score, grade, image_url, quantity, added_at, payload)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        item.id, item.barcode, item.productName, item.brand, "food",
                        item.score, item.grade, item.imageUrl, item.quantity, item.addedAt, payload
                    ])
                }
            }
        } catch {
            NSLog("[PantryManager] migration failed: \(error)")
        }
    }
}
