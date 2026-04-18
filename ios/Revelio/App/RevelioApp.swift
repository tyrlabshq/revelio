import StoreKit
import SwiftUI

@main
struct RevelioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authViewModel = AuthViewModel()
    // Global universal-link handler. Lives at app scope so late-arriving
    // `onContinueUserActivity` events (e.g. the launching link that brought
    // the app from a cold start) are captured before any view mounts.
    @StateObject private var universalLinks = UniversalLinkHandler.shared

    private var transactionListener: Task<Void, Never>?

    init() {
        let auth = _authViewModel
        transactionListener = Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await auth.wrappedValue.refreshUser()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authViewModel)
                .environmentObject(universalLinks)
                // Universal Links: fired when iOS resolves a tapped
                // https://revelio.app/p/<barcode> link to our bundle via the
                // AASA manifest. Delegated to UniversalLinkHandler so URL
                // parsing and validation live in one place.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    universalLinks.handle(activity)
                }
                // Custom-scheme fallback: revelio://scan/<barcode>. Used by
                // the SSR page's inline JS when the universal-link handoff
                // doesn't fire (e.g. in-app browsers that strip the AASA hint).
                .onOpenURL { url in
                    universalLinks.handle(url: url)
                }
        }
    }
}
