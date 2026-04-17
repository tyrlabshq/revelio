package app.revelio.domain

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

// ─── Category / priority enums ──────────────────────────────────────────────────

/** Product category — mirrors `shared/scoring.ts::Category`. */
enum class Category {
    @Json(name = "food") FOOD,
    @Json(name = "cosmetics") COSMETICS,
    @Json(name = "cleaning") CLEANING,
    @Json(name = "supplements") SUPPLEMENTS;

    companion object {
        fun fromWire(raw: String?): Category = when (raw?.lowercase()) {
            "cosmetics", "beauty" -> COSMETICS
            "cleaning" -> CLEANING
            "supplements", "supplement" -> SUPPLEMENTS
            else -> FOOD
        }
    }
}

/** User priority tags — mirrors `shared/scoring.ts::UserPriority`. */
enum class UserPriority(val wire: String) {
    SEED_OILS("seed_oils"),
    ARTIFICIAL_ADDITIVES("artificial_additives"),
    HEAVY_METALS("heavy_metals"),
    ENDOCRINE_DISRUPTORS("endocrine_disruptors"),
    GLUTEN_FREE("gluten_free"),
    KETO("keto"),
    VEGAN("vegan"),
    FRAGRANCE_FREE("fragrance_free"),
    PARABEN_FREE("paraben_free"),
    SULFATE_FREE("sulfate_free");

    companion object {
        fun fromWire(raw: String?): UserPriority? =
            values().firstOrNull { it.wire == raw?.lowercase() }
    }
}

/** Grade — A (best) to F (worst). */
enum class Grade {
    @Json(name = "A") A,
    @Json(name = "B") B,
    @Json(name = "C") C,
    @Json(name = "D") D,
    @Json(name = "F") F;

    companion object {
        fun fromScore(score: Int): Grade = when {
            score >= 80 -> A
            score >= 65 -> B
            score >= 50 -> C
            score >= 35 -> D
            else -> F
        }
    }
}

// ─── Scan / scoring models ──────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class Citation(
    @Json(name = "title") val title: String,
    @Json(name = "url") val url: String,
    @Json(name = "year") val year: Int,
)

@JsonClass(generateAdapter = true)
data class IngredientFlag(
    @Json(name = "ingredient") val ingredient: String,
    /** 0 = fine, 1 = watch, 2 = concerning, 3 = avoid. */
    @Json(name = "severity") val severity: Int,
    @Json(name = "category") val category: String,
    @Json(name = "reason") val reason: String,
    @Json(name = "citation") val citation: Citation? = null,
    /** String-ified priorities (we accept wire strings, not the enum, for forward-compat). */
    @Json(name = "priorities") val priorities: List<String> = emptyList(),
) {
    /** Parsed list of priorities that matched ours. */
    fun priorityEnums(): List<UserPriority> = priorities.mapNotNull(UserPriority::fromWire)
}

@JsonClass(generateAdapter = true)
data class ScanResult(
    @Json(name = "id") val id: String? = null,
    @Json(name = "barcode") val barcode: String,
    @Json(name = "productName") val productName: String,
    @Json(name = "brand") val brand: String? = null,
    @Json(name = "category") val category: String = "food",
    @Json(name = "imageUrl") val imageUrl: String? = null,
    @Json(name = "ingredients") val ingredients: List<String> = emptyList(),
    @Json(name = "flags") val flags: List<IngredientFlag> = emptyList(),
    @Json(name = "baseScore") val baseScore: Int = 0,
    @Json(name = "personalizedScore") val personalizedScore: Int = 0,
    @Json(name = "grade") val grade: String = "C",
    @Json(name = "scannedAt") val scannedAt: String? = null,
)

// ─── Alternatives ───────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class AlternativeProduct(
    @Json(name = "name") val name: String,
    @Json(name = "brand") val brand: String,
    @Json(name = "score") val score: Int,
    @Json(name = "imageUrl") val imageUrl: String? = null,
    @Json(name = "purchaseUrl") val purchaseUrl: String,
    @Json(name = "affiliateNetwork") val affiliateNetwork: String,
    @Json(name = "priceCents") val priceCents: Int? = null,
)

// ─── User / family / profile ────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class UserProfile(
    @Json(name = "id") val id: String,
    @Json(name = "name") val name: String? = null,
    @Json(name = "phone") val phone: String? = null,
    @Json(name = "tier") val tier: String = "free",
    @Json(name = "priorities") val priorities: List<String> = emptyList(),
    @Json(name = "allergies") val allergies: List<String> = emptyList(),
    @Json(name = "goals") val goals: List<String> = emptyList(),
)

@JsonClass(generateAdapter = true)
data class FamilyMember(
    @Json(name = "id") val id: String,
    @Json(name = "owner_id") val ownerId: String? = null,
    @Json(name = "name") val name: String,
    @Json(name = "is_child") val isChild: Boolean = false,
    @Json(name = "goals") val goals: List<String> = emptyList(),
    @Json(name = "allergies") val allergies: List<String> = emptyList(),
    @Json(name = "avatar_color") val avatarColor: String = "#00B87C",
)

// ─── Pantry / history ───────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class PantryItem(
    @Json(name = "id") val id: Long? = null,
    @Json(name = "barcode") val barcode: String,
    @Json(name = "productName") val productName: String,
    @Json(name = "brand") val brand: String? = null,
    @Json(name = "score") val score: Int = 0,
    @Json(name = "grade") val grade: String = "C",
    @Json(name = "imageUrl") val imageUrl: String? = null,
    @Json(name = "category") val category: String = "food",
    @Json(name = "addedAt") val addedAt: String? = null,
)

@JsonClass(generateAdapter = true)
data class HistoryEntry(
    @Json(name = "id") val id: String? = null,
    @Json(name = "barcode") val barcode: String,
    @Json(name = "product_name") val productName: String,
    @Json(name = "score") val score: Int,
    @Json(name = "grade") val grade: String,
    @Json(name = "scanned_at") val scannedAt: String? = null,
)
