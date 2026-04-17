package app.revelio.ui.theme

import androidx.compose.ui.graphics.Color

// Tokens mirror ios/Revelio/Theme/Theme.swift.

val RevelioBackground = Color(0xFFFAFAF8)         // warm off-white
val RevelioSurface = Color(0xFFFFFFFF)            // pure white cards
val RevelioSurfaceElevated = Color(0xFFF2F2EE)    // very light warm gray

val RevelioAccent = Color(0xFF00B87C)             // fresh emerald green

val RevelioTextPrimary = Color(0xFF111827)        // near-black
val RevelioTextSecondary = Color(0xFF6B7280)      // medium gray
val RevelioTextDim = Color(0xFF9CA3AF)            // light gray

val RevelioSuccess = Color(0xFF22C55E)
val RevelioWarning = Color(0xFFF59E0B)
val RevelioDanger = Color(0xFFEF4444)

// Dark mode palette
val RevelioBackgroundDark = Color(0xFF0B0F17)
val RevelioSurfaceDark = Color(0xFF121826)
val RevelioSurfaceElevatedDark = Color(0xFF1A2233)
val RevelioTextPrimaryDark = Color(0xFFF3F4F6)
val RevelioTextSecondaryDark = Color(0xFFA1A1AA)

/** Grade → color mapping, mirrors Theme.gradeColor on iOS. */
fun gradeColor(grade: String): Color = when (grade.uppercase()) {
    "A" -> Color(0xFF22C55E)
    "B" -> Color(0xFF84CC16)
    "C" -> Color(0xFFF59E0B)
    "D" -> Color(0xFFF97316)
    else -> Color(0xFFEF4444)
}
