package com.kidas.controle;

import android.app.AlertDialog;
import android.view.Gravity;
import android.view.View;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Base d'un écran natif : remplit `root`, charge ses données en arrière-plan. */
abstract class Screen {
    interface BoolJob { void run(boolean v) throws Exception; }

    final MainActivity host;
    LinearLayout root;
    boolean alive = true;
    int rc = 0;

    Screen(MainActivity h) { host = h; }

    abstract void build();

    abstract String title();

    void destroy() { alive = false; }

    /* ---------- ajout de vues ---------- */

    void add(View v) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP);
        p.bottomMargin = Ui.dp(14);
        root.addView(v, p);
        Ui.reveal(v, rc++);
    }

    void clearAll() {
        root.removeAllViews();
        rc = 0;
    }

    void skeletons(int n) {
        for (int i = 0; i < n; i++) add(Ui.skeleton(host, i == 0 ? 120 : 90));
    }

    void toast(String m, boolean bad) { host.toast(m, bad); }

    <T> void load(Api.Job<T> j, final Api.Ok<T> ok, final Api.Err er) {
        Api.async(j, v -> {
            if (alive && ok != null) ok.ok(v);
        }, e -> {
            if (alive && er != null) er.err(e);
        });
    }

    <T> void doAct(final Ui.Btn b, Api.Job<T> job, final String okMsg, final Runnable after) {
        if (!b.isEnabled()) return;
        b.setBusy(true);
        Api.async(job, r -> {
            b.setBusy(false);
            if (okMsg != null) toast(okMsg, false);
            if (alive && after != null) after.run();
        }, e -> {
            b.setBusy(false);
            toast(Api.hint(e), true);
        });
    }

    /** Comme doAct, mais le résultat du travail est remis à `ok`. */
    <T> void doActR(final Ui.Btn b, Api.Job<T> job, final Api.Ok<T> ok) {
        if (!b.isEnabled()) return;
        b.setBusy(true);
        Api.async(job, r -> {
            b.setBusy(false);
            if (alive && ok != null) ok.ok(r);
        }, e -> {
            b.setBusy(false);
            toast(Api.hint(e), true);
        });
    }

    void confirm(String msg, final Runnable yes) {
        new AlertDialog.Builder(host)
                .setMessage(msg)
                .setPositiveButton("OK", (d, w) -> yes.run())
                .setNegativeButton("Annuler", null)
                .show();
    }

    /* ---------- composants ---------- */

    LinearLayout section(String title) {
        LinearLayout c = Ui.card(host);
        c.addView(Ui.h2(host, title), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 12));
        return c;
    }

    View errBox(Exception e) {
        TextView t = Ui.tv(host, "Erreur : " + Api.hint(e), 14, Ui.INK, false);
        t.setBackground(Ui.round(Ui.BADBG, 12));
        t.setPadding(Ui.dp(14), Ui.dp(12), Ui.dp(14), Ui.dp(12));
        return t;
    }

    View note(String bold, String rest) {
        TextView t = Ui.tv(host, bold + rest, 14, Ui.INK, false);
        t.setBackground(Ui.round(Ui.WARNBG, 12));
        t.setPadding(Ui.dp(14), Ui.dp(12), Ui.dp(14), Ui.dp(12));
        return t;
    }

    View empty(String msg) {
        TextView t = Ui.tv(host, msg, 14, Ui.MUTED, false);
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, Ui.dp(18), 0, Ui.dp(18));
        return t;
    }

    View divider() {
        View v = new View(host);
        v.setBackgroundColor(Ui.LINE);
        v.setLayoutParams(Ui.lp(Ui.MATCH, 1, 0, 10, 0, 10));
        return v;
    }

    View switchRow(final String label, String desc, boolean checked, final BoolJob job) {
        final LinearLayout row = Ui.hbox(host);
        row.setPadding(0, Ui.dp(8), 0, Ui.dp(8));
        LinearLayout txt = Ui.vbox(host);
        txt.addView(Ui.tv(host, label, 15, Ui.INK, true));
        if (desc != null && !desc.isEmpty()) txt.addView(Ui.tv(host, desc, 12.5f, Ui.MUTED, false));
        row.addView(txt, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        final ToggleView tg = new ToggleView(host);
        tg.setChecked(checked, false);
        tg.setOnToggle(v -> {
            row.setAlpha(0.5f);
            tg.setEnabled(false);
            Api.async(() -> {
                job.run(v);
                return null;
            }, r -> {
                row.setAlpha(1f);
                tg.setEnabled(true);
                toast(label + " : " + (v ? "activé" : "désactivé"), false);
            }, e -> {
                tg.setChecked(!v, true);
                row.setAlpha(1f);
                tg.setEnabled(true);
                toast(Api.hint(e), true);
            });
        });
        row.addView(tg, Ui.lp(Ui.WRAP, Ui.WRAP, 12, 0, 0, 0));
        return row;
    }

    /** Ligne d'exécution GitHub Actions. */
    View runRow(final org.json.JSONObject r, boolean withCancel, final Runnable after) {
        LinearLayout row = Ui.hbox(host);
        row.setPadding(0, Ui.dp(8), 0, Ui.dp(8));
        LinearLayout t = Ui.vbox(host);
        String name = r.optString("name", r.optString("display_title", ""));
        t.addView(Ui.tv(host, name, 14.5f, Ui.INK, true));
        String d = "";
        if ("completed".equals(r.optString("status")) && !r.optString("run_started_at").isEmpty()) {
            long a = Ui.iso(r.optString("run_started_at")), b = Ui.iso(r.optString("updated_at"));
            if (a > 0 && b >= a) d = " · " + Ui.dur(b - a);
        }
        t.addView(Ui.tv(host, Ui.rel(r.optString("created_at")) + d, 12.5f, Ui.MUTED, false));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.addView(runChip(r));
        if (withCancel && !"completed".equals(r.optString("status"))) {
            final Ui.Btn x = Ui.btn(host, "", R.drawable.ic_x, 2);
            x.label.setVisibility(View.GONE);
            x.setPadding(Ui.dp(10), 0, Ui.dp(10), 0);
            x.setMinimumHeight(Ui.dp(36));
            final long id = r.optLong("id");
            x.setOnClickListener(v -> doAct(x, () -> {
                Api.cancelRun(id);
                Thread.sleep(800);
                return null;
            }, "Annulation demandée.", after));
            row.addView(x, Ui.lp(Ui.WRAP, Ui.WRAP, 8, 0, 0, 0));
        }
        return row;
    }

    View runChip(org.json.JSONObject r) {
        String st = r.optString("status");
        if (!"completed".equals(st)) return Ui.chip(host, "queued".equals(st) ? "En file" : "En cours", 4);
        String c = r.optString("conclusion");
        if ("success".equals(c)) return Ui.chip(host, "Réussi", 1);
        if ("failure".equals(c) || "timed_out".equals(c)) return Ui.chip(host, "Échec", 3);
        if ("cancelled".equals(c)) return Ui.chip(host, "Annulé", 0);
        return Ui.chip(host, "skipped".equals(c) ? "Ignoré" : (c.isEmpty() ? "?" : c), 0);
    }
}
