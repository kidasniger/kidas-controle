package com.kidas.controle

import android.app.KeyguardManager
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
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
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.kidas.controle.security.LockScreen
import com.kidas.controle.security.SecureTokenRepository
import com.kidas.controle.security.TokenVault
import com.kidas.controle.security.WelcomeSetupScreen
import com.kidas.controle.ui.theme.KiDasThemeMode
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
    private var pendingCredentialCipher: javax.crypto.Cipher? = null
    private var credentialCallback: ((Boolean, javax.crypto.Cipher?) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        updateManager = AppUpdateManager(applicationContext)
        vault = TokenVault(applicationContext)
        tokenRepository = SecureTokenRepository(vault)

        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = android.graphics.Color.TRANSPARENT
        window.navigationBarColor = android.graphics.Color.TRANSPARENT
        setContent {
            val prefs = remember { getSharedPreferences("kidas_preferences", MODE_PRIVATE) }
            var themeMode by remember {
                mutableStateOf(
                    runCatching {
                        KiDasThemeMode.valueOf(prefs.getString("theme_mode", "DARK") ?: "DARK")
                    }.getOrDefault(KiDasThemeMode.DARK)
                )
            }
            com.kidas.controle.ui.theme.KiDasTheme(mode = themeMode) {
                // Surface fournit une couleur de contenu lisible à tous les écrans,
                // y compris le verrouillage et l'assistant de première configuration.
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground
                ) {
                    var unlocked by rememberSaveable { mutableStateOf(!vault.hasCredential()) }
                    var welcome by rememberSaveable { mutableStateOf(!vault.hasCredential()) }
                    var lockError by remember { mutableStateOf<String?>(null) }

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
                                    runCatching { tokenRepository.prepareCredential(token, dataRepo, managerRepo, parsedExpiry) }
                                        .onFailure { lockError = "Jeton ou dépôt invalide."; return@WelcomeSetupScreen }
                                    authenticate("Sécuriser le jeton", cipher) { success, authenticatedCipher ->
                                        if (success && authenticatedCipher != null) saveCredential(
                                            authenticatedCipher,
                                            onSuccess = { welcome = false; unlocked = true; lockError = null },
                                            onError = { lockError = it }
                                        ) else {
                                            lifecycleScope.launch { tokenRepository.discardPending() }
                                            lockError = "Authentification annulée ou échouée. Réessaie."
                                        }
                                    }
                                }
                            },
                            onUseDeviceCredential = { token, dataRepo, managerRepo, expiry ->
                                val parsedExpiry = runCatching {
                                    if (expiry.isBlank()) null else SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
                                        .parse(expiry)?.time?.plus(86_399_999L)
                                }.getOrNull()
                                if (expiry.isNotBlank() && parsedExpiry == null) lockError = "Date d’expiration invalide (AAAA-MM-JJ)."
                                else {
                                    val cipher = runCatching { vault.createEncryptCipher() }.getOrElse {
                                        lockError = "Impossible de créer la clé sécurisée."; return@WelcomeSetupScreen
                                    }
                                    runCatching { tokenRepository.prepareCredential(token, dataRepo, managerRepo, parsedExpiry) }
                                        .onFailure { lockError = "Jeton ou dépôt invalide."; return@WelcomeSetupScreen }
                                    requestDeviceCredential(cipher) { ok, authCipher ->
                                        if (ok && authCipher != null) saveCredential(
                                            authCipher,
                                            onSuccess = { welcome = false; unlocked = true; lockError = null },
                                            onError = { lockError = it }
                                        ) else {
                                            lifecycleScope.launch { tokenRepository.discardPending() }
                                            lockError = "Vérification du code annulée ou échouée."
                                        }
                                    }
                                }
                            }
                        )
                        !unlocked -> LockScreen(
                            onUnlock = {
                                val cipher = runCatching { vault.createDecryptCipher() }.getOrElse {
                                    lockError = when (it) { is java.security.UnrecoverableKeyException, is android.security.keystore.KeyPermanentlyInvalidatedException -> "La clé de sécurité Android a été invalidée. Une nouvelle configuration sécurisée est nécessaire."; else -> "Le verrouillage sécurisé Android est temporairement indisponible. Réessaie." }; return@LockScreen
                                }
                                authenticate("Déverrouiller KI DAS", cipher) { success, result ->
                                    if (success && result != null) unlockWith(result) { unlocked = true; lockError = null }
                                    else finishAndRemoveTask()
                                }
                            },
                            onUseDeviceCredential = {
                                val cipher = runCatching { vault.createDecryptCipher() }.getOrElse {
                                    finishAndRemoveTask(); return@LockScreen
                                }
                                requestDeviceCredential(cipher) { ok, result ->
                                    if (ok && result != null) unlockWith(result) { unlocked = true; lockError = null }
                                    else finishAndRemoveTask()
                                }
                            },
                            showDeviceCredential = android.os.Build.VERSION.SDK_INT < 30,
                            error = lockError
                        )
                        else -> {
                            LaunchedEffect(Unit) { updateManager.checkForUpdates() }
                            com.kidas.controle.ui.nav.KiDasNavigation(
                                manager = updateManager,
                                tokenRepository = tokenRepository,
                                themeMode = themeMode,
                                onThemeModeChange = {
                                    themeMode = it
                                    prefs.edit().putString("theme_mode", it.name).apply()
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private fun saveCredential(
        cipher: javax.crypto.Cipher, onSuccess: () -> Unit, onError: (String) -> Unit
    ) {
        lifecycleScope.launch {
            runCatching { tokenRepository.storePreparedAuthenticated(cipher) }
                .onSuccess { onSuccess() }
                .onFailure {
                    tokenRepository.discardPending()
                    onError("Enregistrement sécurisé impossible. Vérifie l’authentification et réessaie.")
                }
        }
    }

    private fun unlockWith(cipher: javax.crypto.Cipher, onUnlocked: () -> Unit) {
        lifecycleScope.launch {
            runCatching { tokenRepository.acceptAuthenticated(cipher) }
                .onSuccess { onUnlocked() }
                .onFailure { finishAndRemoveTask() }
        }
    }

    private fun authenticate(title: String, cipher: javax.crypto.Cipher, callback: (Boolean, javax.crypto.Cipher?) -> Unit) {
        val authenticators = if (android.os.Build.VERSION.SDK_INT >= 30)
            BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        else BiometricManager.Authenticators.BIOMETRIC_STRONG
        if (BiometricManager.from(this).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            callback(false, null); return
        }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    callback(true, result.cryptoObject?.cipher)
                }
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { callback(false, null) }
                override fun onAuthenticationFailed() { }
            })
        val info = BiometricPrompt.PromptInfo.Builder().setTitle(title)
            .setSubtitle("Authentification requise pour protéger votre compte GitHub")
            .setAllowedAuthenticators(authenticators).build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    @Suppress("DEPRECATION")
    private fun requestDeviceCredential(cipher: javax.crypto.Cipher, callback: (Boolean, javax.crypto.Cipher?) -> Unit) {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            callback(false, null); return
        }
        val keyguard = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        val intent: Intent = keyguard.createConfirmDeviceCredentialIntent(
            "Déverrouiller KI DAS", "Confirme le code ou schéma de ton téléphone"
        ) ?: run { callback(false, null); return }
        pendingCredentialCipher = cipher
        credentialCallback = callback
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_DEVICE_CREDENTIAL)
    }

    @Deprecated("Legacy device credential confirmation for Android 8–10")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_DEVICE_CREDENTIAL) {
            val callback = credentialCallback
            val cipher = pendingCredentialCipher
            credentialCallback = null
            pendingCredentialCipher = null
            callback?.invoke(resultCode == RESULT_OK, if (resultCode == RESULT_OK) cipher else null)
        }
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

    companion object { private const val REQUEST_DEVICE_CREDENTIAL = 901 }
}
