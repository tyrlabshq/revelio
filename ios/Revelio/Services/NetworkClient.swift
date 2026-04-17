import Foundation
import CryptoKit

// MARK: - NetworkError

enum NetworkError: LocalizedError {
    case invalidURL
    case insecureScheme          // http:// in a release build
    case invalidResponse
    case unauthorized            // 401 after a failed refresh
    case http(Int, Data?)        // any non-2xx (or any 4xx/5xx we don't special-case)
    case decoding(Error)
    case encoding(Error)
    case pinningFailed
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Invalid URL"
        case .insecureScheme:    return "Insecure connections are not permitted"
        case .invalidResponse:   return "Malformed server response"
        case .unauthorized:      return "Your session has expired. Please sign in again."
        case .http(let code, _): return "Request failed (HTTP \(code))"
        case .decoding:          return "Could not decode server response"
        case .encoding:          return "Could not encode request body"
        case .pinningFailed:     return "Could not verify server certificate"
        case .refreshFailed:     return "Could not refresh your session"
        }
    }
}

// MARK: - NetworkClient
//
// Thin wrapper around a URLSession with:
//   - HTTPS enforcement in release builds (any http:// URL is rejected up front)
//   - SPKI SHA-256 certificate pinning against a production leaf (release only)
//   - Automatic `Authorization: Bearer <access>` header from Keychain
//   - Automatic one-shot retry on 401 after calling POST /auth/refresh
//
// We intentionally don't subclass URLSession (Apple does not support that
// cleanly; `URLSession` is a class cluster). Instead we own a URLSession with
// a custom URLSessionDelegate for the pinning hook.

final class NetworkClient: NSObject, @unchecked Sendable {

    // Swap this out with the real production leaf's SPKI SHA-256 (base64)
    // before App Store submission. Generate with:
    //   openssl s_client -connect api.revelio.app:443 </dev/null | \
    //     openssl x509 -pubkey -noout | \
    //     openssl pkey -pubin -outform der | \
    //     openssl dgst -sha256 -binary | base64
    private static let PINNED_SPKI_SHA256 = "REPLACE_WITH_PRODUCTION_LEAF"

    static let shared = NetworkClient()

    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Single-flight lock around refresh so five concurrent 401s don't fire
    /// five refresh calls.
    private let refreshQueue = DispatchQueue(label: "app.revelio.network.refresh")
    private var inflightRefresh: Task<String, Error>?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(baseURL: URL = URL(string: "https://api.revelio.app")!) {
        self.baseURL = baseURL

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        super.init()
    }

    // MARK: - Public API

    /// Generic typed request.
    /// - `endpoint` may be a full URL or a path (e.g. `/auth/refresh`).
    /// - `body` is any Encodable; pass nil for GET/DELETE.
    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await requestData(endpoint, method: method, body: body)
        if T.self == EmptyResponse.self {
            // Callers using EmptyResponse only care about success/failure.
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    /// Raw data request (used by the export flow which just wants the bytes).
    @discardableResult
    func requestData(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        let url = try resolve(endpoint)
        try enforceHTTPS(url)

        let request = try buildRequest(
            url: url,
            method: method,
            body: body,
            extraHeaders: extraHeaders,
            accessToken: AuthTokenProvider.accessToken()
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        // Happy path
        if (200..<300).contains(http.statusCode) {
            return data
        }

        // 401 → refresh + retry once
        if http.statusCode == 401 {
            do {
                let newAccess = try await refreshAccessToken()
                let retry = try buildRequest(
                    url: url,
                    method: method,
                    body: body,
                    extraHeaders: extraHeaders,
                    accessToken: newAccess
                )
                let (retryData, retryResponse) = try await session.data(for: retry)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                if (200..<300).contains(retryHTTP.statusCode) {
                    return retryData
                }
                if retryHTTP.statusCode == 401 {
                    throw NetworkError.unauthorized
                }
                throw NetworkError.http(retryHTTP.statusCode, retryData)
            } catch let err as NetworkError {
                throw err
            } catch {
                throw NetworkError.refreshFailed
            }
        }

        throw NetworkError.http(http.statusCode, data)
    }

    // MARK: - Request construction

    private func resolve(_ endpoint: String) throws -> URL {
        if let full = URL(string: endpoint), full.scheme != nil {
            return full
        }
        // Treat as a path relative to baseURL.
        let trimmed = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            throw NetworkError.invalidURL
        }
        return url
    }

    private func enforceHTTPS(_ url: URL) throws {
        #if DEBUG
        // Debug builds may hit http://localhost / 127.0.0.1 only.
        if url.scheme?.lowercased() == "http" {
            let host = url.host?.lowercased() ?? ""
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if !isLoopback {
                throw NetworkError.insecureScheme
            }
        }
        #else
        if url.scheme?.lowercased() != "https" {
            throw NetworkError.insecureScheme
        }
        #endif
    }

    private func buildRequest(
        url: URL,
        method: String,
        body: Encodable?,
        extraHeaders: [String: String],
        accessToken: String?
    ) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw NetworkError.encoding(error)
            }
        }

        if let token = accessToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        return req
    }

    // MARK: - Refresh (single-flight)

    private func refreshAccessToken() async throws -> String {
        // Coalesce concurrent refreshes.
        let task: Task<String, Error> = refreshQueue.sync {
            if let existing = inflightRefresh {
                return existing
            }
            let new = Task<String, Error> { [weak self] in
                guard let self else { throw NetworkError.refreshFailed }
                return try await self.performRefresh()
            }
            self.inflightRefresh = new
            return new
        }

        do {
            let token = try await task.value
            refreshQueue.sync { self.inflightRefresh = nil }
            return token
        } catch {
            refreshQueue.sync { self.inflightRefresh = nil }
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard let refresh = AuthTokenProvider.refreshToken(), !refresh.isEmpty else {
            throw NetworkError.unauthorized
        }

        let url = try resolve("/auth/refresh")
        try enforceHTTPS(url)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = RefreshRequest(refreshToken: refresh)
        req.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // Refresh token is dead — nuke it so the next request fails fast.
            AuthTokenProvider.clearTokens()
            throw NetworkError.unauthorized
        }

        let decoded: RefreshResponse
        do {
            decoded = try decoder.decode(RefreshResponse.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }

        // Rotation: store BOTH new tokens.
        AuthTokenProvider.storeTokens(access: decoded.token, refresh: decoded.refreshToken)
        return decoded.token
    }
}

// MARK: - URLSessionDelegate (SPKI pinning)

extension NetworkClient: URLSessionDelegate {

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        #if DEBUG
        // No pinning in debug — trust the platform's chain validation so
        // self-signed dev certs and charlesproxy don't break the simulator.
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        return
        #else
        // Production: require SecTrust to pass chain validation AND require
        // the leaf's SPKI SHA-256 to match our pinned value.
        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let leaf = leafCertificate(from: serverTrust),
              let spkiHash = Self.spkiSHA256Base64(for: leaf) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if spkiHash == Self.PINNED_SPKI_SHA256 {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
        #endif
    }

    private func leafCertificate(from trust: SecTrust) -> SecCertificate? {
        if #available(iOS 15.0, *) {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leaf = chain.first else { return nil }
            return leaf
        } else {
            return SecTrustGetCertificateAtIndex(trust, 0)
        }
    }

    private static func spkiSHA256Base64(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let spkiData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        let digest = SHA256.hash(data: spkiData)
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Shared bridge to Keychain-backed tokens
//
// NetworkClient is lower in the dependency graph than AuthViewModel, so we
// read/write the tokens directly against the Keychain here rather than
// reaching back up into the view model.

enum AuthTokenProvider {
    static func accessToken() -> String? {
        guard let data = KeychainStore.load(AuthKeychainKey.accessToken) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func refreshToken() -> String? {
        guard let data = KeychainStore.load(AuthKeychainKey.refreshToken) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func storeTokens(access: String, refresh: String?) {
        if let data = access.data(using: .utf8) {
            KeychainStore.save(data, for: AuthKeychainKey.accessToken)
        }
        if let refresh, let data = refresh.data(using: .utf8) {
            KeychainStore.save(data, for: AuthKeychainKey.refreshToken)
        }
    }

    static func clearTokens() {
        KeychainStore.delete(AuthKeychainKey.accessToken)
        KeychainStore.delete(AuthKeychainKey.refreshToken)
    }
}

// MARK: - Supporting types

/// Returned when the caller doesn't care about the response body
/// (e.g. DELETE /auth/account → 204).
struct EmptyResponse: Decodable {}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct RefreshResponse: Decodable {
    let token: String
    let refreshToken: String
}

/// Type-erasing wrapper so we can accept `Encodable` directly at the call site
/// without forcing every caller to introduce a concrete type.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: Encodable) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
