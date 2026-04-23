import SwiftUI

/// App Clip entry point. Intentionally minimal — App Clips are capped at
/// 10 MB and should do one thing well. Our one thing is: resolve an
/// inbound `https://revelio.app/p/<barcode>` link (see AASA in
/// `backend/src/routes/well-known.ts`) into a score card without the
/// user ever installing the full app or signing in.
///
/// The main app lives in `ios/Revelio/` and shares no code with the clip
/// at runtime — we deliberately copy the few models we need (see
/// `AppClipContentView.swift`) so the clip bundle stays small.
@main
struct RevelioAppClipApp: App {
    @StateObject private var state = AppClipState()

    var body: some Scene {
        WindowGroup {
            AppClipContentView()
                .environmentObject(state)
                // App Clips receive their inbound link as an NSUserActivity
                // of type NSUserActivityTypeBrowsingWeb. We hand it off to
                // AppClipContentView which does the URL → barcode parsing.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    state.handle(activity: activity)
                }
        }
    }
}

/// Lightweight state holder for the clip — analogous to the main app's
/// `AppState` but scoped to a single scan session.
@MainActor
final class AppClipState: ObservableObject {
    @Published var barcode: String?

    /// Parse an NSUserActivity emitted by the App Clip launcher. We only
    /// accept `https://revelio.app/p/<barcode>` with a 6–14 digit GTIN —
    /// anything else is dropped silently so a crafted URL can't push
    /// arbitrary strings through the clip.
    func handle(activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return }
        let host = url.host?.lowercased()
        guard host == "revelio.app" || host == "www.revelio.app" else { return }
        let comps = url.pathComponents.filter { $0 != "/" }
        guard comps.count >= 2, comps[0] == "p" else { return }
        let candidate = comps[1]
        guard (6...14).contains(candidate.count),
              candidate.allSatisfy({ $0.isASCII && $0.isNumber }) else { return }
        barcode = candidate
    }
}
