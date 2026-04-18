package app.revelio.data.api

import app.revelio.data.auth.SecureTokenStore
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Attaches `Authorization: Bearer <accessToken>` to every outgoing request
 * when a token is present. Auth endpoints (`/auth/*`) are unauthenticated
 * by nature — we still attach the header if a token happens to exist; the
 * server ignores it on those routes.
 */
@Singleton
class AuthInterceptor @Inject constructor(
    private val tokenStore: SecureTokenStore,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val token = tokenStore.accessToken
        val request = if (token.isNullOrBlank()) {
            original
        } else {
            original.newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
        }
        return chain.proceed(request)
    }
}
