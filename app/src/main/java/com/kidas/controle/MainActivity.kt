package com.kidas.controle

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
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
                var showSettings by rememberSaveable { mutableStateOf(false) }
                val updateState by updateManager.state.collectAsState()

                // Vérification silencieuse au démarrage : elle ne remplace jamais l'écran principal.
                LaunchedEffect(Unit) { updateManager.checkForUpdates() }

                if (showSettings) {
                    UpdateSettingsScreen(
                        manager = updateManager,
                        onBack = { showSettings = false }
                    )
                } else {
                    Scaffold { contentPadding ->
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(contentPadding)
                                .padding(24.dp),
                            verticalArrangement = Arrangement.spacedBy(20.dp)
                        ) {
                            Text("KI DAS", style = MaterialTheme.typography.headlineLarge)
                            Text(
                                "Bienvenue dans KI DAS Contrôle",
                                style = MaterialTheme.typography.titleMedium
                            )

                            if (updateState is UpdateState.UpdateAvailable) {
                                val available = updateState as UpdateState.UpdateAvailable
                                Card(Modifier.fillMaxWidth()) {
                                    Column(
                                        Modifier.padding(16.dp),
                                        verticalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Text("Mise à jour disponible", style = MaterialTheme.typography.titleMedium)
                                        Text("Version ${available.release.tagName} prête à être consultée.")
                                        Button(onClick = { showSettings = true }) {
                                            Text("Voir la mise à jour")
                                        }
                                    }
                                }
                            } else if (updateState is UpdateState.Checking) {
                                Text("Vérification des mises à jour en arrière-plan…")
                            }

                            Spacer(Modifier.weight(1f))
                            Button(
                                onClick = { showSettings = true },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text("Paramètres")
                            }
                        }
                    }
                }
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
