package com.kidas.controle;

import android.text.InputType;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Future;

final class BotScreen extends Screen {
    private static class Data {
        Api.Bot bot;
        JSONArray runs, wl;
        final List<Exception> errs = new ArrayList<>();
    }

    private static final String[][][] CATALOG = {
            {{"Lecture"}, {"surveiller.yml", "Surveiller la Page", "Récupère commentaires et publications"}, {"statistiques.yml", "Statistiques", "Abonnés, vues, interactions"}, {"archiver.yml", "Archiver la Page", "Résumé des posts"}, {"audit.yml", "Audit complet", "Enchaîne les 4 lectures"}},
            {{"Publication"}, {"dispatcher.yml", "Traiter les files", "Lance ce qui est en attente"}, {"publier.yml", "Publier (texte)", ""}, {"publier-avance.yml", "Publier (média / programmé)", ""}, {"repondre.yml", "Envoyer les réponses", ""}, {"actions-posts.yml", "Modifier / supprimer des posts", ""}},
            {{"Maintenance"}, {"apprendre.yml", "Apprendre", "Met à jour projets et performances"}, {"archive-mensuelle.yml", "Archive mensuelle", ""}, {"keepalive.yml", "Réactiver les tâches planifiées", ""}, {"test-facebook.yml", "Test Facebook", "Vérifie le jeton de Page"}}
    };

    BotScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Pilotage du bot"; }

    @Override
    void build() {
        skeletons(3);
        load(() -> {
            Data d = new Data();
            Future<Api.Bot> fb = Api.par(() -> Api.botState());
            Future<JSONArray> fr = Api.par(() -> Api.runs(20));
            Future<JSONArray> fw = Api.par(() -> Api.workflows(true));
            d.bot = Api.get(fb, d.errs);
            d.runs = Api.get(fr, d.errs);
            d.wl = Api.get(fw, d.errs);
            return d;
        }, this::render, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render(final Data d) {
        clearAll();
        for (Exception e : d.errs) add(errBox(e));
        final Api.Bot bs = d.bot;
        if (bs != null) {
            for (int i = 0; i < Math.min(2, bs.errs.size()); i++) add(errBox(bs.errs.get(i)));
            add(heroCard(bs, d));
            LinearLayout sw = section("Interrupteurs");
            sw.addView(switchRow("GLM (tout)", "Interrupteur général dans glm/config.json", !bs.cfg.has("actif") || bs.cfg.optBoolean("actif", true),
                    v -> Api.updateJson("glm/config.json", false, cur -> {
                        Api.put((JSONObject) cur, "actif", v);
                        return cur;
                    }, "GLM " + (v ? "activé" : "désactivé"))));
            sw.addView(switchRow("Publications automatiques", "Posts planifiés par GLM", nested(bs.cfg, "posts"), v -> setNested("posts", v)));
            sw.addView(switchRow("Réponses automatiques", "Réponses aux commentaires", nested(bs.cfg, "reponses"), v -> setNested("reponses", v)));
            add(sw);
            LinearLayout hard = section("Verrous GitHub");
            hard.addView(switchRow("Variable GLM_LIVE", "Désactive GLM Live et la veille quand elle vaut off", !"off".equals(bs.live), v -> Api.setVar("GLM_LIVE", v ? "on" : "off")));
            hard.addView(switchRow("Variable AUTO_REPONSES", "Désactive le workflow de réponses automatiques", !"off".equals(bs.auto), v -> Api.setVar("AUTO_REPONSES", v ? "on" : "off")));
            final JSONObject vw = Api.wfByFile(d.wl, "glm-veille.yml");
            if (vw != null) {
                final long id = vw.optLong("id");
                hard.addView(switchRow("Veille GLM", "Relance une session toutes les 10 minutes si aucune n'est active", "active".equals(vw.optString("state")),
                        v -> Api.req("PUT", "/repos/" + Api.mgr + "/actions/workflows/" + id + "/" + (v ? "enable" : "disable"), null, null)));
            }
            add(hard);
        }
        add(manualCard());
        for (String[][] g : CATALOG) {
            LinearLayout c = section(g[0][0]);
            for (int i = 1; i < g.length; i++) {
                if (i > 1) c.addView(divider());
                c.addView(workflowRow(g[i], d));
            }
            add(c);
        }
        if (d.runs != null && d.runs.length() > 0) {
            LinearLayout c = section("Exécutions récentes");
            for (int i = 0; i < d.runs.length(); i++) {
                JSONObject r = d.runs.optJSONObject(i);
                if (r == null) continue;
                if (i > 0) c.addView(divider());
                c.addView(runRow(r, true, host::refresh));
            }
            add(c);
        }
    }

    private boolean nested(JSONObject cfg, String key) {
        JSONObject o = cfg.optJSONObject(key);
        return o == null || o.optBoolean("actif", true);
    }

    private void setNested(final String key, final boolean v) throws Exception {
        Api.updateJson("glm/config.json", false, cur -> {
            JSONObject c = (JSONObject) cur;
            JSONObject o = c.optJSONObject(key);
            if (o == null) {
                o = new JSONObject();
                Api.put(c, key, o);
            }
            Api.put(o, "actif", v);
            return c;
        }, "GLM " + key + (v ? " activé" : " désactivé"));
    }

    private View heroCard(final Api.Bot bs, final Data d) {
        LinearLayout card = Ui.hero(host);
        LinearLayout r = Ui.hbox(host);
        PulseDot dot = new PulseDot(host);
        String t;
        if ("on".equals(bs.state)) { t = "En marche"; }
        else if ("wait".equals(bs.state)) { t = "Actif, en attente de session"; }
        else { t = "Arrêté"; }
        dot.set("off".equals(bs.state) ? Ui.HSUB : Ui.BG, !"off".equals(bs.state));
        r.addView(dot);
        LinearLayout tx = Ui.vbox(host);
        tx.addView(Ui.tv(host, t, 19, Ui.BG, true));
        tx.addView(Ui.tv(host, bs.running > 0 ? bs.running + " session(s) GLM Live en cours" : "Aucune session en cours", 13, Ui.HSUB, false));
        r.addView(tx, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        card.addView(r);

        final Ui.Btn start = Ui.btn(host, "Démarrer", R.drawable.ic_play, 3);
        final Ui.Btn stop = Ui.btn(host, "Arrêt d'urgence", R.drawable.ic_x, 2);
        start.setOnClickListener(v -> doAct(start, () -> {
            Api.setVar("GLM_LIVE", "on");
            Api.setVar("AUTO_REPONSES", "on");
            if (bs.cfg.has("actif") && !bs.cfg.optBoolean("actif", true)) {
                Api.updateJson("glm/config.json", false, cur -> {
                    Api.put((JSONObject) cur, "actif", true);
                    return cur;
                }, "Réactivation GLM");
            }
            JSONObject vw = Api.wfByFile(d.wl, "glm-veille.yml");
            if (vw != null && "active".equals(vw.optString("state"))) {
                Api.dispatch("glm-veille.yml", null);
            } else {
                JSONObject in = new JSONObject();
                Api.put(in, "dry_run", "false");
                Api.put(in, "minutes", "330");
                Api.dispatch("glm-live.yml", in);
            }
            Thread.sleep(1500);
            return null;
        }, "Bot démarré (session dans quelques secondes).", host::refresh));
        stop.setOnClickListener(v -> confirm("Arrêter le bot et annuler les sessions en cours ?", () -> doAct(stop, () -> {
            Api.setVar("GLM_LIVE", "off");
            Api.setVar("AUTO_REPONSES", "off");
            for (String s : new String[]{"in_progress", "queued"}) {
                JSONObject j = Api.jobj(Api.req("GET", "/repos/" + Api.mgr + "/actions/workflows/glm-live.yml/runs?status=" + s, null, null), "glm-live");
                JSONArray a = j.optJSONArray("workflow_runs");
                for (int i = 0; a != null && i < a.length(); i++) {
                    JSONObject run = a.optJSONObject(i);
                    if (run == null) continue;
                    try { Api.cancelRun(run.optLong("id")); } catch (Exception ignored) { /* déjà terminé */ }
                }
            }
            Thread.sleep(800);
            return null;
        }, "Bot arrêté.", host::refresh)));
        LinearLayout btns = new LinearLayout(host);
        btns.setOrientation(LinearLayout.HORIZONTAL);
        btns.addView(start, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        btns.addView(stop, Ui.lp(0, Ui.WRAP, 8, 0, 0, 0));
        ((LinearLayout.LayoutParams) stop.getLayoutParams()).weight = 1f;
        card.addView(btns, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 14, 0, 0));
        return card;
    }

    private View manualCard() {
        LinearLayout c = section("GLM Live manuel");
        final ToggleView dry = new ToggleView(host);
        dry.setChecked(true, false);
        LinearLayout row = Ui.hbox(host);
        row.addView(Ui.tv(host, "Mode test (rien n'est publié)", 15, Ui.INK, true), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        row.addView(dry);
        c.addView(row);
        c.addView(Ui.label(host, "Durée (minutes)"));
        final EditText min = Ui.edit(host, "2", "2", 1);
        min.setInputType(InputType.TYPE_CLASS_NUMBER);
        c.addView(min, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        final Ui.Btn run = Ui.btn(host, "Lancer GLM Live", R.drawable.ic_play, 0);
        run.setOnClickListener(v -> {
            final boolean test = dry.isOn();
            int m = 2;
            try { m = Integer.parseInt(min.getText().toString().trim()); } catch (Exception e) { /* défaut */ }
            final int minutes = Math.max(1, Math.min(330, m));
            doAct(run, () -> {
                JSONObject in = new JSONObject();
                Api.put(in, "dry_run", test ? "true" : "false");
                Api.put(in, "minutes", String.valueOf(minutes));
                Api.dispatch("glm-live.yml", in);
                Thread.sleep(1500);
                return null;
            }, "GLM Live lancé.", host::refresh);
        });
        c.addView(run, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 12, 0, 0));
        c.addView(Ui.tv(host, "Pour un test, GLM_LIVE doit être sur on.", 12.5f, Ui.MUTED, false), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        return c;
    }

    private View workflowRow(final String[] w, Data d) {
        JSONObject info = Api.wfByFile(d.wl, w[0]);
        JSONObject last = null;
        for (int i = 0; d.runs != null && info != null && i < d.runs.length(); i++) {
            JSONObject r = d.runs.optJSONObject(i);
            if (r != null && r.optLong("workflow_id") == info.optLong("id")) { last = r; break; }
        }
        LinearLayout row = Ui.hbox(host);
        row.setPadding(0, Ui.dp(4), 0, Ui.dp(4));
        LinearLayout t = Ui.vbox(host);
        t.addView(Ui.tv(host, w[1], 14.5f, Ui.INK, true));
        String sub = (info != null && !"active".equals(info.optString("state")) ? "désactivé · " : "")
                + (last != null ? Ui.rel(last.optString("created_at")) : w[2]);
        t.addView(Ui.tv(host, sub, 12.5f, Ui.MUTED, false));
        row.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        if (last != null) row.addView(runChip(last), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 8, 0));
        final Ui.Btn b = Ui.btn(host, "Lancer", R.drawable.ic_play, 0);
        b.setMinimumHeight(Ui.dp(38));
        b.setOnClickListener(v -> doAct(b, () -> {
            if ("audit.yml".equals(w[0])) Api.startAudit(); else Api.dispatch(w[0], null);
            Thread.sleep(1500);
            return null;
        }, w[1] + " lancé.", host::refresh));
        row.addView(b);
        return row;
    }
}
