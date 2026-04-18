package app.revelio.data.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Encrypted storage for auth tokens, the cached user JSON blob, and the
 * SQLCipher passphrase. Uses the Android Keystore (AES-256-GCM) via
 * [EncryptedSharedPreferences] so nothing sensitive sits in plaintext.
 *
 * Mirrors the iOS Keychain wrapper — callers should never hit
 * UserDefaults / SharedPreferences directly for tokens.
 */
@Singleton
class SecureTokenStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences = buildPrefs(context)

    var accessToken: String?
        get() = prefs.getString(KEY_ACCESS, null)
        set(value) = prefs.edit().putString(KEY_ACCESS, value).apply()

    var refreshToken: String?
        get() = prefs.getString(KEY_REFRESH, null)
        set(value) = prefs.edit().putString(KEY_REFRESH, value).apply()

    /** Raw JSON blob for the cached [app.revelio.domain.UserProfile]. */
    var userJson: String?
        get() = prefs.getString(KEY_USER, null)
        set(value) = prefs.edit().putString(KEY_USER, value).apply()

    /**
     * Random passphrase used to open the SQLCipher-encrypted Room DB.
     * Generated lazily on first access and persisted; survives reinstall only
     * if the user opts into device-to-device transfer (we exclude it — see
     * [data_extraction_rules.xml]).
     */
    fun getOrCreateDbPassphrase(): CharArray {
        prefs.getString(KEY_DB_PASS, null)?.let { return it.toCharArray() }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val hex = bytes.joinToString(separator = "") { "%02x".format(it) }
        prefs.edit().putString(KEY_DB_PASS, hex).apply()
        return hex.toCharArray()
    }

    fun clearAll() {
        prefs.edit().clear().apply()
    }

    private fun buildPrefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        return EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    companion object {
        private const val PREFS_NAME = "revelio_secure_prefs"
        private const val KEY_ACCESS = "access_token"
        private const val KEY_REFRESH = "refresh_token"
        private const val KEY_USER = "user_json"
        private const val KEY_DB_PASS = "db_passphrase"
    }
}
