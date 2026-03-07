import Foundation
import Security
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

// ─── Keychain Keys ────────────────────────────────────────────────────────────

private enum KeychainKey {
    static let service = "com.revelio.app"
    static let jwtToken = "jwt_token"
}

// ─── Auth Errors ──────────────────────────────────────────────────────────────

enum AuthError: LocalizedError {
    case invalidPhone
    case invalidCode
    case networkError(String)
    case serverError(String)
    case tokenStoreFailed

    var errorDescription: String? {
        switch self {
        case .invalidPhone: return "Please enter a valid US phone number."
        case .invalidCode: return "Invalid code. Please check and try again."
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let msg): return msg
        case .tokenStoreFailed: return "Failed to store credentials. Please try again."
        }
    }
}

// ─── API Base ─────────────────────────────────────────────────────────────────

private let API_BASE = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:8430"

// ─── AuthViewModel ────────────────────────────────────────────────────────────

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: AuthUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    init() {
        // Auto-login if token is valid on launch
        Task { await autoLogin() }
    }

    // ─── Auto-login ───────────────────────────────────────────────────────────

    func autoLogin() async {
        guard let token = loadToken() else { return }
        guard !isTokenExpired(token) else {
            deleteToken()
            return
        }
        // Fetch /auth/me to confirm user still valid
        do {
            let user = try await fetchMe(token: token)
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            deleteToken()
        }
    }

    // ─── Request OTP ──────────────────────────────────────────────────────────

    func requestOTP(phone: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let normalized = normalizePhone(phone)
        guard !normalized.isEmpty else { throw AuthError.invalidPhone }

        #if DEBUG
        let mockEnabled = ProcessInfo.processInfo.environment["TWILIO_ACCOUNT_SID"] == nil
        if mockEnabled {
            print("[AuthViewModel/mock] OTP requested for \(normalized) — returning mock success")
            return
        }
        #endif

        let body: [String: String] = ["phone": normalized]
        let response = try await apiPost(path: "/auth/request-otp", body: body)

        guard let ok = response["ok"] as? Bool, ok else {
            let msg = response["error"] as? String ?? "Unknown error"
            throw AuthError.serverError(msg)
        }
    }

    // ─── Verify OTP ───────────────────────────────────────────────────────────

    func verifyOTP(phone: String, code: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let normalized = normalizePhone(phone)
        guard !normalized.isEmpty else { throw AuthError.invalidPhone }
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else { throw AuthError.invalidCode }

        let body: [String: String] = ["phone": normalized, "code": code]
        let response = try await apiPost(path: "/auth/verify-otp", body: body)

        guard let ok = response["ok"] as? Bool, ok,
              let token = response["token"] as? String else {
            let msg = response["error"] as? String ?? "Verification failed"
            throw AuthError.serverError(msg)
        }

        guard saveToken(token) else { throw AuthError.tokenStoreFailed }

        // Parse user from response
        if let userDict = response["user"] as? [String: Any] {
            let user = AuthUser(
                id: userDict["id"] as? String ?? "",
                phone: userDict["phone"] as? String ?? normalized,
                tier: userDict["tier"] as? String ?? "free"
            )
            self.currentUser = user
        }
        self.isAuthenticated = true
    }

    // ─── Sign Out ─────────────────────────────────────────────────────────────

    func signOut() {
        deleteToken()
        currentUser = nil
        isAuthenticated = false
    }

    // ─── Fetch /auth/me ───────────────────────────────────────────────────────

    func refreshUser() async {
        guard let token = loadToken() else { return }
        do {
            let user = try await fetchMe(token: token)
            self.currentUser = user
        } catch {
            print("[AuthViewModel] refreshUser error: \(error)")
        }
    }

    private func fetchMe(token: String) async throws -> AuthUser {
        guard let url = URL(string: "\(API_BASE)/auth/me") else {
            throw AuthError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.serverError("Failed to fetch user")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return AuthUser(
            id: json["userId"] as? String ?? "",
            phone: json["phone"] as? String ?? "",
            tier: json["tier"] as? String ?? "free",
            dailyScansUsed: json["dailyScansUsed"] as? Int,
            dailyScansLimit: json["dailyScansLimit"] as? Int
        )
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11 && digits.hasPrefix("1") { return "+\(digits)" }
        if phone.hasPrefix("+") && digits.count >= 10 { return phone }
        return ""
    }

    private func apiPost(path: String, body: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: "\(API_BASE)\(path)") else {
            throw AuthError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // ─── Keychain ─────────────────────────────────────────────────────────────

    func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: KeychainKey.jwtToken,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    @discardableResult
    private func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        // Delete old first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: KeychainKey.jwtToken,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: KeychainKey.jwtToken,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: KeychainKey.jwtToken,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func isTokenExpired(_ token: String) -> Bool {
        // Decode JWT payload (base64url, no signature verification needed here)
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return true }
        var payload = String(parts[1])
        // Pad base64
        while payload.count % 4 != 0 { payload += "=" }
        let base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }
        return Date(timeIntervalSince1970: exp) < Date()
    }
}
