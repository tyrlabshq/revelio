package app.revelio.data.repo

import app.revelio.data.api.RevelioApi
import app.revelio.data.api.dto.RecordScanBody
import app.revelio.data.db.ScanHistoryDao
import app.revelio.data.db.ScanHistoryEntity
import app.revelio.domain.AlternativeProduct
import app.revelio.domain.ScanResult
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScanRepository @Inject constructor(
    private val api: RevelioApi,
    private val dao: ScanHistoryDao,
) {
    /**
     * Fetches scan metadata for [barcode] from the backend and caches the
     * result in local history. The caller owns UI presentation of errors —
     * we just surface the API exception.
     */
    suspend fun scan(barcode: String, userId: String?): ScanResult {
        val result = api.scan(barcode)
        dao.insert(
            ScanHistoryEntity(
                userId = userId,
                barcode = result.barcode,
                productName = result.productName,
                brand = result.brand,
                category = result.category,
                imageUrl = result.imageUrl,
                score = result.personalizedScore.takeIf { it > 0 } ?: result.baseScore,
                grade = result.grade,
                scannedAtEpochMs = System.currentTimeMillis(),
            )
        )
        // Best-effort server-side history record (non-fatal).
        runCatching {
            api.recordScan(
                RecordScanBody(
                    userId = userId,
                    barcode = result.barcode,
                    productName = result.productName,
                    brand = result.brand,
                    category = result.category,
                    imageUrl = result.imageUrl,
                    score = result.personalizedScore.takeIf { it > 0 } ?: result.baseScore,
                    grade = result.grade,
                    flags = result.flags,
                )
            )
        }
        return result
    }

    suspend fun alternatives(barcode: String): List<AlternativeProduct> =
        api.alternatives(barcode).alternatives

    fun observeHistory(userId: String?): Flow<List<ScanHistoryEntity>> =
        if (userId == null) dao.observeRecent() else dao.observeForUser(userId)

    suspend fun clearHistory() = dao.clear()

    suspend fun deleteHistoryEntry(id: Long) = dao.deleteById(id)
}
