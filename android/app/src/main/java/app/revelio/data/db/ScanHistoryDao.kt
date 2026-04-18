package app.revelio.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ScanHistoryDao {

    @Query("SELECT * FROM scan_history ORDER BY scanned_at DESC LIMIT :limit")
    fun observeRecent(limit: Int = 100): Flow<List<ScanHistoryEntity>>

    @Query("SELECT * FROM scan_history WHERE user_id = :userId ORDER BY scanned_at DESC LIMIT :limit")
    fun observeForUser(userId: String, limit: Int = 100): Flow<List<ScanHistoryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: ScanHistoryEntity): Long

    @Query("DELETE FROM scan_history WHERE id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM scan_history")
    suspend fun clear()
}
