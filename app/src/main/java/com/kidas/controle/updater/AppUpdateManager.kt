package com.kidas.controle.updater

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit

class AppUpdateManager(private val context: Context) {
    companion object {
        const val GITHUB_OWNER = "kidasniger"
        const val GITHUB_REPO = "kidas-controle"
        private const val RELEASE_API = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO/releases/latest"
        private const val APK_FILE = "kidas-controle-update.apk"
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .callTimeout(15, TimeUnit.MINUTES)
        .build()

    private val mutableState = MutableStateFlow<UpdateState>(UpdateState.Idle)
    val state: StateFlow<UpdateState> = mutableState.asStateFlow()

    fun installedVersion(): String = try {
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }
        info.versionName ?: "0.0.0"
    } catch (_: Exception) { "0.0.0" }

    suspend fun checkForUpdates(): UpdateState = withContext(Dispatchers.IO) {
        mutableState.value = UpdateState.Checking
        try {
            val request = Request.Builder().url(RELEASE_API)
                .header("Accept", "application/vnd.github+json")
                .header("X-GitHub-Api-Version", "2022-11-28")
                .header("User-Agent", "KiDas-Controle-Android")
                .build()
            val json = client.newCall(request).execute().use {
                if (!it.isSuccessful) error(if (it.code == 404) "Aucune release publiée pour le moment." else "GitHub a répondu HTTP ${it.code}.")
                requireNotNull(it.body).string()
            }
            val release = GitHubReleaseInfo.fromJson(org.json.JSONObject(json))
            val remoteVersion = release.tagName.removePrefix("v").removePrefix("V")
            val installed = installedVersion()
            val next = if (SemanticVersion.isNewer(remoteVersion, installed)) {
                UpdateState.UpdateAvailable(release, installed)
            } else {
                cleanupIncomplete()
                UpdateState.UpToDate(installed)
            }
            mutableState.value = next
            next
        } catch (e: Exception) {
            UpdateState.Error(e.message ?: "Vérification impossible. Vérifiez votre connexion.")
                .also { mutableState.value = it }
        }
    }

    suspend fun download(release: GitHubReleaseInfo): UpdateState = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "updates").apply { mkdirs() }
        val destination = File(directory, APK_FILE)
        val partial = File(directory, "$APK_FILE.part")
        try {
            if (destination.isFile && destination.length() > 0L &&
                (release.apkSize <= 0L || destination.length() == release.apkSize) &&
                (release.sha256 == null || sha256(destination).equals(release.sha256, true))) {
                return@withContext UpdateState.Downloaded(destination.absolutePath, release.tagName)
                    .also { mutableState.value = it }
            }
            partial.delete()
            val request = Request.Builder().url(release.apkUrl)
                .header("User-Agent", "KiDas-Controle-Android").build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("Échec du téléchargement (HTTP ${response.code}).")
                val body = requireNotNull(response.body) { "Le serveur a envoyé un fichier vide." }
                val total = if (release.apkSize > 0L) release.apkSize else body.contentLength()
                body.byteStream().use { input ->
                    FileOutputStream(partial).use { output ->
                        val buffer = ByteArray(32 * 1024)
                        var received = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            received += count
                            mutableState.value = UpdateState.Downloading(
                                if (total > 0) ((received * 100 / total).toInt().coerceIn(0, 100)) else 0,
                                received, total
                            )
                        }
                        output.fd.sync()
                    }
                }
            }
            if (!partial.isFile || partial.length() == 0L) error("Le fichier téléchargé est vide.")
            if (release.apkSize > 0L && partial.length() != release.apkSize) error("Téléchargement incomplet : taille du fichier incorrecte.")
            val expectedHash = release.sha256 ?: release.checksumUrl?.let { fetchChecksum(it, release.apkName) }
            if (release.checksumUrl != null && expectedHash == null) error("L'empreinte SHA-256 publiée est illisible.")
            if (expectedHash != null && !sha256(partial).equals(expectedHash, true)) {
                error("L'empreinte SHA-256 ne correspond pas. Le fichier a été rejeté.")
            }
            if (!partial.renameTo(destination)) {
                partial.copyTo(destination, overwrite = true)
                partial.delete()
            }
            UpdateState.Downloaded(destination.absolutePath, release.tagName).also { mutableState.value = it }
        } catch (e: Exception) {
            partial.delete()
            destination.delete()
            UpdateState.Error(e.message ?: "Le téléchargement a échoué.")
                .also { mutableState.value = it }
        }
    }

    private fun fetchChecksum(url: String, assetName: String): String? {
        val request = Request.Builder().url(url).header("User-Agent", "KiDas-Controle-Android").build()
        return client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@use null
            val text = response.body?.string().orEmpty()
            val line = text.lineSequence().firstOrNull { it.contains(assetName) || it.trim().matches(Regex("[a-fA-F0-9]{64}")) }
                ?: return@use null
            Regex("[a-fA-F0-9]{64}").find(line)?.value
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it) }
    }

    fun install(apkPath: String, version: String) {
        val apk = File(apkPath)
        if (!apk.isFile || apk.length() == 0L) {
            mutableState.value = UpdateState.Error("Le fichier APK n'est plus disponible.")
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
                val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(settings)
                mutableState.value = UpdateState.Downloaded(apk.absolutePath, version)
                return
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(Intent.EXTRA_RETURN_RESULT, true)
            }
            mutableState.value = UpdateState.Installing(version)
            context.startActivity(intent)
        } catch (e: Exception) {
            mutableState.value = UpdateState.Error("Impossible d'ouvrir l'installateur : ${e.localizedMessage ?: "erreur inconnue"}")
        }
    }

    fun refreshAfterInstaller(expectedVersion: String) {
        val installed = installedVersion()
        mutableState.value = if (runCatching { SemanticVersion.compare(installed, expectedVersion) >= 0 }.getOrDefault(false)) {
            UpdateState.UpToDate(installed)
        } else UpdateState.Error("Installation non terminée. Vous pouvez réessayer depuis les paramètres.")
    }

    fun reset() { mutableState.value = UpdateState.Idle }

    private fun cleanupIncomplete() {
        File(context.cacheDir, "updates").listFiles()?.filter { it.name.endsWith(".part") }?.forEach(File::delete)
    }
}
