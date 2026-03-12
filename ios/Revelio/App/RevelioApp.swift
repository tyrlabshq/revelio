import StoreKit
import SwiftUI

@main
struct RevelioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authViewModel = AuthViewModel()

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
        }
    }
}
