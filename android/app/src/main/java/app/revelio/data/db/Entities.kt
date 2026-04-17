package app.revelio.data.db

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Scan history row. The user may be anonymous, so [userId] is nullable.
 * One row per scan event — a product can appear many times with different
 * timestamps.
 */
@Entity(tableName = "scan_history")
data class ScanHistoryEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id") val id: Long = 0,
    @ColumnInfo(name = "user_id") val userId: String?,
    @ColumnInfo(name = "barcode") val barcode: String,
    @ColumnInfo(name = "product_name") val productName: String,
    @ColumnInfo(name = "brand") val brand: String?,
    @ColumnInfo(name = "category") val category: String,
    @ColumnInfo(name = "image_url") val imageUrl: String?,
    @ColumnInfo(name = "score") val score: Int,
    @ColumnInfo(name = "grade") val grade: String,
    @ColumnInfo(name = "scanned_at") val scannedAtEpochMs: Long,
)

/**
 * Pantry item — the kitchen/bathroom snapshot the user curates. Indexed by
 * (userId, barcode) with a unique constraint enforced at the DAO via
 * `OnConflictStrategy.REPLACE`.
 */
@Entity(tableName = "pantry_items")
data class PantryItemEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id") val id: Long = 0,
    @ColumnInfo(name = "user_id") val userId: String,
    @ColumnInfo(name = "barcode") val barcode: String,
    @ColumnInfo(name = "product_name") val productName: String,
    @ColumnInfo(name = "brand") val brand: String?,
    @ColumnInfo(name = "score") val score: Int,
    @ColumnInfo(name = "grade") val grade: String,
    @ColumnInfo(name = "image_url") val imageUrl: String?,
    @ColumnInfo(name = "category") val category: String,
    @ColumnInfo(name = "added_at") val addedAtEpochMs: Long,
)
