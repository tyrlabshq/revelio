import Foundation
import UIKit
import Vision

/// On-device OCR for product ingredient panels using Apple Vision.
///
/// Wraps `VNRecognizeTextRequest` to extract the ingredient list from a photo of
/// a label. Intended as a fallback when a barcode scan yields no match in any of
/// the remote product databases (OFF/OBF/OPF).
///
/// No network traffic — all processing happens locally, preserving privacy.
enum IngredientOCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed(Error)
    case noTextFound
    case ingredientsHeaderMissing

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Couldn't read that photo."
        case .recognitionFailed(let err): return "OCR failed: \(err.localizedDescription)"
        case .noTextFound: return "No text detected on the label."
        case .ingredientsHeaderMissing:
            return "Couldn't find an 'Ingredients' section. Zoom in and retake."
        }
    }
}

final class IngredientOCRService {
    static let shared = IngredientOCRService()

    /// Extract ingredient tokens from a label image.
    ///
    /// Heuristic:
    ///   1. Run Vision's accurate text recognizer with language correction.
    ///   2. Find the first line that begins with "INGREDIENTS" (case-insensitive,
    ///      optional colon), then consume lines until we hit the next ALL-CAPS
    ///      section heading (e.g. "NUTRITION FACTS", "DISTRIBUTED BY").
    ///   3. Split the captured block on commas and semicolons, strip
    ///      parenthetical qualifiers, trim, lowercase, de-duplicate.
    func extractIngredients(from image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw IngredientOCRError.invalidImage
        }

        let lines: [String] = try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    cont.resume(throwing: IngredientOCRError.recognitionFailed(err))
                    return
                }
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: [])
                    return
                }
                let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: texts)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: IngredientOCRError.recognitionFailed(error))
            }
        }

        guard !lines.isEmpty else { throw IngredientOCRError.noTextFound }

        let block = Self.extractIngredientsBlock(from: lines)
        guard !block.isEmpty else { throw IngredientOCRError.ingredientsHeaderMissing }

        return Self.tokenize(block)
    }

    // MARK: - Parsing helpers (internal for testability)

    /// Given OCR line output, return the raw ingredients block as a single
    /// joined string. Returns empty string if no "Ingredients" header is found.
    static func extractIngredientsBlock(from lines: [String]) -> String {
        // Find the index of the first line containing the ingredients header.
        let headerRegex = #/(?i)ingredients\s*:?/#
        guard let startIdx = lines.firstIndex(where: { line in
            (try? headerRegex.firstMatch(in: line)) != nil
        }) else {
            return ""
        }

        // Strip the header token itself from the first line so we keep trailing content.
        var captured: [String] = []
        let firstLine = lines[startIdx]
        if let match = try? headerRegex.firstMatch(in: firstLine) {
            let after = firstLine[match.range.upperBound...]
            let trimmed = after.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { captured.append(String(trimmed)) }
        }

        // Consume subsequent lines until we hit another ALL-CAPS heading.
        for i in (startIdx + 1)..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if Self.looksLikeSectionHeading(line) { break }
            captured.append(line)
        }

        return captured.joined(separator: " ")
    }

    /// A heading is "ALL CAPS-ish": at least 4 characters, no lowercase, and
    /// not starting with a parenthetical or digit. This reliably catches
    /// "NUTRITION FACTS", "DISTRIBUTED BY", "CONTAINS:" etc.
    static func looksLikeSectionHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 4 else { return false }
        // Must contain at least one letter.
        let letters = trimmed.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        // No lowercase letters.
        if letters.contains(where: { $0.isLowercase }) { return false }
        // Avoid flagging things that are just an acronym inside an ingredient list,
        // by requiring at least one space OR a trailing colon.
        let hasSpace = trimmed.contains(" ")
        let hasColon = trimmed.hasSuffix(":")
        return hasSpace || hasColon
    }

    /// Tokenize the ingredient block into individual ingredient strings.
    static func tokenize(_ block: String) -> [String] {
        // Strip parentheticals: "sugar (beet)" -> "sugar "
        let withoutParens = block.replacingOccurrences(
            of: #"\([^)]*\)"#, with: " ", options: .regularExpression
        )
        // Also strip bracketed annotations.
        let withoutBrackets = withoutParens.replacingOccurrences(
            of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression
        )
        // Remove percentage annotations like "15%".
        let withoutPercents = withoutBrackets.replacingOccurrences(
            of: #"\d+\s*%"#, with: " ", options: .regularExpression
        )
        // Split on commas and semicolons.
        let raw = withoutPercents.split(whereSeparator: { $0 == "," || $0 == ";" })

        var seen = Set<String>()
        var out: [String] = []
        for piece in raw {
            var s = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            // Drop leading bullet characters.
            while let first = s.first, ["-", "*", "•", "·"].contains(first) {
                s.removeFirst()
                s = s.trimmingCharacters(in: .whitespaces)
            }
            // Drop trailing punctuation.
            while let last = s.last, [".", ":"].contains(last) {
                s.removeLast()
            }
            let lower = s.lowercased()
            guard lower.count > 1 else { continue }
            if seen.insert(lower).inserted {
                out.append(lower)
            }
        }
        return out
    }
}
