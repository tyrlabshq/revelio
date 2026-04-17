import Foundation

// MARK: - AuthAPI
//
// Thin typed wrapper around NetworkClient for the auth surface:
//
//   POST   /auth/refresh       — manual refresh (NetworkClient also calls
//                                 this automatically on 401; this entry
//                                 point is here for completeness / future
//                                 "refresh on app foreground" use).
//   POST   /auth/logout        — best-effort server-side session kill.
//   DELETE /auth/account       — hard-delete the user (GDPR).
//   GET    /auth/export        — return a JSON dump of everything the user
//                                 owns (GDPR).
//
// The caller is expected to have already stored an access token in the
// Keychain; NetworkClient attaches the Bearer header automatically.

struct AuthAPI {
    private let client: NetworkClient

    init(client: NetworkClient = .shared) {
        self.client = client
    }

    // MARK: - Refresh
    //
    // Backend contract (from the plan + parallel backend agent):
    //   POST /auth/refresh
    //   body: { "refreshToken": "<30-day refresh>" }
    //   200:  { "token": "<new 15-min access>",
    //           "refreshToken": "<new 30-day refresh>" }   ← rotated
    //
    // On success we store BOTH new tokens via AuthTokenProvider.

    struct RefreshResponse: Decodable {
        let token: String
        let refreshToken: String
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String
    }

    @discardableResult
    func refresh() async throws -> RefreshResponse {
        guard let refresh = AuthTokenProvider.refreshToken(), !refresh.isEmpty else {
            throw NetworkError.unauthorized
        }
        let resp: RefreshResponse = try await client.request(
            "/auth/refresh",
            method: "POST",
            body: RefreshBody(refreshToken: refresh)
        )
        AuthTokenProvider.storeTokens(access: resp.token, refresh: resp.refreshToken)
        return resp
    }

    // MARK: - Logout

    /// Best-effort server logout. Swallows network errors — we always clear
    /// local state afterwards regardless.
    func logout() async {
        _ = try? await client.requestData("/auth/logout", method: "POST", body: nil)
    }

    // MARK: - Delete account (GDPR)

    /// DELETE /auth/account. Backend responds 204 on success.
    /// Throws on any non-2xx; the caller is responsible for clearing local
    /// state only after this returns successfully.
    func deleteAccount() async throws {
        _ = try await client.requestData("/auth/account", method: "DELETE", body: nil)
    }

    // MARK: - Export (GDPR)

    /// GET /auth/export. Returns the raw JSON bytes so the caller can dump
    /// them to a temp file and hand the URL to a share sheet.
    func exportData() async throws -> Data {
        try await client.requestData("/auth/export", method: "GET", body: nil)
    }
}

