import Combine
import Foundation

/// Consumes `NSUserActivity` events emitted when a user taps a
/// `https://revelio.app/p/<barcode>` link on the web and iOS hands the
/// activity to our app (Universal Links). Exposes `pendingScanBarcode`
/// so `ContentView` / `ScanView` can react — `.onReceive` it, then clear
/// it once the navigation completes so re-entry doesn't loop.
///
/// Not an `@MainActor` — `@Published` dispatches to main on its own and
/// the handler is created once at app launch as a singleton via
/// `UniversalLinkHandler.shared`.
final class UniversalLinkHandler: ObservableObject {
    static let shared = UniversalLinkHandler()

    /// Set when the OS hands us a deep link; observers clear it after
    /// navigating so the same link can be followed again later.
    @Published var pendingScanBarcode: String?

    private init() {}

    /// Apple's activity type for "user tapped a web link that resolved
    /// to this app via the AASA manifest". Mirrored in the Scene handler.
    static let browsingWebActivityType = "NSUserActivityTypeBrowsingWeb"

    /// Parse an incoming activity. Accepts:
    ///   - `activityType == NSUserActivityTypeBrowsingWeb`
    ///   - `webpageURL?.host == "revelio.app"` (www subdomain also OK)
    ///   - path shape `/p/<barcode>` where <barcode> is 6–14 digits
    ///
    /// Rejects everything else — we never want a crafted URL to push
    /// arbitrary strings into the scan history / result screen.
    func handle(_ activity: NSUserActivity) {
        guard activity.activityType == Self.browsingWebActivityType,
              let url = activity.webpageURL else { return }
        handle(url: url)
    }

    /// Entry point for `onOpenURL` (custom-scheme `revelio://scan/<barcode>`)
    /// and for the universal-link path above. Centralised so both surfaces
    /// share the same validation.
    func handle(url: URL) {
        let host = url.host?.lowercased()
        let scheme = url.scheme?.lowercased()

        // Custom scheme: revelio://scan/<barcode>
        if scheme == "revelio", host == "scan" {
            let comps = url.pathComponents.filter { $0 != "/" }
            if let first = comps.first, Self.isValidBarcode(first) {
                pendingScanBarcode = first
            }
            return
        }

        // Universal link: https://revelio.app/p/<barcode>
        guard scheme == "https" else { return }
        guard let host, host == "revelio.app" || host == "www.revelio.app" else { return }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2, comps[0] == "p" else { return }
        let barcode = comps[1]
        guard Self.isValidBarcode(barcode) else { return }
        pendingScanBarcode = barcode
    }

    /// GTIN digits only — 6 to 14. Rejects path traversal / XSS payloads.
    private static func isValidBarcode(_ s: String) -> Bool {
        guard (6...14).contains(s.count) else { return false }
        return s.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
