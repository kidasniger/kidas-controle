package com.kidas.controle

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.kidas.controle.ui.settings.UpdateSettingsScreen
import com.kidas.controle.ui.theme.KiDasTheme
import com.kidas.controle.updater.AppUpdateManager
import com.kidas.controle.updater.UpdateState

class MainActivity : ComponentActivity() {
    private lateinit var updateManager: AppUpdateManager

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        updateManager = AppUpdateManager(applicationContext)

        setContent {
            KiDasTheme {
                UpdateSettingsScreen(manager = updateManager)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (::updateManager.isInitialized) {
            val installing = updateManager.state.value as? UpdateState.Installing
            if (installing != null) updateManager.refreshAfterInstaller(installing.version)
        }
    }
}
