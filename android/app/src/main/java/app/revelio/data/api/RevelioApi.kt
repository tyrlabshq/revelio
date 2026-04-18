package app.revelio.data.api

import app.revelio.data.api.dto.AddMemberBody
import app.revelio.data.api.dto.AddPantryBody
import app.revelio.data.api.dto.AlternativesResponse
import app.revelio.data.api.dto.AuthTokens
import app.revelio.data.api.dto.MemberResponse
import app.revelio.data.api.dto.MembersResponse
import app.revelio.data.api.dto.MeResponse
import app.revelio.data.api.dto.PantryListResponse
import app.revelio.data.api.dto.PantryScoreResponse
import app.revelio.data.api.dto.ProfileResponse
import app.revelio.data.api.dto.RecordScanBody
import app.revelio.data.api.dto.RecordScanResponse
import app.revelio.data.api.dto.RefreshBody
import app.revelio.data.api.dto.RequestOtpBody
import app.revelio.data.api.dto.RequestOtpResponse
import app.revelio.data.api.dto.ScansInsightsResponse
import app.revelio.data.api.dto.UpdateProfileBody
import app.revelio.data.api.dto.VerifyOtpBody
import app.revelio.domain.HistoryEntry
import app.revelio.domain.ScanResult
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Revelio backend HTTP surface. Mirrors the endpoints the iOS client uses so
 * we can reuse the hardened server 1:1.
 */
interface RevelioApi {

    // ─── Auth ──────────────────────────────────────────────────────────────────
    @POST("auth/request-otp")
    suspend fun requestOtp(@Body body: RequestOtpBody): RequestOtpResponse

    @POST("auth/verify-otp")
    suspend fun verifyOtp(@Body body: VerifyOtpBody): AuthTokens

    @POST("auth/refresh")
    suspend fun refresh(@Body body: RefreshBody): AuthTokens

    @GET("auth/me")
    suspend fun me(): MeResponse

    // ─── Scan ──────────────────────────────────────────────────────────────────
    @GET("scan/{barcode}")
    suspend fun scan(@Path("barcode") barcode: String): ScanResult

    @GET("scan/history")
    suspend fun scanHistory(
        @Query("userId") userId: String,
        @Query("limit") limit: Int = 50,
    ): List<HistoryEntry>

    @POST("scan/history")
    suspend fun recordScan(@Body body: RecordScanBody): RecordScanResponse

    // ─── Pantry ────────────────────────────────────────────────────────────────
    @GET("pantry")
    suspend fun pantry(@Query("user_id") userId: String): PantryListResponse

    @POST("pantry")
    suspend fun addToPantry(@Body body: AddPantryBody): RecordScanResponse

    @DELETE("pantry/{barcode}")
    suspend fun removeFromPantry(
        @Path("barcode") barcode: String,
        @Query("user_id") userId: String,
    ): RecordScanResponse

    @GET("pantry/score")
    suspend fun pantryScore(@Query("user_id") userId: String): PantryScoreResponse

    // ─── Profile ───────────────────────────────────────────────────────────────
    @GET("profiles/{id}")
    suspend fun profile(@Path("id") id: String): ProfileResponse

    @PATCH("profiles/{id}")
    suspend fun updateProfile(
        @Path("id") id: String,
        @Body body: UpdateProfileBody,
    ): ProfileResponse

    @GET("profiles/{id}/members")
    suspend fun members(@Path("id") id: String): MembersResponse

    @POST("profiles/{id}/members")
    suspend fun addMember(
        @Path("id") id: String,
        @Body body: AddMemberBody,
    ): MemberResponse

    // ─── Alternatives ──────────────────────────────────────────────────────────
    @GET("alternatives/{barcode}")
    suspend fun alternatives(@Path("barcode") barcode: String): AlternativesResponse

    // ─── Scans insights ────────────────────────────────────────────────────────
    @GET("scans")
    suspend fun scans(@Query("userId") userId: String): List<HistoryEntry>

    @GET("scans/insights")
    suspend fun scansInsights(@Query("userId") userId: String): ScansInsightsResponse
}
