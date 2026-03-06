import SwiftUI
import AVFoundation

enum ScanState: Equatable {
    case idle, scanning, loading, result(ScanResult), error(String)
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.scanning, .scanning), (.loading, .loading): return true
        case (.error(let a), .error(let b)): return a == b
        case (.result(let a), .result(let b)): return a.id == b.id
        default: return false
        }
    }
}

@MainActor
class ScanViewModel: ObservableObject {
    @Published var state: ScanState = .scanning
    @Published var torchOn = false
    private var lastBarcode = ""
    private var lastScanTime = Date.distantPast

    var stateTag: String {
        switch state {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .loading: return "loading"
        case .result: return "result"
        case .error: return "error"
        }
    }

    func handleBarcode(_ code: String) {
        guard code != lastBarcode || Date().timeIntervalSince(lastScanTime) > 2 else { return }
        lastBarcode = code; lastScanTime = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await fetchProduct(barcode: code) }
    }

    private func fetchProduct(barcode: String) async {
        state = .loading
        try? await Task.sleep(for: .seconds(1.2))

        // Mock result for dev
        let scan = ScanResult(
            id: UUID().uuidString, barcode: barcode,
            productName: "Hellmann's Real Mayonnaise", brand: "Hellmann's",
            category: .food, imageUrl: nil,
            ingredients: ["water", "canola oil", "eggs", "distilled white vinegar", "salt", "sugar", "lemon juice concentrate", "calcium disodium edta"],
            flags: [
                IngredientFlag(id: "1", ingredient: "canola oil", severity: 2, category: "SEED OIL", reason: "High in omega-6 fatty acids, oxidizes during high-heat processing", citationTitle: "Dietary Fats and Cardiovascular Disease", citationUrl: "https://doi.org/10.1161/CIR.0000000000000510", citationYear: 2017, priorities: ["seed_oils"]),
                IngredientFlag(id: "2", ingredient: "calcium disodium edta", severity: 1, category: "PRESERVATIVE", reason: "Chelating agent; may deplete essential minerals", citationTitle: "FDA Food Additive Status List", citationUrl: "https://www.fda.gov/food/food-additives-petitions/food-additive-status-list", citationYear: 2023, priorities: ["artificial_additives"])
            ],
            baseScore: 65, personalizedScore: 65, grade: "B",
            alternatives: nil, scannedAt: Date()
        )
        state = .result(scan)
    }

    func resetScan() { lastBarcode = ""; state = .scanning }

    func toggleTorch() {
        torchOn.toggle()
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = torchOn ? .on : .off
        device.unlockForConfiguration()
    }
}
