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
    @Published var showAutoManualEntry = false
    @Published var failedScanCount = 0

    private var lastBarcode = ""
    private var lastScanTime = Date.distantPast

    private let successFeedback = UINotificationFeedbackGenerator()
    private let errorFeedback = UINotificationFeedbackGenerator()

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
        Task { await fetchProduct(barcode: code) }
    }

    func searchByName(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state = .loading
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "http://10.0.0.244:8430/search?q=\(encoded)") else {
            state = .error("Invalid search query")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                state = .error("No response from server")
                return
            }
            if http.statusCode == 404 {
                errorFeedback.notificationOccurred(.error)
                state = .error("No products found matching \"\(query)\".")
                return
            }
            guard http.statusCode == 200 else {
                errorFeedback.notificationOccurred(.error)
                state = .error("Server error (\(http.statusCode)). Try again.")
                return
            }
            let scan = try JSONDecoder().decode(ScanResult.self, from: data)
            successFeedback.notificationOccurred(.success)
            HistoryManager.shared.addScan(scan)
            state = .result(scan)
        } catch {
            errorFeedback.notificationOccurred(.error)
            state = .error("Search failed. Check your connection.")
        }
    }

    private func fetchProduct(barcode: String) async {
        state = .loading
        guard let url = URL(string: "http://10.0.0.244:8430/scan/\(barcode)") else {
            recordFailure()
            state = .error("Invalid barcode")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                recordFailure()
                state = .error("No response from server")
                return
            }
            if http.statusCode == 404 {
                recordFailure()
                state = .error("Product not found in our database yet. Try another item!")
                return
            }
            guard http.statusCode == 200 else {
                recordFailure()
                state = .error("Server error (\(http.statusCode)). Try again.")
                return
            }
            let scan = try JSONDecoder().decode(ScanResult.self, from: data)
            failedScanCount = 0
            showAutoManualEntry = false
            successFeedback.notificationOccurred(.success)
            HistoryManager.shared.addScan(scan)
            state = .result(scan)
        } catch {
            recordFailure()
            state = .error("Couldn't analyze this product. Check your connection.")
        }
    }

    private func recordFailure() {
        errorFeedback.notificationOccurred(.error)
        failedScanCount += 1
        if failedScanCount >= 3 {
            showAutoManualEntry = true
        }
    }

    func resetScan() {
        lastBarcode = ""
        failedScanCount = 0
        showAutoManualEntry = false
        state = .scanning
    }

    func toggleTorch() {
        torchOn.toggle()
        applyTorch(torchOn)
    }

    func turnOffTorch() {
        guard torchOn else { return }
        torchOn = false
        applyTorch(false)
    }

    private func applyTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}
