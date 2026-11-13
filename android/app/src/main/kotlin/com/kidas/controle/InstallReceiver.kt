package com.kidas.controle

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

/** Reçoit le résultat de l'installation (confirmation demandée, échec, annulation). */
class InstallReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        val st = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        if (st == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val conf = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (conf != null) {
                conf.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(conf)
                } catch (e: Exception) {
                    MainActivity.channel?.invokeMethod("installResult",
                        mapOf("status" to PackageInstaller.STATUS_FAILURE,
                            "msg" to "Impossible d'ouvrir l'installateur."))
                    return
                }
            }
        }
        MainActivity.channel?.invokeMethod("installResult",
            mapOf("status" to st, "msg" to msg))
    }
}
