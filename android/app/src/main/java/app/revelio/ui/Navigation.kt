package app.revelio.ui

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import app.revelio.ui.auth.OTPVerifyScreen
import app.revelio.ui.auth.PhoneEntryScreen
import app.revelio.ui.history.HistoryScreen
import app.revelio.ui.pantry.PantryScreen
import app.revelio.ui.profile.ProfileScreen
import app.revelio.ui.result.ScanResultScreen
import app.revelio.ui.scan.ScanScreen

/** Top-level nav graph. Keep route strings here so screens stay decoupled. */
object Routes {
    const val PHONE_ENTRY = "phone"
    const val OTP_VERIFY = "otp/{phone}"
    const val SCAN = "scan"
    const val RESULT = "result/{barcode}"
    const val HISTORY = "history"
    const val PANTRY = "pantry"
    const val PROFILE = "profile"

    fun otpRoute(phone: String) = "otp/$phone"
    fun resultRoute(barcode: String) = "result/$barcode"
}

@Composable
fun RevelioNavHost(startDestination: String = Routes.PHONE_ENTRY) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = startDestination) {
        composable(Routes.PHONE_ENTRY) {
            PhoneEntryScreen(
                onOtpRequested = { phone -> navController.navigate(Routes.otpRoute(phone)) },
            )
        }
        composable(Routes.OTP_VERIFY) { entry ->
            val phone = entry.arguments?.getString("phone").orEmpty()
            OTPVerifyScreen(
                phone = phone,
                onVerified = {
                    navController.navigate(Routes.SCAN) {
                        popUpTo(Routes.PHONE_ENTRY) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.SCAN) {
            ScanScreen(
                onBarcode = { barcode -> navController.navigate(Routes.resultRoute(barcode)) },
                onOpenHistory = { navController.navigate(Routes.HISTORY) },
                onOpenPantry = { navController.navigate(Routes.PANTRY) },
                onOpenProfile = { navController.navigate(Routes.PROFILE) },
            )
        }
        composable(Routes.RESULT) { entry ->
            val barcode = entry.arguments?.getString("barcode").orEmpty()
            ScanResultScreen(
                barcode = barcode,
                onBack = { navController.popBackStack() },
            )
        }
        composable(Routes.HISTORY) {
            HistoryScreen(onOpenResult = { barcode ->
                navController.navigate(Routes.resultRoute(barcode))
            })
        }
        composable(Routes.PANTRY) { PantryScreen() }
        composable(Routes.PROFILE) { ProfileScreen() }
    }
}
