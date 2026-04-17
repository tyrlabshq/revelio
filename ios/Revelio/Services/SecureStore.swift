import Foundation
import CryptoKit
import Security

/// Minimal encrypted-at-rest store for sensitive user data (scan history,
/// favorites). A random 256-bit key is generated on first use and stored in
/// the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
/// so the key is unavailable before first unlock and does not sync across
/// devices. Payloads are AES-GCM sealed and written to Application Support
/// with `.completeFileProtection`.
enum SecureStoreError: Error {
    case keychain(OSStatus)
    case encodingFailure
    case decodingFailure
    case ioFailure(Error)
}

final class SecureStore {
    static let shared = SecureStore()

    private let keychainService = "app.revelio.securestore"
    private let keychainAccount = "master-key-v1"

    private init() {}

    // MARK: - Keychain-backed master key

    private func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try storeKey(key)
        return key
    }

    private func loadKey() throws -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureStoreError.keychain(status)
        }
        return SymmetricKey(data: data)
    }

    private func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.keychain(status)
        }
    }

    // MARK: - Public API

    /// Encrypt and persist a JSON-encodable value at `filename` under
    /// Application Support with full file protection.
    func write<T: Encodable>(_ value: T, to filename: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let plaintext = try? encoder.encode(value) else {
            throw SecureStoreError.encodingFailure
        }
        let key = try loadOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw SecureStoreError.encodingFailure
        }
        let url = try fileURL(for: filename)
        do {
            try combined.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw SecureStoreError.ioFailure(error)
        }
    }

    /// Read and decrypt a previously-written value. Returns nil if the file
    /// does not exist (first launch) or cannot be decrypted (e.g. key lost
    /// on restore from another device).
    func read<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let url = try fileURL(for: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: url)
        } catch {
            throw SecureStoreError.ioFailure(error)
        }
        let key = try loadOrCreateKey()
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(box, using: key)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: plaintext)
        } catch {
            // Key mismatch or tampered file — surface as nil so the caller
            // can fall back to empty state rather than crashing.
            return nil
        }
    }

    // MARK: - Paths

    private func fileURL(for filename: String) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory,
                              in: .userDomainMask,
                              appropriateFor: nil,
                              create: true)
        let dir = base.appendingPathComponent("SecureStore", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.complete])
        }
        return dir.appendingPathComponent(filename)
    }
}
