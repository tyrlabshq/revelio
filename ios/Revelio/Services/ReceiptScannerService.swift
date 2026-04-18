import Foundation
import UIKit
import Vision

/// A receipt line extracted by OCR. Intentionally minimal — fuzzy DB match
/// happens server-side in `POST /receipts/score`.
struct ReceiptLine: Identifiable, Hashable {
    let id = UUID()
    let lineText: String
}

enum ReceiptScanError: Error, LocalizedError {
    case invalidImage
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Couldn't read that photo. Try again in better light."
        case .visionFailed(let msg):
            return "OCR failed: \(msg)"
        }
    }
}

/// Wraps `VNRecognizeTextRequest` over a receipt image and returns a
/// filtered list of plausible product-name lines.
struct ReceiptScannerService {

    /// Max / min line length filter. Receipts include totals, store headers,
    /// phone numbers, etc. — we only want product-name-shaped strings.
    static let minLineLength = 3
    static let maxLineLength = 60

    /// Extract lines from a receipt image.
    /// - Parameter image: a UIImage captured from camera or photo library.
    /// - Returns: filtered `ReceiptLine` array (de-duped, trimmed).
    static func extractLines(from image: UIImage) async throws -> [ReceiptLine] {
        guard let cgImage = image.cgImage else {
            throw ReceiptScanError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    continuation.resume(throwing: ReceiptScanError.visionFailed(err.localizedDescription))
                    return
                }

                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let raw: [String] = observations.compactMap { obs in
                    obs.topCandidates(1).first?.string
                }

                let filtered = filterProductLines(raw)
                let lines = filtered.map { ReceiptLine(lineText: $0) }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ReceiptScanError.visionFailed(error.localizedDescription))
            }
        }
    }

    /// Heuristic filter: keep lines that look like product names, drop
    /// totals, dates, store headers, phone numbers, etc.
    static func filterProductLines(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        for original in raw {
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= minLineLength, trimmed.count <= maxLineLength else { continue }

            // Mostly letters/spaces: reject lines where digits dominate
            // (phone numbers, prices, dates) and lines that are pure punctuation.
            let letters = trimmed.unicodeScalars.filter {
                CharacterSet.letters.contains($0) || $0 == " " || $0 == "'" || $0 == "-" || $0 == "&"
            }
            guard letters.count >= Int(Double(trimmed.count) * 0.6) else { continue }

            // Drop obvious non-product lines
            let lower = trimmed.lowercased()
            let skipTokens = [
                "total", "subtotal", "tax", "cash", "change", "visa",
                "mastercard", "debit", "credit", "thank you", "receipt",
                "balance", "tender", "approved", "cashier", "register",
                "store #", "tel:", "phone", "www.", "http",
            ]
            if skipTokens.contains(where: { lower.contains($0) }) { continue }

            // De-dupe by lowered form
            if seen.insert(lower).inserted {
                out.append(trimmed)
            }
        }
        return out
    }
}
