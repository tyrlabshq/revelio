package app.revelio

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

/**
 * Application entry point. `@HiltAndroidApp` bootstraps the DI graph; every
 * `@AndroidEntryPoint` activity, fragment, or service inherits from it.
 */
@HiltAndroidApp
class RevelioApp : Application()
