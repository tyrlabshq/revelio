import AppIntents
import SwiftUI

// ─── Scan Product Intent ──────────────────────────────────────────────────────
//
// Exposes "Scan a product with Revelio" to Siri, Shortcuts, and Spotlight.
// Conforms to OpenIntent so Siri opens the app and returns the user to the
// scan surface. The actual camera UI lives in ScanView; we only need to open
// the app — SwiftUI's default root lands on the Scan tab.

@available(iOS 16.0, *)
struct ScanProductIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a product with Revelio"
    static var description = IntentDescription(
        "Opens Revelio to the scanner so you can scan a barcode."
    )

    // Ensures Siri foregrounds the app before / after performing the intent.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app launches directly into ScanView (the first tab), so simply
        // opening is enough. If in the future we add a router, post a
        // notification here to deep-link into the scanner.
        NotificationCenter.default.post(name: .revelioOpenScanner, object: nil)
        return .result()
    }
}

// ─── Shortcuts Provider ───────────────────────────────────────────────────────

@available(iOS 16.0, *)
struct RevelioShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanProductIntent(),
            phrases: [
                "Scan a product with \(.applicationName)",
                "Open \(.applicationName) scanner",
                "Scan with \(.applicationName)"
            ],
            shortTitle: "Scan Product",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: LookupBarcodeIntent(),
            phrases: [
                "Look up a barcode in \(.applicationName)",
                "Check a barcode with \(.applicationName)"
            ],
            shortTitle: "Look Up Barcode",
            systemImageName: "magnifyingglass"
        )
    }
}

// ─── Deep-link Notification ───────────────────────────────────────────────────

extension Notification.Name {
    static let revelioOpenScanner = Notification.Name("revelio.openScanner")
}
