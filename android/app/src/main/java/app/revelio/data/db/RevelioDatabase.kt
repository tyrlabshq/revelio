package app.revelio.data.db

import androidx.room.Database
import androidx.room.RoomDatabase

/**
 * Offline-first SQLite DB. Encrypted at rest via SQLCipher; the passphrase
 * is stored in [app.revelio.data.auth.SecureTokenStore] (EncryptedSharedPrefs).
 */
@Database(
    entities = [ScanHistoryEntity::class, PantryItemEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class RevelioDatabase : RoomDatabase() {
    abstract fun scanHistoryDao(): ScanHistoryDao
    abstract fun pantryDao(): PantryDao
}
