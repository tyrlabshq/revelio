import Foundation
import StoreKit
import SwiftUI
import AuthenticationServices

// ─── User Model ───────────────────────────────────────────────────────────────

struct AuthUser: Codable {
    let id: String
    let phone: String?
    let email: String?
    let name: String?
    var tier: String
    var isPro: Bool { tier == "pro" }
    var dailyScansUsed: Int?
    var dailyScansLimit: Int?
    var authProvider: String? // "apple", "guest"
}

// ─── Apple Sign In Credential ──────────────────────────────────────────────────

struct AppleCredential {
    let userId: String
    let identityToken: String
    let authorizationCode: String
    let email: String?
    let fullName: PersonNameComponents?
}

// ─── Keychain Keys ────────────────────────────────────────────────────────────
//
// Access/refresh tokens and the cached user record live in the Keychain
// (kSecClassGenericPassword, AfterFirstUnlockThisDeviceOnly, non-iCloud).
// The KeychainStore scaffold handles the low-level SecItem plumbing; we just
// define the namespaced keys here.

enum AuthKeychainKey {
    static let accessToken = "revelio.auth.accessToken"
    static let refreshToken = "revelio.auth.refreshToken"
    static let userJSON = "revelio.auth.userJSON"
}

/// Legacy UserDefaults keys — only used for one-shot migration on launch.
private enum LegacyDefaultsKey {
    static let authToken = "auth_token"
    static let savedUser = "saved_user"
}

// ─── AuthViewModel ────────────────────────────────────────────────────────────

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: AuthUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private static let proProductIDs: Set<String> = [
        "com.revelio.pro.monthly",
        "com.revelio.pro.yearly"
    ]

    private let apiBaseURL = "https://api.revelio.app"

    init() {
        // One-shot migration: if a token still lives in UserDefaults from a
        // pre-Keychain build, move it to the Keychain and purge the plaintext
        // copies. Runs before we try to restore the session.
        Self.migrateLegacyUserDefaultsIfNeeded()

        if let savedUser = loadSavedUser() {
            self.currentUser = savedUser
            self.isAuthenticated = true
        } else {
            self.currentUser = nil
            self.isAuthenticated = false
        }

        // Check existing entitlements on launch
        Task { await refreshUser() }
    }

    // MARK: - Legacy migration

    /// Migrates any auth_token / saved_user values from UserDefaults into the
    /// Keychain, then removes the UserDefaults copies. Idempotent.
    private static func migrateLegacyUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard

        if let legacyToken = defaults.string(forKey: LegacyDefaultsKey.authToken),
           !legacyToken.isEmpty {
            if let data = legacyToken.data(using: .utf8) {
                KeychainStore.save(data, for: AuthKeychainKey.accessToken)
            }
            defaults.removeObject(forKey: LegacyDefaultsKey.authToken)
        }

        if let legacyUser = defaults.data(forKey: LegacyDefaultsKey.savedUser) {
            KeychainStore.save(legacyUser, for: AuthKeychainKey.userJSON)
            defaults.removeObject(forKey: LegacyDefaultsKey.savedUser)
        }
    }

    // MARK: - Sign In with Apple

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        isLoading = true
        errorMessage = nil

        switch result {
        case .success(let authorization):
            Task {
                await processAppleAuthorization(authorization)
            }
        case .failure(let error):
            isLoading = false
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    // User canceled - this is fine, just return to guest mode
                    break
                default:
                    errorMessage = "Sign in failed. Please try again."
                }
            } else {
                errorMessage = "An error occurred. Please try again."
            }
        }
    }

    private func processAppleAuthorization(_ authorization: ASAuthorization) async {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            isLoading = false
            errorMessage = "Invalid credentials"
            return
        }

        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = appleIDCredential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            isLoading = false
            errorMessage = "Failed to get authentication tokens"
            return
        }

        let credential = AppleCredential(
            userId: appleIDCredential.user,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            email: appleIDCredential.email,
            fullName: appleIDCredential.fullName
        )

        await authenticateWithBackend(credential: credential)
    }

    private func authenticateWithBackend(credential: AppleCredential) async {
        guard let url = URL(string: "\(apiBaseURL)/auth/apple") else {
            isLoading = false
            errorMessage = "Invalid API URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "appleUserId": credential.userId,
            "identityToken": credential.identityToken,
            "authorizationCode": credential.authorizationCode,
            "email": credential.email as Any,
            "fullName": credential.fullName?.givenName as Any
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                // Parse user from response
                let decoder = JSONDecoder()
                let user = try decoder.decode(AuthUser.self, from: data)

                await MainActor.run {
                    self.currentUser = user
                    self.isAuthenticated = true
                    self.saveUser(user)
                    self.isLoading = false
                }
            } else {
                throw AuthError.serverError("Server returned \(httpResponse.statusCode)")
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Authentication failed. Please try again."
            }
        }
    }

    // MARK: - Guest Mode

    func continueAsGuest() {
        let guestUser = AuthUser(
            id: "guest-\(UUID().uuidString)",
            phone: nil,
            email: nil,
            name: nil,
            tier: "free",
            dailyScansUsed: 0,
            dailyScansLimit: 10,
            authProvider: "guest"
        )

        currentUser = guestUser
        isAuthenticated = true
        saveUser(guestUser)
    }

    // MARK: - Session Management

    /// Access token retrieval — reads from Keychain only (no more UserDefaults).
    func loadToken() -> String? {
        guard let data = KeychainStore.load(AuthKeychainKey.accessToken) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Refresh token retrieval. Nil if we've never stored one (e.g. legacy
    /// sessions migrated from pre-refresh-token builds).
    func loadRefreshToken() -> String? {
        guard let data = KeychainStore.load(AuthKeychainKey.refreshToken) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Store a fresh access/refresh token pair (e.g. after verify-otp or refresh).
    func storeTokens(access: String, refresh: String?) {
        if let data = access.data(using: .utf8) {
            KeychainStore.save(data, for: AuthKeychainKey.accessToken)
        }
        if let refresh, let data = refresh.data(using: .utf8) {
            KeychainStore.save(data, for: AuthKeychainKey.refreshToken)
        }
    }

    func signOut() {
        currentUser = nil
        isAuthenticated = false
        KeychainStore.delete(AuthKeychainKey.accessToken)
        KeychainStore.delete(AuthKeychainKey.refreshToken)
        KeychainStore.delete(AuthKeychainKey.userJSON)

        // Belt and suspenders: make sure nothing is still sitting in legacy defaults.
        UserDefaults.standard.removeObject(forKey: LegacyDefaultsKey.authToken)
        UserDefaults.standard.removeObject(forKey: LegacyDefaultsKey.savedUser)

        // Note: Apple Sign In doesn't have a server-side sign out
        // The user remains signed in with Apple until they revoke access in Settings
    }

    private func saveUser(_ user: AuthUser) {
        guard let encoded = try? JSONEncoder().encode(user) else { return }
        KeychainStore.save(encoded, for: AuthKeychainKey.userJSON)
    }

    private func loadSavedUser() -> AuthUser? {
        guard let data = KeychainStore.load(AuthKeychainKey.userJSON),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return nil
        }
        return user
    }

    func refreshUser() async {
        var foundPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.proProductIDs.contains(transaction.productID) {
                foundPro = true
                break
            }
        }

        await MainActor.run {
            self.currentUser?.tier = foundPro ? "pro" : "free"
        }
    }
}

enum AuthError: Error {
    case invalidResponse
    case serverError(String)
    case networkError
}
