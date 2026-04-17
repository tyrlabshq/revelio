package app.revelio.domain

import com.squareup.moshi.JsonClass

enum class ProductCategory(val id: String, val display: String, val icon: String) {
    FOOD("food", "Food", "🍎"),
    COSMETICS("cosmetics", "Cosmetic", "💄"),
    CLEANING("cleaning", "Cleaning", "🧴"),
    SUPPLEMENTS("supplements", "Supplement", "💊");

    companion object {
        fun fromId(id: String): ProductCategory =
            entries.firstOrNull { it.id == id.lowercase() } ?: FOOD
    }
}

enum class Grade { A, B, C, D, F }

@JsonClass(generateAdapter = true)
data class Citation(
    val title: String,
    val url: String,
    val year: Int
)

@JsonClass(generateAdapter = true)
data class IngredientFlag(
    val ingredient: String,
    val severity: Int,
    val category: String,
    val reason: String,
    val priorities: List<String> = emptyList(),
    val citation: Citation? = null
) {
    val severityLabel: String get() = when (severity) {
        1 -> "WATCH"
        2 -> "CONCERNING"
        3 -> "AVOID"
        else -> "FINE"
    }
}

@JsonClass(generateAdapter = true)
data class AlternativeProduct(
    val name: String,
    val brand: String,
    val score: Int,
    val imageUrl: String? = null,
    val purchaseUrl: String,
    val affiliateNetwork: String,
    val priceCents: Int? = null
)

@JsonClass(generateAdapter = true)
data class ScanResult(
    val barcode: String,
    val productName: String,
    val brand: String,
    val category: String,
    val imageUrl: String? = null,
    val ingredients: List<String> = emptyList(),
    val flags: List<IngredientFlag> = emptyList(),
    val baseScore: Int,
    val personalizedScore: Int,
    val grade: String,
    val alternatives: List<AlternativeProduct>? = null
)

@JsonClass(generateAdapter = true)
data class UserProfile(
    val id: String,
    val name: String = "",
    val phone: String = "",
    val tier: String = "free",
    val priorities: List<String> = emptyList(),
    val allergies: List<String> = emptyList(),
    val dietaryRestrictions: List<String> = emptyList()
) {
    val isPro: Boolean get() = tier == "pro"
}
