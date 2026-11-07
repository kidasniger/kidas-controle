package com.kidas.controle;

import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.net.Uri;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Future;

final class PublishScreen extends Screen {
    /* brouillon conservé quand on change d'onglet */
    static String msg = "";
    static String media = "";
    static long whenMs = 0;
    static boolean now = true;

    private TextView mediaTv, whenTv, status;
    private Ui.Btn clearMedia, clearWhen;
    private LinearLayout queueBox;

    PublishScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Publier"; }

    static String kind(String p) {
        return p.toLowerCase().matches(".*\\.(mp4|mov|m4v|webm|3gp|avi|mkv)$") ? "video" : "image";
    }

    @Override
    void build() {
        LinearLayout c = section("Nouveau post");
        final EditText ed = Ui.edit(host, "Texte du post...", msg, 5);
        final TextView count = Ui.tv(host, msg.length() + " caractères", 12.5f, Ui.MUTED, false);
        ed.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int a, int b, int c2) { }
            @Override public void onTextChanged(CharSequence s, int a, int b, int c2) { }
            @Override public void afterTextChanged(Editable s) {
                msg = s.toString();
                count.setText(msg.length() + " caractères");
            }
        });
        c.addView(ed, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        c.addView(count, Ui.lp(Ui.WRAP, Ui.WRAP, 2, 6, 0, 0));

        /* média */
        c.addView(Ui.label(host, "Média (image ou vidéo)"));
        mediaTv = Ui.tv(host, "", 14, Ui.INK, false);
        c.addView(mediaTv);
        status = Ui.tv(host, "", 12.5f, Ui.MUTED, false);
        LinearLayout mrow = new LinearLayout(host);
        mrow.setOrientation(LinearLayout.HORIZONTAL);
        Ui.Btn lib = Ui.btn(host, "Bibliothèque", R.drawable.ic_image, 0);
        lib.setOnClickListener(v -> openLibrary());
        Ui.Btn up = Ui.btn(host, "Envoyer", R.drawable.ic_up, 0);
        up.setOnClickListener(v -> host.pickFiles(false, this::uploadPicked));
        clearMedia = Ui.btn(host, "", R.drawable.ic_x, 2);
        clearMedia.label.setVisibility(View.GONE);
        clearMedia.setOnClickListener(v -> {
            media = "";
            refreshLabels();
        });
        mrow.addView(lib, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        mrow.addView(up, Ui.lp(0, Ui.WRAP, 8, 0, 0, 0));
        ((LinearLayout.LayoutParams) up.getLayoutParams()).weight = 1f;
        mrow.addView(clearMedia, Ui.lp(Ui.WRAP, Ui.WRAP, 8, 0, 0, 0));
        c.addView(mrow, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 0));
        c.addView(status);

        /* programmation */
        c.addView(Ui.label(host, "Programmer (facultatif)"));
        whenTv = Ui.tv(host, "", 14, Ui.INK, false);
        c.addView(whenTv);
        LinearLayout wrow = new LinearLayout(host);
        wrow.setOrientation(LinearLayout.HORIZONTAL);
        Ui.Btn pick = Ui.btn(host, "Choisir date et heure", R.drawable.ic_clock, 0);
        pick.setOnClickListener(v -> pickWhen());
        clearWhen = Ui.btn(host, "", R.drawable.ic_x, 2);
        clearWhen.label.setVisibility(View.GONE);
        clearWhen.setOnClickListener(v -> {
            whenMs = 0;
            refreshLabels();
        });
        wrow.addView(pick, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        wrow.addView(clearWhen, Ui.lp(Ui.WRAP, Ui.WRAP, 8, 0, 0, 0));
        c.addView(wrow, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 8, 0, 0));

        c.addView(switchRow("Lancer tout de suite", "Sinon le contrôle automatique le prend sous 5 à 10 min.", now, v -> now = v), Ui.lp(Ui.MATCH, Ui.WRAP, 0, 10, 0, 6));
        refreshLabels();

        final Ui.Btn go = Ui.btn(host, "Mettre en file", R.drawable.ic_send, 1);
        go.setOnClickListener(v -> submit(go, ed));
        c.addView(go, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        add(c);

        queueBox = section("Files d'attente");
        queueBox.addView(Ui.skeleton(host, 80));
        add(queueBox);
        loadQueues();
    }

    private void refreshLabels() {
        mediaTv.setText(media.isEmpty() ? "Aucun média" : media.replaceFirst("^media/\\d{10,}-", ""));
        mediaTv.setTextColor(media.isEmpty() ? Ui.MUTED : Ui.INK);
        clearMedia.setVisibility(media.isEmpty() ? View.GONE : View.VISIBLE);
        whenTv.setText(whenMs > 0 ? "Pour le " + Ui.fdate(whenMs) : "Publication immédiate");
        whenTv.setTextColor(whenMs > 0 ? Ui.INK : Ui.MUTED);
        clearWhen.setVisibility(whenMs > 0 ? View.VISIBLE : View.GONE);
    }

    private void pickWhen() {
        final Calendar c = Calendar.getInstance();
        if (whenMs > 0) c.setTimeInMillis(whenMs); else c.add(Calendar.HOUR_OF_DAY, 1);
        new DatePickerDialog(host, (dp, y, m, d) -> {
            final Calendar x = Calendar.getInstance();
            x.set(y, m, d);
            new TimePickerDialog(host, (tp, hh, mm) -> {
                x.set(Calendar.HOUR_OF_DAY, hh);
                x.set(Calendar.MINUTE, mm);
                x.set(Calendar.SECOND, 0);
                x.set(Calendar.MILLISECOND, 0);
                whenMs = x.getTimeInMillis();
                if (alive) refreshLabels();
            }, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), true).show();
        }, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH)).show();
    }

    private void openLibrary() {
        status.setText("Chargement de la bibliothèque...");
        load(() -> Api.listDir("media"), arr -> {
            status.setText("");
            final List<JSONObject> files = new ArrayList<>();
            for (int i = 0; i < arr.length(); i++) {
                JSONObject f = arr.optJSONObject(i);
                if (f != null && "file".equals(f.optString("type"))) files.add(f);
            }
            Collections.sort(files, (a, b) -> b.optString("name").compareTo(a.optString("name")));
            if (files.isEmpty()) {
                toast("Aucun média dans la bibliothèque.", false);
                return;
            }
            int n = Math.min(60, files.size());
            String[] names = new String[n];
            for (int i = 0; i < n; i++) {
                JSONObject f = files.get(i);
                names[i] = f.optString("name").replaceFirst("^\\d{10,}-", "") + " (" + Ui.fsize(f.optLong("size")) + ")";
            }
            new AlertDialog.Builder(host).setTitle("Choisir un média").setItems(names, (dlg, which) -> {
                media = files.get(which).optString("path");
                refreshLabels();
            }).show();
        }, e -> {
            status.setText("");
            toast(Api.hint(e), true);
        });
    }

    private void uploadPicked(final List<Uri> uris) {
        final Uri u = uris.get(0);
        load(() -> {
            String[] ns = Api.nameSize(host, u);
            return Api.upload(host, u, ns[0], Long.parseLong(ns[1]), s -> Api.MAIN.post(() -> {
                if (alive) status.setText(s);
            }));
        }, path -> {
            media = path;
            status.setText("Envoyé.");
            refreshLabels();
            toast("Média envoyé.", false);
        }, e -> {
            status.setText("");
            toast(Api.hint(e), true);
        });
    }

    private void submit(Ui.Btn go, final EditText ed) {
        final String text = ed.getText().toString().trim();
        final String mediaP = media;
        final long when = whenMs;
        final boolean launch = now;
        doActR(go, () -> {
            if (text.isEmpty() && mediaP.isEmpty()) throw new Exception("Écris un texte ou choisis un média.");
            final JSONObject entry = new JSONObject();
            Api.put(entry, "message", text);
            Api.put(entry, "status", "pending");
            String file = "posts/queue.json";
            if (!mediaP.isEmpty()) {
                Api.put(entry, "video".equals(kind(mediaP)) ? "video_path" : "image_path", mediaP);
                file = "posts/avance.json";
            }
            if (when > 0) {
                long d = when - System.currentTimeMillis();
                if (d < 10 * 60000L) throw new Exception("La programmation doit être à plus de 10 minutes.");
                if (d > 30L * 86400000L) throw new Exception("La programmation est limitée à 30 jours.");
                Api.put(entry, "publish_at", Ui.isoOf(when));
                file = "posts/avance.json";
            }
            Api.updateJson(file, true, cur -> {
                ((JSONArray) cur).put(entry);
                return cur;
            }, "Nouveau post (appli de contrôle)");
            boolean ok = false;
            if (launch) {
                try {
                    Api.dispatch("posts/queue.json".equals(file) ? "publier.yml" : "publier-avance.yml", null);
                    ok = true;
                } catch (Exception e) {
                    ok = false;
                }
            }
            return launch ? (ok ? "Mis en file et lancé." : "Mis en file, mais pas lancé : traité sous 5 à 10 min.") : "Mis en file (traité sous 5 à 10 min).";
        }, res -> {
            msg = "";
            media = "";
            whenMs = 0;
            now = true;
            toast(res, false);
            host.refresh();
        });
    }

    /* ---------- files d'attente ---------- */

    private static final String[] LABELS = {"Post texte", "Post média / programmé", "Réponse", "Action"};

    private static class Item {
        JSONObject e;
        int i;
        int src;
    }

    private void loadQueues() {
        load(() -> {
            List<Future<JSONArray>> fs = new ArrayList<>();
            for (final String n : Api.QUEUES) fs.add(Api.par(() -> Api.readArr("posts/" + n + ".json")));
            List<Item> items = new ArrayList<>();
            List<Exception> errs = new ArrayList<>();
            for (int s = 0; s < fs.size(); s++) {
                JSONArray a = Api.get(fs.get(s), errs);
                if (a == null) continue;
                for (int i = 0; i < a.length(); i++) {
                    JSONObject e = a.optJSONObject(i);
                    if (e == null) continue;
                    Item it = new Item();
                    it.e = e;
                    it.i = i;
                    it.src = s;
                    items.add(it);
                }
            }
            if (items.isEmpty() && !errs.isEmpty()) throw errs.get(0);
            return items;
        }, this::showQueues, e -> {
            queueBox.removeAllViews();
            queueBox.addView(Ui.h2(host, "Files d'attente"), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 12));
            queueBox.addView(errBox(e));
        });
    }

    private void showQueues(List<Item> items) {
        queueBox.removeAllViews();
        queueBox.addView(Ui.h2(host, "Files d'attente"), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 0, 0, 12));
        if (items.isEmpty()) {
            queueBox.addView(empty("Rien dans les files."));
            return;
        }
        List<Item> pend = new ArrayList<>(), done = new ArrayList<>();
        for (int k = items.size() - 1; k >= 0; k--) {
            Item it = items.get(k);
            if ("pending".equals(it.e.optString("status"))) pend.add(it);
            else if (done.size() < 25) done.add(it);
        }
        boolean first = true;
        for (Item it : pend) {
            if (!first) queueBox.addView(divider());
            queueBox.addView(card(it));
            first = false;
        }
        if (!done.isEmpty()) {
            queueBox.addView(Ui.h2(host, "Historique récent"), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 18, 0, 8));
            first = true;
            for (Item it : done) {
                if (!first) queueBox.addView(divider());
                queueBox.addView(card(it));
                first = false;
            }
        }
    }

    private View card(final Item x) {
        JSONObject e = x.e;
        String st = e.optString("status");
        int kind = 0;
        String txt = st;
        if ("published".equals(st) || "replied".equals(st) || "done".equals(st)) { kind = 1; txt = "published".equals(st) ? "Publié" : ("replied".equals(st) ? "Répondu" : "Fait"); }
        else if ("scheduled".equals(st)) { kind = 4; txt = "Programmé"; }
        else if ("error".equals(st)) { kind = 3; txt = "Erreur"; }
        else if ("cancelled".equals(st)) { kind = 0; txt = "Annulé"; }
        else if ("pending".equals(st)) { kind = 2; txt = "En attente"; }
        StringBuilder meta = new StringBuilder(LABELS[x.src]);
        if (!e.optString("publish_at").isEmpty()) meta.append(" · pour le ").append(Ui.fdate(Ui.iso(e.optString("publish_at"))));
        String mp = e.optString("image_path", e.optString("video_path", ""));
        if (!mp.isEmpty()) meta.append(" · ").append(mp.replaceFirst("^media/\\d{10,}-", ""));
        if (!e.optString("action").isEmpty()) meta.append(" · ").append(e.optString("action"));
        String body = e.optString("message", "");
        if (body.isEmpty()) body = e.optString("comment_id", e.optString("post_id", ""));

        LinearLayout box = Ui.vbox(host);
        LinearLayout top = Ui.hbox(host);
        top.addView(Ui.tv(host, meta.toString(), 12.5f, Ui.MUTED, false), new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        top.addView(Ui.chip(host, txt, kind));
        box.addView(top);
        TextView b = Ui.tv(host, body, 14.5f, Ui.INK, false);
        b.setMaxLines(3);
        b.setEllipsize(android.text.TextUtils.TruncateAt.END);
        box.addView(b, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 4, 0, 0));
        if ("pending".equals(st)) {
            final Ui.Btn c = Ui.btn(host, "Annuler", R.drawable.ic_x, 2);
            c.setMinimumHeight(Ui.dp(38));
            c.setOnClickListener(v -> confirm("Annuler cette entrée ?",
                    () -> doAct(c, () -> setStatus(x, "cancelled"), "Annulé.", host::refresh)));
            box.addView(c, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        } else if ("error".equals(st)) {
            final Ui.Btn r = Ui.btn(host, "Remettre en attente", R.drawable.ic_refresh, 0);
            r.setMinimumHeight(Ui.dp(38));
            r.setOnClickListener(v -> doAct(r, () -> setStatus(x, "pending"), "Remis en attente.", host::refresh));
            box.addView(r, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        }
        return box;
    }

    private Object setStatus(final Item x, final String s) throws Exception {
        Api.updateJson("posts/" + Api.QUEUES[x.src] + ".json", true, cur -> {
            JSONArray a = (JSONArray) cur;
            JSONObject t = a.optJSONObject(x.i);
            if (t == null || !t.optString("message", "").equals(x.e.optString("message", ""))
                    || !t.optString("comment_id", "").equals(x.e.optString("comment_id", ""))) {
                throw new Exception("Le fichier a changé, actualise l'écran.");
            }
            Api.put(t, "status", s);
            return a;
        }, "Mise à jour du statut (appli de contrôle)");
        return null;
    }
}
