import Foundation
import StoreKit
import SwiftUI

// ─── User Model ───────────────────────────────────────────────────────────────

struct AuthUser: Codable {
    let id: String
    let phone: String
    var tier: String
    var isPro: Bool { tier == "pro" }
    var dailyScansUsed: Int?
    var dailyScansLimit: Int?
}

// ─── AuthViewModel ────────────────────────────────────────────────────────────

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = true
    @Published var currentUser: AuthUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init() {
        // Stub user - always authenticated as free tier
        self.currentUser = AuthUser(
            id: "stub-user",
            phone: "",
            tier: "free",
            dailyScansUsed: 0,
            dailyScansLimit: 10
        )
        // Check existing entitlements on launch
        Task { await refreshUser() }
    }

    func loadToken() -> String? {
        // Returns nil so ProductDetailView doesn't crash
        return nil
    }

    func signOut() {
        // No-op: auth is disabled
    }

    private static let proProductIDs: Set<String> = [
        "com.revelio.pro.monthly",
        "com.revelio.pro.yearly"
    ]

    func refreshUser() async {
        var foundPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.proProductIDs.contains(transaction.productID) {
                foundPro = true
                break
            }
        }
        currentUser?.tier = foundPro ? "pro" : "free"
    }
}
