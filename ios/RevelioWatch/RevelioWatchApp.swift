import SwiftUI

/// watchOS companion entry point. The Watch app is a "glance + handoff"
/// surface — it does not scan barcodes (the Watch camera isn't suitable)
/// and does not talk to the backend directly. All data comes from the
/// shared App Group (`group.app.revelio`) written by the iPhone app, and
/// the Quick Scan tab hands off to the iPhone via `revelio://scan`.
@main
struct RevelioWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
