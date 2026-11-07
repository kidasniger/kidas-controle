package com.kidas.controle;

import android.text.TextUtils;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;

final class CommentsScreen extends Screen {
    private static boolean showAll = false;

    CommentsScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Avis et commentaires"; }

    @Override
    void build() {
        skeletons(3);
        load(() -> Api.readObj("inbox/commentaires.json"), this::render, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render(JSONObject cm) {
        clearAll();
        if (cm == null) {
            add(empty("Aucune donnée. Lance « Surveiller » depuis l'accueil."));
            return;
        }
        JSONObject pg = cm.optJSONObject("page");
        final String pid = pg == null ? "" : pg.optString("id", "");
        List<Api.Cmt> all = Api.flatComments(cm);
        List<Api.Cmt> un = Api.unanswered(all, pid);
        host.badge(un.size());

        /* sélecteur */
        LinearLayout seg = new LinearLayout(host);
        seg.setOrientation(LinearLayout.HORIZONTAL);
        seg.setBackground(Ui.roundS(Ui.CARD, Ui.LINE, 14));
        seg.setPadding(Ui.dp(4), Ui.dp(4), Ui.dp(4), Ui.dp(4));
        String[] names = {"Sans réponse (" + un.size() + ")", "Tous (" + all.size() + ")"};
        for (int i = 0; i < 2; i++) {
            final boolean allMode = i == 1;
            boolean on = showAll == allMode;
            TextView t = Ui.tv(host, names[i], 14, on ? 0xFF06112B : Ui.MUTED, true);
            t.setGravity(android.view.Gravity.CENTER);
            t.setPadding(0, Ui.dp(10), 0, Ui.dp(10));
            t.setBackground(Ui.round(on ? Ui.ACCENT : 0x00000000, 11));
            t.setOnClickListener(v -> {
                showAll = allMode;
                host.refresh();
            });
            seg.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        }
        add(seg);
        String upd = cm.optString("updated", "");
        add(Ui.tv(host, "Données du dernier audit : " + (upd.isEmpty() ? "date inconnue" : Ui.rel(upd)), 12.5f, Ui.MUTED, false));

        List<Api.Cmt> list = showAll ? all : un;
        if (list.isEmpty()) {
            add(empty("Aucun commentaire à afficher."));
            return;
        }
        int max = Math.min(40, list.size());
        for (int i = 0; i < max; i++) add(commentCard(list.get(i), pid));
        if (list.size() > 40) add(empty("40 plus récents affichés."));
    }

    private View commentCard(Api.Cmt x, String pid) {
        final JSONObject c = x.c;
        JSONObject from = c.optJSONObject("from");
        String name = from == null ? "Abonné" : from.optString("name", "Abonné");
        boolean mine = from != null && from.optString("id", "").equals(pid);
        LinearLayout card = Ui.card(host);
        LinearLayout top = Ui.hbox(host);
        top.addView(Ui.tv(host, mine ? "Ta Page" : name, 15, Ui.INK, true), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        top.addView(Ui.tv(host, Ui.rel(c.optString("created_time")), 12.5f, Ui.MUTED, false));
        card.addView(top);
        String msg = c.optString("message", "");
        card.addView(Ui.tv(host, msg.isEmpty() ? "(sans texte)" : msg, 15, Ui.INK, false), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 6, 0, 6));
        String post = x.post.optString("message", x.post.optString("story", "publication"));
        TextView pt = Ui.tv(host, "Sur : " + (post.length() > 90 ? post.substring(0, 90) : post), 12.5f, Ui.MUTED, false);
        pt.setMaxLines(1);
        pt.setEllipsize(TextUtils.TruncateAt.END);
        card.addView(pt);

        final LinearLayout foot = Ui.hbox(host);
        boolean answered = c.optBoolean("page_a_repondu", false);
        foot.addView(Ui.chip(host, answered ? "Répondu" : "Sans réponse", answered ? 1 : 2), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        card.addView(foot, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));

        if (!mine) {
            final Ui.Btn open = Ui.btn(host, "Répondre", R.drawable.ic_chat, 0);
            open.setMinimumHeight(Ui.dp(38));
            foot.addView(open);
            final LinearLayout form = Ui.vbox(host);
            form.setVisibility(View.GONE);
            final EditText ta = Ui.edit(host, "Ta réponse...", "", 3);
            form.addView(ta, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
            final Ui.Btn send = Ui.btn(host, "Mettre en file", R.drawable.ic_send, 1);
            form.addView(send, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 0));
            card.addView(form, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));
            open.setOnClickListener(v -> {
                if (form.getVisibility() == View.VISIBLE) {
                    form.setVisibility(View.GONE);
                } else {
                    form.setVisibility(View.VISIBLE);
                    form.setAlpha(0f);
                    form.animate().alpha(1f).setDuration(250).start();
                    ta.requestFocus();
                }
            });
            send.setOnClickListener(v -> {
                final String t = ta.getText().toString().trim();
                final String cid = String.valueOf(c.optString("id"));
                doActR(send, () -> {
                    if (t.isEmpty()) throw new Exception("Écris une réponse.");
                    Api.updateJson("posts/replies.json", true, cur -> {
                        JSONObject e = new JSONObject();
                        Api.put(e, "comment_id", cid);
                        Api.put(e, "message", t);
                        Api.put(e, "status", "pending");
                        ((JSONArray) cur).put(e);
                        return cur;
                    }, "Réponse (appli de contrôle)");
                    try {
                        Api.dispatch("repondre.yml", null);
                        return true;
                    } catch (Exception e) {
                        return false;
                    }
                }, launched -> {
                    form.setVisibility(View.GONE);
                    open.setVisibility(View.GONE);
                    foot.addView(Ui.chip(host, "En file", 4));
                    toast(launched ? "Réponse mise en file et lancée." : "Réponse mise en file : traitée sous 5 à 10 min.", false);
                });
            });
        }
        return card;
    }
}
