package com.kidas.controle;

import android.view.Gravity;
import android.view.View;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

final class StatsScreen extends Screen {
    private List<Api.Metric> ms = new ArrayList<>();
    private LineChartView chart;
    private TextView bigVal;
    private LinearLayout deltaBox, statsRow;
    private final List<TextView> chips = new ArrayList<>();

    StatsScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Statistiques"; }

    @Override
    void build() {
        skeletons(5);
        load(Api::dash, this::render, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render(final Api.Dash d) {
        clearAll();
        ms = Api.metrics(d.st);
        JSONObject page = d.st == null ? null : d.st.optJSONObject("page");
        if (page == null && d.cm != null) page = d.cm.optJSONObject("page");
        if (page == null) page = new JSONObject();
        String pid = Api.pageId(d.st, d.cm);
        List<Api.Cmt> all = Api.flatComments(d.cm);
        List<Api.Cmt> un = Api.unanswered(all, pid);
        host.badge(un.size());

        /* grand chiffre */
        LinearLayout hero = new LinearLayout(host);
        hero.setOrientation(LinearLayout.VERTICAL);
        hero.setBackground(Ui.gradient(0xFF1D3FA6, 0xFF6D3FD1, 20));
        hero.setPadding(Ui.dp(20), Ui.dp(18), Ui.dp(20), Ui.dp(18));
        hero.addView(Ui.tv(host, "ABONNÉS", 12, 0xCCFFFFFF, true));
        TextView big = Ui.tv(host, "-", 46, 0xFFFFFFFF, true);
        hero.addView(big);
        if (page.has("followers_count")) Ui.countUp(big, page.optDouble("followers_count"));
        String sub = page.has("fan_count") ? Ui.nf(page.optDouble("fan_count")) + " J'aime sur la Page" : "";
        if (d.st != null && !d.st.optString("date").isEmpty()) sub += (sub.isEmpty() ? "" : " · ") + "mis à jour " + Ui.rel(d.st.optString("date"));
        if (!sub.isEmpty()) hero.addView(Ui.tv(host, sub, 13, 0xCCFFFFFF, false));
        add(hero);

        /* tuiles */
        LinearLayout k1 = Ui.kpi(host, R.drawable.ic_heart, Ui.ACCENT2, "J'aime la Page");
        LinearLayout k2 = Ui.kpi(host, R.drawable.ic_chat, Ui.WARN, "Sans réponse");
        LinearLayout k3 = Ui.kpi(host, R.drawable.ic_clock, Ui.OK, "En attente");
        LinearLayout k4 = Ui.kpi(host, R.drawable.ic_trend, Ui.ACCENT, "Commentaires");
        if (page.has("fan_count")) Ui.countUp(Ui.kpiValue(k1), page.optDouble("fan_count"));
        if (d.cm != null) {
            Ui.countUp(Ui.kpiValue(k2), un.size());
            Ui.countUp(Ui.kpiValue(k4), all.size());
        }
        Ui.countUp(Ui.kpiValue(k3), Api.sum(d.pending));
        add(Ui.row2(host, k1, k2));
        add(Ui.row2(host, k3, k4));

        if (ms.isEmpty()) {
            LinearLayout c = section("Courbes");
            c.addView(empty("Aucune statistique pour l'instant. Lance « Statistiques » depuis l'accueil."));
            final Ui.Btn b = Ui.btn(host, "Lancer les statistiques", R.drawable.ic_play, 1);
            b.setOnClickListener(v -> doAct(b, () -> {
                Api.dispatch("statistiques.yml", null);
                return null;
            }, "Statistiques lancées.", null));
            c.addView(b, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
            add(c);
        } else {
            add(buildExplorer());
            select(0);
            add(buildBars());
        }

        add(buildRings(d, all, un));

        if (!ms.isEmpty()) {
            LinearLayout c = section("Toutes les métriques");
            for (int i = 0; i < ms.size(); i++) {
                final int idx = i;
                Api.Metric m = ms.get(i);
                if (i > 0) c.addView(divider());
                LinearLayout r = Ui.hbox(host);
                r.setPadding(0, Ui.dp(4), 0, Ui.dp(4));
                r.addView(Ui.tv(host, m.name, 14.5f, Ui.INK, false), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
                float last = m.vals[m.vals.length - 1];
                r.addView(Ui.tv(host, Ui.nf(last), 15, Ui.INK, true), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 8, 0));
                if (m.vals.length > 1) r.addView(deltaChip(last, m.vals[m.vals.length - 2]));
                r.setOnClickListener(v -> {
                    select(idx);
                    host.toast(ms.get(idx).name + " affiché plus haut.", false);
                });
                c.addView(r);
            }
            add(c);
        }
    }

    /* ---------- explorateur de courbes ---------- */

    private View buildExplorer() {
        LinearLayout c = section("Évolution");
        HorizontalScrollView hs = new HorizontalScrollView(host);
        hs.setHorizontalScrollBarEnabled(false);
        LinearLayout row = Ui.hbox(host);
        chips.clear();
        for (int i = 0; i < ms.size(); i++) {
            final int idx = i;
            TextView t = Ui.tv(host, ms.get(i).name, 13.5f, Ui.MUTED, true);
            t.setPadding(Ui.dp(14), Ui.dp(8), Ui.dp(14), Ui.dp(8));
            t.setBackground(Ui.round(Ui.SOFT, 99));
            t.setOnClickListener(v -> select(idx));
            Ui.press(t);
            row.addView(t, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 8, 0));
            chips.add(t);
        }
        hs.addView(row);
        c.addView(hs, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        LinearLayout v = Ui.hbox(host);
        bigVal = Ui.tv(host, "-", 34, Ui.INK, true);
        v.addView(bigVal);
        deltaBox = Ui.hbox(host);
        v.addView(deltaBox, Ui.lp(Ui.WRAP, Ui.WRAP, 10, 0, 0, 0));
        c.addView(v, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 14, 0, 0));
        chart = new LineChartView(host);
        c.addView(chart, Ui.lp(Ui.MATCH, Ui.dp(200), 0, 6, 0, 0));
        statsRow = Ui.hbox(host);
        c.addView(statsRow, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 0));
        return c;
    }

    private void select(int i) {
        if (i < 0 || i >= ms.size() || chart == null) return;
        Api.Metric m = ms.get(i);
        for (int k = 0; k < chips.size(); k++) {
            TextView t = chips.get(k);
            boolean on = k == i;
            t.setTextColor(on ? 0xFF06112B : Ui.MUTED);
            t.setBackground(Ui.round(on ? Ui.ACCENT : Ui.SOFT, 99));
        }
        int[] palette = {Ui.ACCENT, Ui.ACCENT2, Ui.OK, Ui.WARN, 0xFF38BDF8};
        int color = palette[i % palette.length];
        float last = m.vals[m.vals.length - 1];
        Ui.countUp(bigVal, last);
        deltaBox.removeAllViews();
        if (m.vals.length > 1) deltaBox.addView(deltaChip(last, m.vals[m.vals.length - 2]));
        chart.setData(m.vals, m.labs, color);
        float mn = m.vals[0], mx = m.vals[0], sum = 0;
        for (float v : m.vals) {
            mn = Math.min(mn, v);
            mx = Math.max(mx, v);
            sum += v;
        }
        statsRow.removeAllViews();
        String[][] items = {{"Min", Ui.nf(mn)}, {"Moyenne", Ui.nf(sum / m.vals.length)}, {"Max", Ui.nf(mx)}};
        for (String[] it : items) {
            LinearLayout col = Ui.vbox(host);
            col.setGravity(Gravity.CENTER);
            col.addView(Ui.tv(host, it[1], 16, Ui.INK, true));
            col.addView(Ui.tv(host, it[0], 12, Ui.MUTED, false));
            statsRow.addView(col, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        }
    }

    private View deltaChip(float last, float prev) {
        String p = Ui.pct(last, prev);
        if (p.isEmpty()) return Ui.chip(host, "stable", 0);
        return Ui.chip(host, p, last > prev ? 1 : (last < prev ? 3 : 0));
    }

    /* ---------- barres ---------- */

    private View buildBars() {
        Api.Metric pick = ms.get(0);
        for (Api.Metric m : ms) if ("page_daily_follows_unique".equals(m.key)) pick = m;
        if (pick == ms.get(0) && ms.size() > 1 && !"page_daily_follows_unique".equals(pick.key)) pick = ms.get(1);
        LinearLayout c = section(pick.name + " par jour");
        BarChartView bc = new BarChartView(host);
        c.addView(bc, new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(190)));
        bc.setData(pick.vals, pick.labs, Ui.ACCENT2);
        return c;
    }

    /* ---------- anneaux ---------- */

    private View buildRings(Api.Dash d, List<Api.Cmt> all, List<Api.Cmt> un) {
        LinearLayout c = section("Santé du bot");
        LinearLayout row = new LinearLayout(host);
        row.setOrientation(LinearLayout.HORIZONTAL);

        float answered = all.isEmpty() ? 1f : (all.size() - countUnanswered(all)) / (float) all.size();
        int done = 0, ok = 0;
        JSONArray rn = d.runs;
        for (int i = 0; rn != null && i < rn.length(); i++) {
            JSONObject r = rn.optJSONObject(i);
            if (r == null || !"completed".equals(r.optString("status"))) continue;
            done++;
            if ("success".equals(r.optString("conclusion"))) ok++;
        }
        float success = done == 0 ? 0f : ok / (float) done;
        int tot = Api.sum(d.total), pend = Api.sum(d.pending);
        float files = tot == 0 ? 1f : (tot - pend) / (float) tot;

        row.addView(ring("Réponses données", answered, Ui.OK), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.addView(ring("Exécutions réussies", success, Ui.ACCENT), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.addView(ring("Files traitées", files, Ui.ACCENT2), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        c.addView(row);
        return c;
    }

    private int countUnanswered(List<Api.Cmt> all) {
        int n = 0;
        for (Api.Cmt x : all) {
            if (x.c.has("page_a_repondu") && !x.c.optBoolean("page_a_repondu", true)) n++;
        }
        return n;
    }

    private View ring(String label, float p, int color) {
        LinearLayout col = Ui.vbox(host);
        col.setGravity(Gravity.CENTER_HORIZONTAL);
        RingView rv = new RingView(host);
        rv.set(p, color);
        col.addView(rv, new LinearLayout.LayoutParams(Ui.dp(88), Ui.dp(88)));
        TextView t = Ui.tv(host, label, 12, Ui.MUTED, false);
        t.setGravity(Gravity.CENTER);
        col.addView(t, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        return col;
    }
}
