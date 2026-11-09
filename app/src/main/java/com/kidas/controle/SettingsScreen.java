package com.kidas.controle;

import android.app.DatePickerDialog;
import android.text.InputType;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;

final class SettingsScreen extends Screen {
    private String expiry = "";
    private TextView expTv;

    SettingsScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Réglages"; }

    @Override
    void build() {
        expiry = Api.exp;
        LinearLayout c = section("Connexion GitHub");
        c.addView(Ui.label(host, "Jeton (chiffré dans le coffre du téléphone)"));
        final EditText tok = Ui.edit(host, "github_pat_...", Api.tok, 1);
        tok.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        c.addView(tok, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        c.addView(Ui.label(host, "Dépôt des données (privé)"));
        final EditText dr = Ui.edit(host, "proprietaire/depot", Api.data, 1);
        c.addView(dr, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        c.addView(Ui.label(host, "Dépôt du code (public)"));
        final EditText mr = Ui.edit(host, "proprietaire/depot", Api.mgr, 1);
        c.addView(mr, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        c.addView(Ui.label(host, "Date d'expiration du jeton (rappel)"));
        LinearLayout er = Ui.hbox(host);
        expTv = Ui.tv(host, "", 15, Ui.INK, false);
        er.addView(expTv, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        Ui.Btn pick = Ui.btn(host, "Choisir", R.drawable.ic_clock, 0);
        pick.setMinimumHeight(Ui.dp(38));
        pick.setOnClickListener(v -> pickDate());
        er.addView(pick);
        Ui.Btn clr = Ui.btn(host, "", R.drawable.ic_x, 2);
        clr.label.setVisibility(View.GONE);
        clr.setMinimumHeight(Ui.dp(38));
        clr.setOnClickListener(v -> {
            expiry = "";
            showExp();
        });
        er.addView(clr, Ui.lp(Ui.WRAP, Ui.WRAP, 8, 0, 0, 0));
        c.addView(er);
        showExp();

        final LinearLayout res = Ui.vbox(host);
        final Ui.Btn save = Ui.btn(host, "Enregistrer et tester", R.drawable.ic_check, 1);
        save.setOnClickListener(v -> {
            final String t = tok.getText().toString().trim();
            final String d = dr.getText().toString().trim();
            final String m = mr.getText().toString().trim();
            doActR(save, () -> {
                if (t.isEmpty()) throw new Exception("Colle ton jeton.");
                Api.tok = t;
                if (!d.isEmpty()) Api.data = d;
                if (!m.isEmpty()) Api.mgr = m;
                Api.exp = expiry;
                Api.wf = null;
                host.store.set("gh_token", Api.tok);
                host.store.set("cfg_data", Api.data);
                host.store.set("cfg_mgr", Api.mgr);
                if (expiry.isEmpty()) host.store.del("cfg_exp"); else host.store.set("cfg_exp", expiry);
                List<String[]> out = new ArrayList<>();
                String[] names = {"Données : lecture (" + Api.data + ")", "Actions : lecture (" + Api.mgr + ")", "Variables : lecture"};
                for (int i = 0; i < 3; i++) {
                    String msg = "";
                    try {
                        if (i == 0) Api.req("GET", "/repos/" + Api.data + "/contents/README.md", null, null);
                        else if (i == 1) Api.req("GET", "/repos/" + Api.mgr + "/actions/workflows", null, null);
                        else Api.req("GET", "/repos/" + Api.mgr + "/actions/variables", null, null);
                    } catch (Exception e) {
                        msg = Api.hint(e);
                    }
                    out.add(new String[]{names[i], msg});
                }
                return out;
            }, out -> {
                res.removeAllViews();
                for (String[] o : out) {
                    LinearLayout r = Ui.hbox(host);
                    r.setPadding(0, Ui.dp(6), 0, Ui.dp(6));
                    LinearLayout tx = Ui.vbox(host);
                    tx.addView(Ui.tv(host, o[0], 14, Ui.INK, false));
                    if (!o[1].isEmpty()) tx.addView(Ui.tv(host, o[1], 12.5f, Ui.MUTED, false));
                    r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
                    r.addView(Ui.chip(host, o[1].isEmpty() ? "OK" : "Échec", o[1].isEmpty() ? 1 : 3));
                    res.addView(r);
                }
                toast("Réglages enregistrés.", false);
            });
        });
        c.addView(save, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 16, 0, 0));
        c.addView(res, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));
        add(c);

        LinearLayout info = section("Droits du jeton");
        TextView tv = Ui.tv(host, "Sur les deux dépôts : Contents (écriture), Actions (écriture), Variables (écriture). Sans Actions ni Variables, seuls Médias, Publier et Avis fonctionnent.", 14, Ui.INK, false);
        info.addView(tv);
        add(info);

        LinearLayout up = section("Mise à jour de l'application");
        up.addView(Ui.tv(host, "Version installée : " + Updater.versionName(host) + " (" + Updater.versionCode(host) + ")", 14, Ui.INK, false));
        up.addView(switchRow("Vérifier au démarrage", "Cherche une nouvelle version à chaque ouverture", !"0".equals(host.store.get("upd_auto")), v -> {
            if (v) host.store.del("upd_auto"); else host.store.set("upd_auto", "0");
        }), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 6, 0, 0));
        final TextView upMsg = Ui.tv(host, "", 13.5f, Ui.MUTED, false);
        final Ui.Btn chk = Ui.btn(host, "Rechercher une mise à jour", R.drawable.ic_refresh, 0);
        chk.setOnClickListener(v -> doActR(chk, () -> Updater.check(host), inf -> {
            if (inf.available) {
                upMsg.setText("Version " + inf.name + " disponible.");
                new UpdateDialog(host, inf).show();
            } else {
                upMsg.setText("Tu as déjà la dernière version.");
            }
        }));
        up.addView(chk, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));
        up.addView(upMsg, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        add(up);

        LinearLayout sec = section("Sécurité");
        final Ui.Btn out = Ui.btn(host, "Oublier le jeton sur ce téléphone", R.drawable.ic_trash, 2);
        out.setOnClickListener(v -> confirm("Effacer le jeton de ce téléphone ?", () -> {
            host.store.del("gh_token");
            Api.tok = "";
            host.go(MainActivity.HOME);
        }));
        sec.addView(out, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        add(sec);
    }

    private void showExp() {
        expTv.setText(expiry.isEmpty() ? "Aucune date" : expiry);
        expTv.setTextColor(expiry.isEmpty() ? Ui.MUTED : Ui.INK);
    }

    private void pickDate() {
        Calendar c = Calendar.getInstance();
        new DatePickerDialog(host, (dp, y, m, d) -> {
            expiry = String.format(Locale.US, "%04d-%02d-%02d", y, m + 1, d);
            if (alive) showExp();
        }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).show();
    }
}
