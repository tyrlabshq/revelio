package app.revelio.data.repo

import app.revelio.data.api.RevelioApi
import app.revelio.data.api.dto.RequestOtpBody
import app.revelio.data.api.dto.VerifyOtpBody
import app.revelio.data.auth.SecureTokenStore
import app.revelio.domain.UserProfile
import com.squareup.moshi.Moshi
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val api: RevelioApi,
    private val tokens: SecureTokenStore,
    private val moshi: Moshi,
) {
    private val userAdapter = moshi.adapter(UserProfile::class.java)

    val isAuthenticated: Boolean
        get() = !tokens.accessToken.isNullOrBlank()

    val cachedUser: UserProfile?
        get() = tokens.userJson?.let { runCatching { userAdapter.fromJson(it) }.getOrNull() }

    suspend fun requestOtp(phone: String) {
        api.requestOtp(RequestOtpBody(phone = phone))
    }

    suspend fun verifyOtp(phone: String, code: String): UserProfile? {
        val result = api.verifyOtp(VerifyOtpBody(phone = phone, code = code))
        tokens.accessToken = result.accessToken
        tokens.refreshToken = result.refreshToken
        result.user?.let { tokens.userJson = userAdapter.toJson(it) }
        return result.user
    }

    suspend fun refreshMe(): UserProfile {
        val me = api.me().user
        tokens.userJson = userAdapter.toJson(me)
        return me
    }

    fun signOut() {
        tokens.clearAll()
    }
}
