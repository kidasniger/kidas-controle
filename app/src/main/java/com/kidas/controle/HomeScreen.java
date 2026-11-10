package com.kidas.controle;

import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;

final class HomeScreen extends Screen {
    HomeScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Centre de contrôle"; }

    @Override
    void build() {
        skeletons(4);
        load(Api::dash, this::render, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render(Api.Dash d) {
        clearAll();
        /* rappel d'expiration du jeton */
        if (!Api.exp.isEmpty()) {
            long end = Ui.iso(Api.exp);
            if (end > 0) {
                long days = (long) Math.ceil((end + 86399000L - System.currentTimeMillis()) / 86400000.0);
                if (days <= 30) {
                    add(note(days < 0 ? "Jeton expiré. " : "Jeton : expire dans " + days + " j. ",
                            "Recrée-le puis remets-le dans DATA_PAT et ARCHIVE_TOKEN (dépôt facebook-manager) et dans Réglages."));
                }
            }
        }
        /* héro bot */
        if (d.bot != null) {
            final Api.Bot bs = d.bot;
            LinearLayout hero = Ui.hero(host);
            LinearLayout r = Ui.hbox(host);
            PulseDot dot = new PulseDot(host);
            String t, s;
            if ("on".equals(bs.state)) { t = "Le bot est en marche"; s = "Une session GLM Live tourne."; }
            else if ("wait".equals(bs.state)) { t = "Actif, en attente de session"; s = "La veille lance une session dans les 10 minutes."; }
            else { t = "Le bot est arrêté"; s = bs.hardOff ? "Variable GLM_LIVE = off." : "Désactivé dans glm/config.json."; }
            dot.set("off".equals(bs.state) ? Ui.HSUB : Ui.BG, !"off".equals(bs.state));
            r.addView(dot);
            LinearLayout tx = Ui.vbox(host);
            tx.addView(Ui.tv(host, t, 18, Ui.BG, true));
            tx.addView(Ui.tv(host, s, 13, Ui.HSUB, false));
            r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
            Ui.Btn g = Ui.btn(host, "Gérer", 0, 0);
            g.setMinimumHeight(Ui.dp(38));
            g.setOnClickListener(v -> host.go(MainActivity.BOT));
            r.addView(g);
            hero.addView(r);
            add(hero);
        } else if (!d.errs.isEmpty()) {
            add(errBox(d.errs.get(0)));
        }
        /* chiffres */
        JSONObject page = d.st == null ? null : d.st.optJSONObject("page");
        if (page == null && d.cm != null) page = d.cm.optJSONObject("page");
        if (page == null) page = new JSONObject();
        String pid = Api.pageId(d.st, d.cm);
        List<Api.Cmt> un = Api.unanswered(Api.flatComments(d.cm), pid);
        host.badge(un.size());
        LinearLayout k1 = Ui.kpi(host, R.drawable.ic_users, Ui.ACCENT, "Abonnés");
        LinearLayout k2 = Ui.kpi(host, R.drawable.ic_heart, Ui.MUTED, "J'aime la Page");
        LinearLayout k3 = Ui.kpi(host, R.drawable.ic_chat, Ui.MUTED, "Sans réponse");
        LinearLayout k4 = Ui.kpi(host, R.drawable.ic_clock, Ui.ACCENT, "En attente");
        fill(k1, page.has("followers_count") ? page.optDouble("followers_count") : -1);
        fill(k2, page.has("fan_count") ? page.optDouble("fan_count") : -1);
        fill(k3, d.cm == null ? -1 : un.size());
        fill(k4, Api.sum(d.pending));
        k3.setOnClickListener(v -> host.go(MainActivity.COMMENTS));
        k4.setOnClickListener(v -> host.go(MainActivity.PUBLISH));
        Ui.press(k3);
        Ui.press(k4);
        LinearLayout g1 = Ui.row2(host, k1, k2), g2 = Ui.row2(host, k3, k4);
        add(g1);
        add(g2);
        /* courbe de la métrique principale */
        List<Api.Metric> ms = Api.metrics(d.st);
        if (!ms.isEmpty()) {
            Api.Metric m = ms.get(0);
            LinearLayout c = section(m.name + " · 7 jours");
            LineChartView ch = new LineChartView(host);
            c.addView(ch, new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(150)));
            ch.setData(m.vals, m.labs, Ui.ACCENT);
            TextView more = Ui.tv(host, "Toutes les courbes dans l'onglet Stats", 13, Ui.ACCENT, true);
            more.setPadding(0, Ui.dp(10), 0, 0);
            more.setOnClickListener(v -> host.go(MainActivity.STATS));
            c.addView(more);
            add(c);
        }
        /* actions rapides */
        LinearLayout qa = section("Actions rapides");
        String[][] acts = {{"Audit complet", "audit"}, {"Statistiques", "statistiques.yml"}, {"Surveiller", "surveiller.yml"}, {"Traiter les files", "dispatcher.yml"}};
        LinearLayout rowA = null;
        for (int i = 0; i < acts.length; i++) {
            final String[] a = acts[i];
            final Ui.Btn b = Ui.btn(host, a[0], R.drawable.ic_play, 0);
            b.setOnClickListener(v -> doAct(b, () -> {
                if ("audit".equals(a[1])) Api.startAudit(); else Api.dispatch(a[1], null);
                Thread.sleep(1500);
                return null;
            }, a[0] + " lancé.", host::refresh));
            if (i % 2 == 0) {
                rowA = new LinearLayout(host);
                rowA.setOrientation(LinearLayout.HORIZONTAL);
                qa.addView(rowA, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 0, 0, 8));
                rowA.addView(b, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
            } else {
                rowA.addView(b, Ui.lp(0, Ui.WRAP, 8, 0, 0, 0));
                ((LinearLayout.LayoutParams) b.getLayoutParams()).weight = 1f;
            }
        }
        add(qa);
        /* exécutions */
        JSONArray rn = d.runs;
        if (rn != null && rn.length() > 0) {
            LinearLayout c = section("Dernières exécutions");
            for (int i = 0; i < Math.min(8, rn.length()); i++) {
                JSONObject r = rn.optJSONObject(i);
                if (r == null) continue;
                if (i > 0) c.addView(divider());
                c.addView(runRow(r, false, null));
            }
            add(c);
        }
    }

    private void fill(LinearLayout k, double v) {
        TextView t = Ui.kpiValue(k);
        if (v < 0) t.setText("-"); else Ui.countUp(t, v);
    }
}
