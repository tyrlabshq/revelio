package app.revelio.data.repo

import app.revelio.data.api.RevelioApi
import app.revelio.data.api.dto.AddPantryBody
import app.revelio.data.api.dto.PantryScoreResponse
import app.revelio.data.db.PantryDao
import app.revelio.data.db.PantryItemEntity
import app.revelio.domain.PantryItem
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PantryRepository @Inject constructor(
    private val api: RevelioApi,
    private val dao: PantryDao,
) {
    /** Reactive local pantry. Sync from the server via [refresh]. */
    fun observe(userId: String): Flow<List<PantryItemEntity>> = dao.observeForUser(userId)

    suspend fun refresh(userId: String) {
        val items = api.pantry(userId).items
        // Mirror server rows into the local encrypted DB for offline access.
        // Destructive refresh is acceptable: pantry is user-curated and small.
        dao.clearForUser(userId)
        items.forEach { item ->
            dao.upsert(
                PantryItemEntity(
                    userId = userId,
                    barcode = item.barcode,
                    productName = item.productName,
                    brand = item.brand,
                    score = item.score,
                    grade = item.grade,
                    imageUrl = item.imageUrl,
                    category = item.category,
                    addedAtEpochMs = System.currentTimeMillis(),
                )
            )
        }
    }

    suspend fun add(userId: String, barcode: String) {
        api.addToPantry(AddPantryBody(userId = userId, barcode = barcode))
        refresh(userId)
    }

    suspend fun remove(userId: String, barcode: String) {
        api.removeFromPantry(barcode, userId)
        dao.delete(userId, barcode)
    }

    suspend fun score(userId: String): PantryScoreResponse = api.pantryScore(userId)
}
