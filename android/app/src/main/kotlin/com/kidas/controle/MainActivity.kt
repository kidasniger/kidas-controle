package com.kidas.controle

import android.media.AudioManager
import android.media.ToneGenerator
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/** Pont natif : version installée, vérification APK, installation (PackageInstaller). */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        const val ACTION = "com.kidas.controle.INSTALL_RESULT"
        var channel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kidas/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "legacyKeys" -> result.success(LegacyStore(this).keys())
                "legacyGet" -> result.success(LegacyStore(this).get(call.argument<String>("key") ?: ""))
                "versionCode" -> result.success(versionCode())
                "versionName" -> result.success(versionName())
                "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                "openUnknownSources" -> try {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("x", "Impossible d'ouvrir les réglages.", null)
                }
                "verify" -> try {
                    verify(call.argument<String>("path")!!, call.argument<Int>("code")!!)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("verify", e.message ?: "APK refusé.", null)
                }
                "install" -> try {
                    install(File(call.argument<String>("path")!!))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install", e.message ?: "Installation impossible.", null)
                }
                "beep" -> try {
                    beep(call.argument<String>("kind") ?: "tick")
                    result.success(null)
                } catch (e: Exception) {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /* ---------- son court (40 ms), hors thread UI ---------- */

    private fun beep(kind: String) {
        Thread {
            try {
                val tg = ToneGenerator(AudioManager.STREAM_MUSIC, 50)
                val tone = when (kind) {
                    "ok" -> ToneGenerator.TONE_PROP_BEEP
                    "err" -> ToneGenerator.TONE_PROP_NACK
                    else -> ToneGenerator.TONE_PROP_BEEP2
                }
                tg.startTone(tone, 40)
                Thread.sleep(250)
                tg.release()
            } catch (e: Exception) { /* son facultatif */ }
        }.start()
    }

    /* ---------- version installée ---------- */

    private fun versionCode(): Int = try {
        val p = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) p.longVersionCode.toInt() else p.versionCode
    } catch (e: Exception) { 0 }

    private fun versionName(): String = try {
        packageManager.getPackageInfo(packageName, 0).versionName ?: ""
    } catch (e: Exception) { "" }

    /* ---------- vérification (port de Updater.verify) ---------- */

    @Suppress("DEPRECATION")
    private fun signers(p: PackageInfo): Array<Signature>? =
        if (Build.VERSION.SDK_INT >= 28) p.signingInfo?.apkContentsSigners else p.signatures

    private fun same(a: Array<Signature>?, b: Array<Signature>?): Boolean {
        if (a == null || b == null || a.isEmpty() || a.size != b.size) return false
        for (x in a) {
            var ok = false
            for (y in b) if (x == y) { ok = true; break }
            if (!ok) return false
        }
        return true
    }

    /** Paquet, version et signature : refuse tout APK qui n'est pas un vrai successeur. */
    private fun verify(path: String, code: Int) {
        val fl = if (Build.VERSION.SDK_INT >= 28)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val n = packageManager.getPackageArchiveInfo(path, fl)
            ?: throw Exception("APK illisible ou corrompu.")
        if (n.packageName != packageName) {
            throw Exception("Cet APK n'est pas celui de l'application.")
        }
        val vc = if (Build.VERSION.SDK_INT >= 28) n.longVersionCode.toInt() else n.versionCode
        if (vc != code) throw Exception("La version de l'APK ne correspond pas à celle annoncée.")
        if (vc <= versionCode()) {
            throw Exception("Cet APK n'est pas plus récent que la version installée.")
        }
        val self = packageManager.getPackageInfo(packageName, fl)
        if (!same(signers(n), signers(self))) {
            throw Exception("Signature différente : installation refusée.")
        }
    }

    /* ---------- installation (port de Updater.install) ---------- */

    private fun install(apk: File) {
        val pi = packageManager.packageInstaller
        val sp = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        sp.setAppPackageName(packageName)
        val id = pi.createSession(sp)
        val s = pi.openSession(id)
        try {
            val out = s.openWrite("base.apk", 0, apk.length())
            try {
                FileInputStream(apk).use { ins -> ins.copyTo(out) }
                s.fsync(out)
            } finally {
                out.close()
            }
            val intent = Intent(this, InstallReceiver::class.java).setAction(ACTION)
            val fl = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pend = PendingIntent.getBroadcast(this, id, intent, fl)
            s.commit(pend.intentSender)
        } catch (e: Exception) {
            s.abandon()
            throw e
        } finally {
            s.close()
        }
    }
}
