package com.kidas.controle;

import android.app.Dialog;
import android.content.pm.PackageInstaller;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;

/** Fenêtre de mise à jour : notes, téléchargement avec progression, installation. */
final class UpdateDialog {
    private static final int IDLE = 0, DOWN = 1, READY = 2, ERR = 3, INST = 4;

    private final MainActivity a;
    private final Updater.Info info;
    private final Dialog dlg;
    private final LinearLayout buttons, progressBox;
    private final TextView status, pTxt;
    private final FrameLayout track;
    private final View fill;
    private File file;

    UpdateDialog(MainActivity act, Updater.Info i) {
        a = act;
        info = i;
        dlg = new Dialog(a);
        dlg.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dlg.setCancelable(!i.mandatory);
        dlg.setCanceledOnTouchOutside(false);

        LinearLayout card = Ui.vbox(a);
        card.setBackground(Ui.roundS(Ui.CARD, Ui.LINE, 20));
        card.setPadding(Ui.dp(20), Ui.dp(20), Ui.dp(20), Ui.dp(16));

        LinearLayout head = Ui.hbox(a);
        head.addView(Ui.icon(a, R.drawable.ic_download, Ui.ACCENT, 22), Ui.lp(Ui.dp(22), Ui.dp(22), 0, 0, 10, 0));
        TextView title = Ui.tv(a, "Mise à jour disponible", 19, Ui.INK, true);
        head.addView(title, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        head.addView(Ui.chip(a, i.mandatory ? "Obligatoire" : "Facultative", i.mandatory ? 3 : 4));
        card.addView(head);

        card.addView(Ui.tv(a, "Version " + i.name + " · installée : " + (i.curName.isEmpty() ? String.valueOf(i.current) : i.curName),
                13.5f, Ui.MUTED, false), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 12));

        String notes = i.notes.isEmpty() ? "Aucune note de version." : i.notes;
        TextView nt = Ui.tv(a, notes, 14, Ui.INK, false);
        nt.setPadding(Ui.dp(14), Ui.dp(12), Ui.dp(14), Ui.dp(12));
        ScrollView sv = new ScrollView(a);
        sv.setBackground(Ui.round(Ui.BG, 12));
        sv.addView(nt);
        card.addView(sv, new LinearLayout.LayoutParams(Ui.MATCH, notes.length() > 160 ? Ui.dp(170) : Ui.WRAP));

        progressBox = Ui.vbox(a);
        track = new FrameLayout(a);
        track.setBackground(Ui.round(Ui.LINE, 99));
        fill = new View(a);
        fill.setBackground(Ui.round(Ui.ACCENT, 99));
        track.addView(fill, new FrameLayout.LayoutParams(0, Ui.MATCH));
        progressBox.addView(track, new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(8)));
        pTxt = Ui.tv(a, "", 12.5f, Ui.MUTED, false);
        progressBox.addView(pTxt, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 6, 0, 0));
        progressBox.setVisibility(View.GONE);
        card.addView(progressBox, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 14, 0, 0));

        status = Ui.tv(a, "", 13.5f, Ui.MUTED, false);
        status.setVisibility(View.GONE);
        card.addView(status, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 12, 0, 0));

        buttons = Ui.hbox(a);
        card.addView(buttons, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 16, 0, 0));

        dlg.setContentView(card);
        Window w = dlg.getWindow();
        if (w != null) {
            w.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            w.setLayout((int) (a.getResources().getDisplayMetrics().widthPixels * 0.92), ViewGroup.LayoutParams.WRAP_CONTENT);
        }
        dlg.setOnDismissListener(d -> {
            Updater.listener = null;
            if (Updater.busy()) Updater.cancel();
        });
        setState(IDLE, null);
    }

    void show() { dlg.show(); }

    /* ---------- états ---------- */

    private void addBtn(String t, int icon, int kind, final Runnable r) {
        Ui.Btn b = Ui.btn(a, t, icon, kind);
        b.setOnClickListener(v -> r.run());
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, Ui.WRAP, 1f);
        if (buttons.getChildCount() > 0) p.leftMargin = Ui.dp(10);
        buttons.addView(b, p);
    }

    private void setState(int s, String msg) {
        buttons.removeAllViews();
        progressBox.setVisibility(s == DOWN ? View.VISIBLE : View.GONE);
        boolean has = msg != null && !msg.isEmpty();
        status.setText(has ? msg : "");
        status.setTextColor(s == ERR ? Ui.BAD : Ui.MUTED);
        status.setVisibility(has ? View.VISIBLE : View.GONE);
        if (s == IDLE) {
            if (!info.mandatory) addBtn("Plus tard", 0, 0, () -> dlg.dismiss());
            addBtn("Télécharger", R.drawable.ic_download, 1, this::startDownload);
        } else if (s == DOWN) {
            progress(0, info.size);
            addBtn("Annuler", R.drawable.ic_x, 2, Updater::cancel);
        } else if (s == READY) {
            if (!info.mandatory) addBtn("Plus tard", 0, 0, () -> dlg.dismiss());
            addBtn("Installer", R.drawable.ic_check, 3, this::install);
        } else if (s == ERR) {
            if (!info.mandatory) addBtn("Fermer", 0, 0, () -> dlg.dismiss());
            addBtn("Réessayer", R.drawable.ic_refresh, 1, this::startDownload);
        }
    }

    private void progress(long done, long total) {
        double r = total > 0 ? Math.min(1.0, (double) done / total) : 0;
        ViewGroup.LayoutParams lp = fill.getLayoutParams();
        lp.width = (int) (track.getWidth() * r);
        fill.setLayoutParams(lp);
        pTxt.setText(total > 0 ? Ui.fsize(done) + " / " + Ui.fsize(total) + " · " + Math.round(r * 100) + " %" : Ui.fsize(done));
    }

    /* ---------- actions ---------- */

    private void startDownload() {
        if (Updater.busy()) {
            a.toast("Un téléchargement est déjà en cours.", true);
            return;
        }
        setState(DOWN, null);
        Api.async(() -> Updater.download(a, info, (done, total) -> Api.MAIN.post(() -> progress(done, total))), f -> {
            file = f;
            setState(READY, "Téléchargement terminé, fichier vérifié (signature et intégrité).");
        }, e -> {
            if (e instanceof Updater.Cancelled) setState(IDLE, "Téléchargement annulé.");
            else setState(ERR, e.getMessage() == null ? e.toString() : e.getMessage());
        });
    }

    private void install() {
        if (file == null || !file.exists()) {
            setState(ERR, "Le fichier a disparu, télécharge-le de nouveau.");
            return;
        }
        if (!Updater.canInstall(a)) {
            setState(READY, "Autorise l'installation depuis KI DAS Contrôle, puis reviens ici et appuie sur Installer.");
            a.markExternal();
            try {
                a.startActivity(Updater.unknownSourcesIntent(a));
            } catch (Exception e) {
                setState(ERR, "Impossible d'ouvrir les réglages d'installation.");
            }
            return;
        }
        setState(INST, "Préparation de l'installation…");
        Updater.listener = (st, msg) -> {
            if (st == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                setState(INST, "Confirme l'installation dans la fenêtre Android.");
            } else if (st == PackageInstaller.STATUS_SUCCESS) {
                dlg.dismiss();
            } else if (st == PackageInstaller.STATUS_FAILURE_ABORTED) {
                setState(READY, "Installation annulée. Tu peux réessayer.");
            } else {
                setState(READY, "Installation refusée" + (msg == null || msg.isEmpty() ? "." : " : " + msg));
            }
        };
        final File f = file;
        Api.async(() -> {
            Updater.install(a, f);
            return null;
        }, r -> { /* la suite arrive par InstallReceiver */ }, e -> setState(READY, "Installation impossible : " + (e.getMessage() == null ? e.toString() : e.getMessage())));
    }
}
