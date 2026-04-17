package app.revelio

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
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authRepository: AuthRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val start = if (authRepository.isAuthenticated) Routes.SCAN else Routes.PHONE_ENTRY
        setContent {
            RevelioTheme {
                RevelioNavHost(startDestination = start)
            }
        }
    }
}
