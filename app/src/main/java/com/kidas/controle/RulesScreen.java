package com.kidas.controle;

import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

import java.util.List;
import java.util.concurrent.Future;

/** Onglet Réponses : comportement du bot et accès aux interactions. */
final class RulesScreen extends Screen {
    private static class Data {
        Api.Bot bot;
        Api.Dash dash;
        final List<Exception> errs = new java.util.ArrayList<>();
    }

    RulesScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Réponses et règles"; }

    @Override
    void build() {
        skeletons(4);
        load(() -> {
            Data d = new Data();
            Future<Api.Bot> fb = Api.par(() -> Api.botState());
            Future<Api.Dash> fd = Api.par(() -> Api.dash());
            d.bot = Api.get(fb, d.errs);
            d.dash = Api.get(fd, d.errs);
            return d;
        }, this::render, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render(Data d) {
        clearAll();
        for (Exception e : d.errs) add(errBox(e));
        final Api.Bot bs = d.bot;

        /* héro inversé : état des réponses */
        LinearLayout hero = Ui.hero(host);
        LinearLayout r = Ui.hbox(host);
        PulseDot dot = new PulseDot(host);
        boolean on = bs != null && nested(bs.cfg, "reponses");
        String t, s;
        if (bs == null) { t = "État inconnu"; s = "Impossible de lire glm/config.json."; }
        else if (!on) { t = "Réponses automatiques coupées"; s = "Le bot like et lit, mais ne répond plus."; }
        else if ("on".equals(bs.state)) { t = "Le bot répond tout seul"; s = "Il like et répond aux nouvelles interactions."; }
        else if ("wait".equals(bs.state)) { t = "En attente de session"; s = "Les réponses reprendront au prochain démarrage."; }
        else { t = "Bot arrêté"; s = "Relance une session depuis l'onglet Bot."; }
        dot.set(bs == null || !on ? Ui.HSUB : Ui.BG, bs != null && on && !"off".equals(bs.state));
        r.addView(dot);
        LinearLayout tx = Ui.vbox(host);
        tx.addView(Ui.tv(host, t, 18, Ui.BG, true));
        tx.addView(Ui.tv(host, s, 13, Ui.HSUB, false));
        r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        hero.addView(r);
        add(hero);

        /* interrupteur IA réponse */
        if (bs != null) {
            LinearLayout sw = section("IA réponse");
            sw.addView(switchRow("Répondre aux commentaires", "Le bot rédige et publie une réponse", on,
                    v -> Api.updateJson("glm/config.json", false, cur -> {
                        JSONObject c = (JSONObject) cur;
                        JSONObject o = c.optJSONObject("reponses");
                        if (o == null) { o = new JSONObject(); Api.put(c, "reponses", o); }
                        Api.put(o, "actif", v);
                        return c;
                    }, "Réponses automatiques " + (v ? "activées" : "désactivées"))));
            add(sw);
        }

        /* accès aux interactions */
        JSONObject page = d.dash == null ? null : d.dash.st == null ? null : d.dash.st.optJSONObject("page");
        if (page == null && d.dash != null && d.dash.cm != null) page = d.dash.cm.optJSONObject("page");
        String pid = d.dash == null ? "" : Api.pageId(d.dash.st, d.dash.cm);
        int nAvis = 0, nAll = 0;
        if (d.dash != null && d.dash.cm != null) {
            List<Api.Cmt> all = Api.flatComments(d.dash.cm);
            nAll = all.size();
            nAvis = Api.unanswered(all, pid).size();
        }
        host.badge(nAvis);
        LinearLayout inter = section("Interactions");
        inter.addView(routeRow(R.drawable.ic_chat, "Avis", nAvis <= 0 ? "Tout est traité" : nAvis + " sans réponse", MainActivity.COMMENTS));
        inter.addView(divider());
        inter.addView(routeRow(R.drawable.ic_messenger, "Messages", "Conversations Messenger", MainActivity.MESSAGES));
        inter.addView(divider());
        inter.addView(routeRow(R.drawable.ic_pen, "Publier", "Nouveau post sur la Page", MainActivity.PUBLISH));
        add(inter);

        /* règles actives du bot */
        LinearLayout rules = section("Règles du bot");
        boolean rep = bs != null && nested(bs.cfg, "reponses");
        rules.addView(ruleRow("Like automatique", "Chaque nouveau commentaire est aimé", rep));
        rules.addView(divider());
        rules.addView(ruleRow("Réponse rédigée", "GLM adapte la réponse au commentaire", rep));
        rules.addView(divider());
        rules.addView(ruleRow("Publications automatiques", "Posts planifiés par le bot", bs != null && nested(bs.cfg, "posts")));
        add(rules);
        add(note("Règles avancées (délai, mots-clés) : ", "à venir dans une prochaine version du bot."));
    }

    private boolean nested(JSONObject cfg, String key) {
        JSONObject o = cfg.optJSONObject(key);
        return o == null || o.optBoolean("actif", true);
    }

    private View routeRow(int iconRes, final String label, final String sub, final int target) {
        LinearLayout row = Ui.hbox(host);
        row.setPadding(0, Ui.dp(6), 0, Ui.dp(6));
        row.setClickable(true);
        Ui.press(row);
        ImageView ic = new ImageView(host);
        ic.setImageResource(iconRes);
        ic.setColorFilter(Ui.INK, android.graphics.PorterDuff.Mode.SRC_IN);
        ic.setBackground(Ui.roundS(Ui.SOFT, Ui.LINE, 12));
        ic.setPadding(Ui.dp(10), Ui.dp(10), Ui.dp(10), Ui.dp(10));
        row.addView(ic, new LinearLayout.LayoutParams(Ui.dp(38), Ui.dp(38)));
        LinearLayout t = Ui.vbox(host);
        t.setPadding(Ui.dp(12), 0, 0, 0);
        t.addView(Ui.tv(host, label, 14.5f, Ui.INK, true));
        t.addView(Ui.tv(host, sub, 12.5f, Ui.MUTED, false));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.setOnClickListener(v -> host.go(target));
        return row;
    }

    private View ruleRow(String label, String desc, boolean active) {
        LinearLayout row = Ui.hbox(host);
        row.setPadding(0, Ui.dp(6), 0, Ui.dp(6));
        LinearLayout t = Ui.vbox(host);
        t.addView(Ui.tv(host, label, 14.5f, Ui.INK, true));
        t.addView(Ui.tv(host, desc, 12.5f, Ui.MUTED, false));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.addView(Ui.chip(host, active ? "Actif" : "Coupé", active ? 1 : 0));
        return row;
    }
}
