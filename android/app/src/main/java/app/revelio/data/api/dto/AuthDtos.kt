package app.revelio.data.api.dto

import app.revelio.domain.AlternativeProduct
import app.revelio.domain.FamilyMember
import app.revelio.domain.HistoryEntry
import app.revelio.domain.IngredientFlag
import app.revelio.domain.PantryItem
import app.revelio.domain.UserProfile
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

// ─── /auth/request-otp ──────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class RequestOtpBody(
    @Json(name = "phone") val phone: String,
)

@JsonClass(generateAdapter = true)
data class RequestOtpResponse(
    @Json(name = "ok") val ok: Boolean = true,
)

// ─── /auth/verify-otp ───────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class VerifyOtpBody(
    @Json(name = "phone") val phone: String,
    @Json(name = "code") val code: String,
)

@JsonClass(generateAdapter = true)
data class AuthTokens(
    @Json(name = "token") val accessToken: String,
    @Json(name = "refreshToken") val refreshToken: String? = null,
    @Json(name = "user") val user: UserProfile? = null,
)

// ─── /auth/refresh ──────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class RefreshBody(
    @Json(name = "refreshToken") val refreshToken: String,
)

// ─── /auth/me ───────────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class MeResponse(
    @Json(name = "user") val user: UserProfile,
)

// ─── /scan/history (POST body) ──────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class RecordScanBody(
    @Json(name = "userId") val userId: String? = null,
    @Json(name = "barcode") val barcode: String,
    @Json(name = "productName") val productName: String,
    @Json(name = "brand") val brand: String? = null,
    @Json(name = "category") val category: String = "food",
    @Json(name = "imageUrl") val imageUrl: String? = null,
    @Json(name = "score") val score: Int,
    @Json(name = "grade") val grade: String,
    @Json(name = "flags") val flags: List<IngredientFlag> = emptyList(),
)

@JsonClass(generateAdapter = true)
data class RecordScanResponse(
    @Json(name = "ok") val ok: Boolean = true,
)

// ─── Pantry ─────────────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class PantryListResponse(
    @Json(name = "items") val items: List<PantryItem> = emptyList(),
)

@JsonClass(generateAdapter = true)
data class AddPantryBody(
    @Json(name = "user_id") val userId: String,
    @Json(name = "barcode") val barcode: String,
)

@JsonClass(generateAdapter = true)
data class PantryScoreResponse(
    @Json(name = "score") val score: Int = 0,
    @Json(name = "grade") val grade: String = "N/A",
    @Json(name = "clean") val cleanPct: Int = 0,
    @Json(name = "concerning") val concerningPct: Int = 0,
    @Json(name = "avoid") val avoidPct: Int = 0,
    @Json(name = "total") val total: Int = 0,
)

// ─── Profile ────────────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class ProfileResponse(
    @Json(name = "profile") val profile: UserProfile,
)

@JsonClass(generateAdapter = true)
data class UpdateProfileBody(
    @Json(name = "priorities") val priorities: List<String>? = null,
    @Json(name = "allergies") val allergies: List<String>? = null,
    @Json(name = "goals") val goals: List<String>? = null,
)

@JsonClass(generateAdapter = true)
data class MembersResponse(
    @Json(name = "members") val members: List<FamilyMember> = emptyList(),
)

@JsonClass(generateAdapter = true)
data class AddMemberBody(
    @Json(name = "name") val name: String,
    @Json(name = "is_child") val isChild: Boolean = false,
    @Json(name = "goals") val goals: List<String> = emptyList(),
    @Json(name = "allergies") val allergies: List<String> = emptyList(),
    @Json(name = "avatar_color") val avatarColor: String = "#00B87C",
)

@JsonClass(generateAdapter = true)
data class MemberResponse(
    @Json(name = "member") val member: FamilyMember,
)

// ─── Alternatives ───────────────────────────────────────────────────────────────

@JsonClass(generateAdapter = true)
data class AlternativesResponse(
    @Json(name = "alternatives") val alternatives: List<AlternativeProduct> = emptyList(),
)

// ─── Scans insights (lightweight; used on Profile screen) ───────────────────────

@JsonClass(generateAdapter = true)
data class ScansInsightsResponse(
    @Json(name = "totalScans") val totalScans: Int = 0,
    @Json(name = "averageScore") val averageScore: Int = 0,
    @Json(name = "topCategory") val topCategory: String? = null,
)
