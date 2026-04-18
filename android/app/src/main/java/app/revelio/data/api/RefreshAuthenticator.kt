package app.revelio.data.api

import app.revelio.data.api.dto.RefreshBody
import app.revelio.data.auth.SecureTokenStore
import kotlinx.coroutines.runBlocking
import okhttp3.Authenticator
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import javax.inject.Inject
import javax.inject.Provider
import javax.inject.Singleton

/**
 * On 401, tries the refresh endpoint once, updates the token store, and
 * retries the original request with the new access token. Uses a Provider
 * for [RevelioApi] because the API depends on OkHttp which depends on this
 * authenticator — breaks the DI cycle.
 */
@Singleton
class RefreshAuthenticator @Inject constructor(
    private val tokenStore: SecureTokenStore,
    private val apiProvider: Provider<RevelioApi>,
) : Authenticator {

    override fun authenticate(route: Route?, response: Response): Request? {
        // Avoid infinite loops: if we already retried, give up.
        if (response.priorResponse != null) return null
        if (responseCount(response) >= 2) return null

        val refresh = tokenStore.refreshToken ?: return null

        val newTokens = try {
            runBlocking { apiProvider.get().refresh(RefreshBody(refresh)) }
        } catch (t: Throwable) {
            // Refresh failed → surface the 401 to callers.
            tokenStore.clearAll()
            return null
        }

        tokenStore.accessToken = newTokens.accessToken
        if (!newTokens.refreshToken.isNullOrBlank()) {
            tokenStore.refreshToken = newTokens.refreshToken
        }

        return response.request.newBuilder()
            .header("Authorization", "Bearer ${newTokens.accessToken}")
            .build()
    }

    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count++
            prior = prior.priorResponse
        }
        return count
    }
}
