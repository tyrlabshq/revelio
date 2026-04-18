import AppIntents
import Foundation

// ─── Lookup Barcode Intent ────────────────────────────────────────────────────
//
// Siri/Shortcuts pass a barcode string; we call GET /scan/:barcode and
// return a spoken grade. Keeps networking inline (no dependency on
// ScanViewModel) so the intent works without the app being in the
// foreground.

@available(iOS 16.0, *)
struct LookupBarcodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Look up a barcode"
    static var description = IntentDescription(
        "Returns the Revelio grade for a barcode."
    )

    @Parameter(title: "Barcode")
    var barcode: String

    static var parameterSummary: some ParameterSummary {
        Summary("Look up barcode \(\.$barcode) with Revelio")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Please provide a barcode.")
        }

        let apiBase = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://api.revelio.app"
        guard let url = URL(string: "\(apiBase)/scan/\(trimmed)") else {
            return .result(dialog: "That barcode looks invalid.")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                return .result(dialog: "I couldn't reach Revelio. Try again in a moment.")
            }
            if http.statusCode == 404 {
                return .result(dialog: "Revelio doesn't have that product yet.")
            }
            guard http.statusCode == 200 else {
                return .result(dialog: "Revelio had trouble looking that up.")
            }

            // Decode loosely — backend may use snake_case or camelCase depending on route.
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let grade = (json?["grade"] as? String) ?? "?"
            let brand = (json?["brand"] as? String) ?? ""
            let productName = (json?["product_name"] as? String) ?? (json?["productName"] as? String) ?? ""
            let name = !brand.isEmpty ? brand : (!productName.isEmpty ? productName : "that product")

            let dialog = "Revelio says that's a grade \(grade): \(name)"
            return .result(dialog: IntentDialog(stringLiteral: dialog))
        } catch {
            return .result(dialog: "Network error — try again shortly.")
        }
    }
}
