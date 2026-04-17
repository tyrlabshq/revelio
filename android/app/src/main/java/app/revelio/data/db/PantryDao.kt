package app.revelio.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface PantryDao {

    @Query("SELECT * FROM pantry_items WHERE user_id = :userId ORDER BY added_at DESC")
    fun observeForUser(userId: String): Flow<List<PantryItemEntity>>

    @Query("SELECT * FROM pantry_items WHERE user_id = :userId AND barcode = :barcode LIMIT 1")
    suspend fun findByBarcode(userId: String, barcode: String): PantryItemEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PantryItemEntity): Long

    @Query("DELETE FROM pantry_items WHERE user_id = :userId AND barcode = :barcode")
    suspend fun delete(userId: String, barcode: String): Int

    @Query("DELETE FROM pantry_items WHERE user_id = :userId")
    suspend fun clearForUser(userId: String)
}
