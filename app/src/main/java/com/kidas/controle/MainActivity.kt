package com.kidas.controle

import android.os.Bundle
import android.os.SystemClock
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.kidas.controle.security.LockScreen
import com.kidas.controle.security.SecureTokenRepository
import com.kidas.controle.security.TokenVault
import com.kidas.controle.security.WelcomeSetupScreen
import com.kidas.controle.ui.settings.UpdateSettingsScreen
import com.kidas.controle.ui.theme.KiDasTheme
import com.kidas.controle.updater.AppUpdateManager
import com.kidas.controle.updater.UpdateState
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Locale

class MainActivity : FragmentActivity() {
    private lateinit var updateManager: AppUpdateManager
    private lateinit var vault: TokenVault
    private lateinit var tokenRepository: SecureTokenRepository
    private var backgroundAt: Long? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        updateManager = AppUpdateManager(applicationContext)
        vault = TokenVault(applicationContext)
        tokenRepository = SecureTokenRepository(vault)

        setContent {
            KiDasTheme {
                var showSettings by rememberSaveable { mutableStateOf(false) }
                var unlocked by rememberSaveable { mutableStateOf(!vault.hasCredential()) }
                var welcome by rememberSaveable { mutableStateOf(!vault.hasCredential()) }
                var lockError by remember { mutableStateOf<String?>(null) }
                val updateState by updateManager.state.collectAsState()

                SideEffect {
                    if (showSettings) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                LaunchedEffect(Unit) { updateManager.checkForUpdates() }

                when {
                    welcome -> WelcomeSetupScreen(
                        deviceSecure = vault.canUseDeviceAuthentication(),
                        error = lockError,
                        onSave = { token, dataRepo, managerRepo, expiry ->
                            val parsedExpiry = runCatching {
                                if (expiry.isBlank()) null else SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
                                    .parse(expiry)?.time?.plus(86_399_999L)
                            }.getOrNull()
                            if (expiry.isNotBlank() && parsedExpiry == null) {
                                lockError = "Date d’expiration invalide (AAAA-MM-JJ)."
                            } else {
                                val cipher = runCatching { vault.createEncryptCipher() }.getOrElse {
                                    lockError = "Impossible de créer la clé sécurisée. Vérifie le verrouillage Android."
                                    return@WelcomeSetupScreen
                                }
                                authenticate("Sécuriser le jeton", cipher) { success, authenticatedCipher ->
                                    if (success && authenticatedCipher != null) {
                                        lifecycleScope.launch {
                                            runCatching {
                                                tokenRepository.storeAuthenticated(
                                                    authenticatedCipher, token, dataRepo, managerRepo, parsedExpiry
                                                )
                                            }.onSuccess {
                                                welcome = false
                                                unlocked = true
                                                lockError = null
                                            }.onFailure { lockError = "Enregistrement sécurisé impossible." }
                                        }
                                    } else lockError = "Authentification annulée ou échouée. Réessaie."
                                }
                            }
                        }
                    )
                    !unlocked -> LockScreen(
                        onUnlock = {
                            val cipher = runCatching { vault.createDecryptCipher() }.getOrElse {
                                lockError = "Impossible de préparer le déverrouillage."
                                return@LockScreen
                            }
                            authenticate("Déverrouiller KI DAS", cipher) { success, result ->
                                if (success && result != null) {
                                    lifecycleScope.launch {
                                        runCatching { tokenRepository.acceptAuthenticated(result) }
                                            .onSuccess { unlocked = true; lockError = null }
                                            .onFailure { finishAndRemoveTask() }
                                    }
                                } else finishAndRemoveTask()
                            }
                        },
                        error = lockError
                    )
                    showSettings -> UpdateSettingsScreen(updateManager) { showSettings = false }
                    else -> Scaffold { padding ->
                        Column(
                            Modifier.fillMaxSize().padding(padding).padding(24.dp),
                            verticalArrangement = Arrangement.spacedBy(20.dp)
                        ) {
                            Text("KI DAS", style = MaterialTheme.typography.headlineLarge)
                            Text("Bienvenue dans KI DAS Contrôle", style = MaterialTheme.typography.titleMedium)
                            if (updateState is UpdateState.UpdateAvailable) {
                                val available = updateState as UpdateState.UpdateAvailable
                                Card(Modifier.fillMaxWidth()) {
                                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        Text("Mise à jour disponible", style = MaterialTheme.typography.titleMedium)
                                        Text("Version ${available.release.tagName} prête à être consultée.")
                                        Button(onClick = { showSettings = true }) { Text("Voir la mise à jour") }
                                    }
                                }
                            } else if (updateState is UpdateState.Checking) {
                                Text("Vérification des mises à jour en arrière-plan…")
                            }
                            Spacer(Modifier.weight(1f))
                            Button(onClick = { showSettings = true }, modifier = Modifier.fillMaxWidth()) {
                                Text("Paramètres")
                            }
                        }
                    }
                }
            }
        }
    }

    private fun authenticate(title: String, cipher: javax.crypto.Cipher, callback: (Boolean, javax.crypto.Cipher?) -> Unit) {
        val authenticators = if (android.os.Build.VERSION.SDK_INT >= 30) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else BiometricManager.Authenticators.BIOMETRIC_STRONG

        if (BiometricManager.from(this).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            callback(false, null)
            return
        }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    callback(true, result.cryptoObject?.cipher)
                }
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    callback(false, null)
                }
                override fun onAuthenticationFailed() { /* L’utilisateur peut réessayer. */ }
            })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("Authentification requise pour protéger votre compte GitHub")
            .setAllowedAuthenticators(authenticators)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    override fun onStop() {
        if (!isChangingConfigurations) backgroundAt = SystemClock.elapsedRealtime()
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        val elapsed = backgroundAt?.let { SystemClock.elapsedRealtime() - it }
        if (elapsed != null && elapsed >= 60_000L && ::tokenRepository.isInitialized) {
            lifecycleScope.launch { tokenRepository.lock() }
            recreate()
        }
        backgroundAt = null
    }

    override fun onResume() {
        super.onResume()
        if (::updateManager.isInitialized) {
            val installing = updateManager.state.value as? UpdateState.Installing
            if (installing != null) updateManager.refreshAfterInstaller(installing.version)
        }
    }
}
