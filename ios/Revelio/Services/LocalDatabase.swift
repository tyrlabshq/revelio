import Foundation
import GRDB
import Security

/// Shared GRDB database for Revelio's offline-first storage.
///
/// The database is encrypted at rest with SQLCipher. The passphrase is
/// generated on first launch (256 bits of cryptographic randomness, base64
/// encoded), stored in the iOS Keychain with
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and rotated only when
/// the user deletes their account.
///
/// Tables owned here:
///   • `scan_history` — one row per scanned product (most-recent wins on
///     barcode collision).
///   • `pantry_items` — products the user has explicitly added to their
///     pantry.
///   • `favorites` — barcode strings the user has starred.
///
/// Schema migrations are declarative; add a new `registerMigration` block
/// per change. Never mutate an existing migration — create a new one.
final class LocalDatabase {
    static let shared = LocalDatabase()

    /// The shared pool. Nil only if initialization failed hard (we log and
    /// return in-memory fallback so the app still launches).
    let queue: DatabaseWriter

    private init() {
        let dw: DatabaseWriter
        do {
            dw = try Self.makeOnDiskQueue()
        } catch {
            NSLog("[LocalDatabase] Disk init failed: \(error). Falling back to in-memory store.")
            // In-memory fallback so callers never have to unwrap.
            dw = try! DatabaseQueue()
        }
        self.queue = dw

        do {
            try Self.migrator.migrate(dw)
        } catch {
            NSLog("[LocalDatabase] Migration failed: \(error)")
        }
    }

    // MARK: - Disk setup

    private static func makeOnDiskQueue() throws -> DatabaseWriter {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Revelio", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let dbURL = dir.appendingPathComponent("revelio.sqlite")

        var config = Configuration()
        let passphrase = try KeychainPassphrase.loadOrCreate()
        config.prepareDatabase { db in
            try db.usePassphrase(passphrase)
        }
        config.foreignKeysEnabled = true

        let pool = try DatabasePool(path: dbURL.path, configuration: config)
        return pool
    }

    // MARK: - Migrations

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "scan_history") { t in
                t.column("id", .text).primaryKey()
                t.column("barcode", .text).notNull().indexed()
                t.column("product_name", .text).notNull()
                t.column("brand", .text).notNull()
                t.column("category", .text).notNull()
                t.column("score", .integer).notNull()
                t.column("grade", .text).notNull()
                t.column("image_url", .text)
                t.column("scanned_at", .datetime).notNull().indexed()
                t.column("payload", .blob).notNull() // full ScanResult JSON
            }

            try db.create(table: "pantry_items") { t in
                t.column("id", .text).primaryKey()
                t.column("barcode", .text).notNull().unique()
                t.column("product_name", .text).notNull()
                t.column("brand", .text).notNull()
                t.column("category", .text)
                t.column("score", .integer).notNull()
                t.column("grade", .text).notNull()
                t.column("image_url", .text)
                t.column("quantity", .integer).notNull().defaults(to: 1)
                t.column("added_at", .datetime).notNull()
                t.column("payload", .blob).notNull() // full PantryItem JSON
            }

            try db.create(table: "favorites") { t in
                t.column("barcode", .text).primaryKey()
                t.column("added_at", .datetime).notNull()
            }
        }

        return m
    }
}

// MARK: - Keychain passphrase

/// Thin wrapper around a Keychain entry that holds the SQLCipher passphrase.
enum KeychainPassphrase {
    private static let service = "app.revelio.localdb"
    private static let account = "sqlcipher.passphrase"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case randomGenerationFailed
    }

    /// Load the existing passphrase if present, otherwise generate and
    /// persist a fresh one.
    static func loadOrCreate() throws -> String {
        if let existing = try load() {
            return existing
        }
        let fresh = try generatePassphrase()
        try store(fresh)
        return fresh
    }

    private static func load() throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        _ = query // keep keys scoped
        return str
    }

    private static func store(_ value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.randomGenerationFailed
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Try to add; if the item already exists (race), update it.
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    private static func generatePassphrase() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
    }
}
