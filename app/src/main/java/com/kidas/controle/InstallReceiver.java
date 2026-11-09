package com.kidas.controle;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;

/** Reçoit le résultat de l'installation (confirmation demandée, échec, annulation). */
public class InstallReceiver extends BroadcastReceiver {
    @Override
    @SuppressWarnings("deprecation")
    public void onReceive(Context c, Intent i) {
        int st = i.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
        String msg = i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
        if (st == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent conf = i.getParcelableExtra(Intent.EXTRA_INTENT);
            if (conf != null) {
                conf.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    c.startActivity(conf);
                } catch (Exception e) {
                    Updater.notifyResult(PackageInstaller.STATUS_FAILURE, "Impossible d'ouvrir l'installateur.");
                    return;
                }
            }
        }
        Updater.notifyResult(st, msg);
    }
}
