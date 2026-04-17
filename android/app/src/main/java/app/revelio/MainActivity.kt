package app.revelio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.tooling.preview.Preview
import dagger.hilt.android.AndroidEntryPoint

/**
 * Hosts the single-activity Compose UI. The NavHost is wired up in a later
 * patch once the destination composables exist.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface { Text("Revelio") }
            }
        }
    }
}

@Preview
@androidx.compose.runtime.Composable
private fun PreviewRoot() {
    MaterialTheme { Surface { Text("Revelio") } }
}
