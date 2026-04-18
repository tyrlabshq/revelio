package app.revelio

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.revelio.data.repo.AuthRepository
import app.revelio.ui.RevelioNavHost
import app.revelio.ui.Routes
import app.revelio.ui.theme.RevelioTheme
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Single-activity Compose host. Picks the start destination based on whether
 * the user already has a valid access token so signed-in users jump straight
 * to the scanner.
 *
 * Also consumes universal / deep-link intents (`https://revelio.app/p/<barcode>`
 * and `revelio://scan/<barcode>`) and forwards them to the nav graph as a
 * `RESULT` route so the tap opens directly on the scan result.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authRepository: AuthRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pendingBarcode = parseBarcode(intent)
        val start = when {
            pendingBarcode != null && authRepository.isAuthenticated -> Routes.resultRoute(pendingBarcode)
            authRepository.isAuthenticated -> Routes.SCAN
            else -> Routes.PHONE_ENTRY
        }
        setContent {
            RevelioTheme {
                RevelioNavHost(startDestination = start)
            }
        }
    }

    /**
     * Called when a new deep-link intent arrives while the activity is already
     * running (singleTop / singleTask behaviour). We currently re-launch the
     * start destination in `onCreate`-style; the nav controller is not yet
     * hoisted here, so the pragmatic approach is to restart the activity with
     * the new intent so the nav graph re-evaluates its start destination.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (parseBarcode(intent) == null) return
        // Recreate so the RevelioNavHost picks up the new start destination.
        // Simpler than hoisting the NavController out of the composable tree
        // for a single entry point.
        setIntent(intent)
        recreate()
    }

    /**
     * Pull a valid 6-14 digit barcode out of either:
     *   - https://revelio.app/p/<barcode> (Android App Link)
     *   - revelio://scan/<barcode>        (custom scheme fallback)
     * Returns null for any other shape; never returns unvalidated user input.
     */
    private fun parseBarcode(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val data: Uri = intent.data ?: return null
        val scheme = data.scheme?.lowercase()
        val host = data.host?.lowercase()
        val segments = data.pathSegments.orEmpty()

        val candidate: String? = when {
            scheme == "https" && (host == "revelio.app" || host == "www.revelio.app") &&
                segments.size >= 2 && segments[0] == "p" -> segments[1]
            scheme == "revelio" && host == "scan" && segments.isNotEmpty() -> segments[0]
            else -> null
        }
        return candidate?.takeIf { it.length in 6..14 && it.all(Char::isDigit) }
    }
}
