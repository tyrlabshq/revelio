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
        guard let url = URL(string: "http://10.0.0.244:8430/scan/\(barcode)") else {
            state = .error("Invalid barcode")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                state = .error("No response from server")
                return
            }
            if http.statusCode == 404 {
                state = .error("Product not found in our database yet. Try another item!")
                return
            }
            guard http.statusCode == 200 else {
                state = .error("Server error (\(http.statusCode)). Try again.")
                return
            }
            let scan = try JSONDecoder().decode(ScanResult.self, from: data)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            state = .result(scan)
        } catch {
            state = .error("Couldn't analyze this product. Check your connection.")
        }
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
