import Foundation
import SwiftUI

/// Persists pantry items locally using UserDefaults + Codable.
/// Products are deduplicated by barcode — rescanning updates the scan date.
@MainActor
class PantryManager: ObservableObject {
    static let shared = PantryManager()

    @Published private(set) var items: [PantryItem] = []

    private let storageKey = "pantry_items_v1"

    private init() {
        load()
    }

    // MARK: - Public API

    /// Add or update a product from a successful scan.
    /// If the barcode already exists, updates the scan date (and grade/score) instead of duplicating.
    func addItem(from scan: ScanResult) {
        let flagged = scan.flags.map { $0.ingredient }
        let scanDate = Date()

        if let existingIndex = items.firstIndex(where: { $0.barcode == scan.barcode }) {
            // Dedup: update existing entry with fresh scan date and latest data
            let existing = items[existingIndex]
            let updated = PantryItem(
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
            items[existingIndex] = updated
        } else {
            let newItem = PantryItem(
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
            items.insert(newItem, at: 0)
        }
        save()
    }

    func removeItem(_ item: PantryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Used by List.onDelete — offsets map into the filtered list, not the full items array.
    func removeItems(at offsets: IndexSet, from filtered: [PantryItem]) {
        let ids = Set(offsets.map { filtered[$0].id })
        items.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([PantryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
