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
        load()
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
