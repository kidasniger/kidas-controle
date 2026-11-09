package com.kidas.controle;

import android.text.InputFilter;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;

/** Messenger de la Page : liste des conversations, lecture, réponse (envoyée par le bot). */
final class MessagesScreen extends Screen {
    private static boolean showAll = false;
    private static String openId = "";
    private static final int MAX_CARDS = 30;

    private Object[] data;

    MessagesScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Messenger"; }

    @Override
    void build() {
        skeletons(3);
        this.<Object[]>load(() -> {
            Object[] r = new Object[2];
            r[0] = Api.readObj("inbox/messages.json");
            r[1] = Api.readArr("posts/messages.json");
            return r;
        }, r -> {
            data = r;
            render();
        }, e -> {
            clearAll();
            add(errBox(e));
        });
    }

    private void render() {
        clearAll();
        JSONObject inbox = (JSONObject) data[0];
        JSONArray queue = (JSONArray) data[1];
        if (inbox == null) {
            add(empty("Aucune conversation pour l'instant. Le bot les écrit après son prochain cycle de lecture."));
            return;
        }
        List<JSONObject> all = Api.conversations(inbox);
        final List<JSONObject> todo = new java.util.ArrayList<>();
        for (JSONObject c : all) if (Api.needsReply(c)) todo.add(c);
        host.badgeMessages(todo.size());

        LinearLayout seg = new LinearLayout(host);
        seg.setOrientation(LinearLayout.HORIZONTAL);
        seg.setBackground(Ui.roundS(Ui.CARD, Ui.LINE, 14));
        seg.setPadding(Ui.dp(4), Ui.dp(4), Ui.dp(4), Ui.dp(4));
        String[] names = {"À répondre (" + todo.size() + ")", "Toutes (" + all.size() + ")"};
        for (int i = 0; i < 2; i++) {
            final boolean allMode = i == 1;
            boolean on = showAll == allMode;
            TextView t = Ui.tv(host, names[i], 14, on ? 0xFF06112B : Ui.MUTED, true);
            t.setGravity(Gravity.CENTER);
            t.setPadding(0, Ui.dp(10), 0, Ui.dp(10));
            t.setBackground(Ui.round(on ? Ui.ACCENT : 0x00000000, 11));
            t.setOnClickListener(v -> {
                showAll = allMode;
                render();
            });
            seg.addView(t, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        }
        add(seg);
        String upd = inbox.optString("updated", "");
        add(Ui.tv(host, "Lu par le bot : " + (upd.isEmpty() ? "date inconnue" : Ui.rel(upd)), 12.5f, Ui.MUTED, false));

        List<JSONObject> list = showAll ? all : todo;
        if (list.isEmpty()) {
            add(empty(showAll ? "Aucune conversation." : "Aucun message en attente de réponse."));
            return;
        }
        int max = Math.min(MAX_CARDS, list.size());
        for (int i = 0; i < max; i++) {
            JSONObject c = list.get(i);
            add(convCard(c, Api.lastQueued(queue, c.optString("id"))));
        }
        if (list.size() > MAX_CARDS) add(empty(MAX_CARDS + " plus récentes affichées."));
    }

    private static String textOf(JSONObject m) {
        String t = m.optString("message", "");
        return t.isEmpty() ? "(pièce jointe ou sticker)" : t;
    }

    private View convCard(final JSONObject c, JSONObject queued) {
        final String cid = c.optString("id");
        JSONObject who = c.optJSONObject("with");
        String name = who == null ? "" : who.optString("name", "");
        if (name.isEmpty()) name = "Contact";
        final String rid = who == null ? "" : who.optString("id", "");
        JSONArray ms = c.optJSONArray("messages");
        boolean needs = Api.needsReply(c);
        boolean winOpen = Api.windowOpen(c);
        String qs = queued == null ? "" : queued.optString("status", "");
        boolean waiting = "pending".equals(qs);

        LinearLayout card = Ui.card(host);
        LinearLayout top = Ui.hbox(host);
        top.addView(Ui.tv(host, name, 15, Ui.INK, true), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        top.addView(Ui.tv(host, Ui.rel(c.optString("updated_time")), 12.5f, Ui.MUTED, false));
        card.addView(top);

        JSONObject last = ms == null || ms.length() == 0 ? null : ms.optJSONObject(ms.length() - 1);
        if (last != null) {
            String pre = last.optBoolean("from_page", false) ? "Toi : " : "";
            TextView pv = Ui.tv(host, pre + textOf(last), 14.5f, Ui.INK, false);
            pv.setMaxLines(2);
            pv.setEllipsize(TextUtils.TruncateAt.END);
            card.addView(pv, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 6, 0, 0));
        }

        final LinearLayout chips = Ui.hbox(host);
        if (waiting) {
            chips.addView(Ui.chip(host, "En file", 4));
        } else if ("error".equals(qs)) {
            chips.addView(Ui.chip(host, "Échec d'envoi", 3));
        } else if (needs) {
            chips.addView(Ui.chip(host, "Sans réponse", 2));
        } else {
            chips.addView(Ui.chip(host, "Répondu", 1));
        }
        if (needs && !winOpen) chips.addView(Ui.chip(host, "24 h dépassées", 3), Ui.lp(Ui.WRAP, Ui.WRAP, 6, 0, 0, 0));

        final LinearLayout foot = Ui.hbox(host);
        foot.addView(chips, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        final Ui.Btn toggle = Ui.btn(host, "Ouvrir", R.drawable.ic_chat, 0);
        toggle.setMinimumHeight(Ui.dp(38));
        foot.addView(toggle);
        card.addView(foot, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));

        /* fil de discussion */
        final LinearLayout thread = Ui.vbox(host);
        for (int i = 0; ms != null && i < ms.length(); i++) {
            JSONObject m = ms.optJSONObject(i);
            if (m != null) addBubble(thread, m);
        }
        if (waiting) {
            thread.addView(Ui.tv(host, "Ta réponse est en file : le bot l'envoie à son prochain cycle (environ 1 minute).",
                    13, Ui.MUTED, false), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 4, 0, 0));
        } else if (rid.isEmpty()) {
            thread.addView(Ui.tv(host, "Contact introuvable : réponse impossible.", 13, Ui.MUTED, false),
                    Ui.lp(Ui.MATCH, Ui.WRAP, 0, 4, 0, 0));
        } else if (!winOpen) {
            thread.addView(Ui.tv(host, "Messenger n'autorise plus la réponse 24 h après le dernier message de la personne. "
                    + "Elle doit réécrire pour rouvrir la conversation.", 13, Ui.MUTED, false),
                    Ui.lp(Ui.MATCH, Ui.WRAP, 0, 4, 0, 0));
        } else {
            if ("error".equals(qs)) {
                String er = queued.optString("erreur", "");
                thread.addView(Ui.tv(host, "Dernier envoi refusé" + (er.isEmpty() ? "." : " : " + er + "."),
                        13, Ui.BAD, false), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 4, 0, 0));
            }
            final EditText ta = Ui.edit(host, "Ta réponse...", "", 3);
            ta.setFilters(new InputFilter[]{new InputFilter.LengthFilter(Api.MESSAGE_MAX)});
            thread.addView(ta, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 0));
            final Ui.Btn send = Ui.btn(host, "Mettre en file", R.drawable.ic_send, 1);
            thread.addView(send, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 0));
            send.setOnClickListener(v -> {
                final String t = ta.getText().toString().trim();
                doActR(send, () -> {
                    if (t.isEmpty()) throw new Exception("Écris une réponse.");
                    Api.queueMessage(cid, rid, t);
                    return Boolean.TRUE;
                }, done -> {
                    JSONObject e = new JSONObject();
                    Api.put(e, "conversation_id", cid);
                    Api.put(e, "recipient_id", rid);
                    Api.put(e, "message", t);
                    Api.put(e, "status", "pending");
                    if (data != null) ((JSONArray) data[1]).put(e);
                    thread.removeView(ta);
                    thread.removeView(send);
                    chips.removeAllViews();
                    chips.addView(Ui.chip(host, "En file", 4));
                    toast("Message mis en file : envoi sous 1 à 2 min.", false);
                });
            });
        }
        card.addView(thread, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 12, 0, 0));

        boolean open = cid.equals(openId);
        thread.setVisibility(open ? View.VISIBLE : View.GONE);
        toggle.label.setText(open ? "Fermer" : "Ouvrir");
        toggle.setOnClickListener(v -> {
            if (thread.getVisibility() == View.VISIBLE) {
                thread.setVisibility(View.GONE);
                toggle.label.setText("Ouvrir");
                openId = "";
            } else {
                thread.setVisibility(View.VISIBLE);
                thread.setAlpha(0f);
                thread.animate().alpha(1f).setDuration(250).start();
                toggle.label.setText("Fermer");
                openId = cid;
            }
        });
        return card;
    }

    private void addBubble(LinearLayout thread, JSONObject m) {
        boolean mine = m.optBoolean("from_page", false);
        TextView b = Ui.tv(host, textOf(m), 14.5f, Ui.INK, false);
        b.setBackground(mine ? Ui.round(Ui.SOFT, 14) : Ui.roundS(Ui.BG, Ui.LINE, 14));
        b.setPadding(Ui.dp(12), Ui.dp(8), Ui.dp(12), Ui.dp(8));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(Ui.WRAP, Ui.WRAP);
        p.gravity = mine ? Gravity.END : Gravity.START;
        p.topMargin = Ui.dp(8);
        if (mine) p.leftMargin = Ui.dp(40); else p.rightMargin = Ui.dp(40);
        thread.addView(b, p);
        TextView tm = Ui.tv(host, Ui.rel(m.optString("created_time")), 11, Ui.MUTED, false);
        LinearLayout.LayoutParams q = new LinearLayout.LayoutParams(Ui.WRAP, Ui.WRAP);
        q.gravity = mine ? Gravity.END : Gravity.START;
        q.topMargin = Ui.dp(2);
        thread.addView(tm, q);
    }
}
