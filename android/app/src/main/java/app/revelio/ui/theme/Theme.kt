package app.revelio.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = RevelioAccent,
    onPrimary = RevelioSurface,
    background = RevelioBackground,
    onBackground = RevelioTextPrimary,
    surface = RevelioSurface,
    onSurface = RevelioTextPrimary,
    surfaceVariant = RevelioSurfaceElevated,
    onSurfaceVariant = RevelioTextSecondary,
    error = RevelioDanger,
)

private val DarkColors = darkColorScheme(
    primary = RevelioAccent,
    onPrimary = RevelioSurface,
    background = RevelioBackgroundDark,
    onBackground = RevelioTextPrimaryDark,
    surface = RevelioSurfaceDark,
    onSurface = RevelioTextPrimaryDark,
    surfaceVariant = RevelioSurfaceElevatedDark,
    onSurfaceVariant = RevelioTextSecondaryDark,
    error = RevelioDanger,
)

@Composable
fun RevelioTheme(
    useDarkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (useDarkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colorScheme,
        typography = RevelioTypography,
        content = content,
    )
}
