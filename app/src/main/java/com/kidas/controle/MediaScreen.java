package com.kidas.controle;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class MediaScreen extends Screen {
    private TextView status;

    MediaScreen(MainActivity h) { super(h); }

    @Override
    String title() { return "Médias"; }

    @Override
    void build() {
        LinearLayout up = section("Envoyer");
        final Ui.Btn pick = Ui.btn(host, "Choisir des fichiers", R.drawable.ic_up, 1);
        pick.setOnClickListener(v -> host.pickFiles(true, this::uploadAll));
        up.addView(pick, new LinearLayout.LayoutParams(Ui.MATCH, Ui.WRAP));
        status = Ui.tv(host, "", 13, Ui.MUTED, false);
        up.addView(status, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 8, 0, 0));
        up.addView(Ui.tv(host, "Images et vidéos jusqu'à 50 Mo. Reprise automatique en cas de conflit avec le bot.", 12.5f, Ui.MUTED, false), Ui.lp(Ui.WRAP, Ui.WRAP, 0, 4, 0, 0));
        add(up);
        skeletons(1);
        load(() -> Api.listDir("media"), this::showLibrary, e -> {
            root.removeViewAt(root.getChildCount() - 1);
            add(errBox(e));
        });
    }

    private void uploadAll(final List<Uri> uris) {
        status.setText("Préparation...");
        load(() -> {
            int ok = 0;
            String last = "";
            for (int i = 0; i < uris.size(); i++) {
                final int idx = i;
                String[] ns = Api.nameSize(host, uris.get(i));
                try {
                    last = Api.upload(host, uris.get(i), ns[0], Long.parseLong(ns[1]), s -> Api.MAIN.post(() -> {
                        if (alive) status.setText("(" + (idx + 1) + "/" + uris.size() + ") " + ns0(uris, idx) + " : " + s);
                    }));
                    ok++;
                } catch (Exception e) {
                    if (uris.size() == 1) throw e;
                }
            }
            if (ok == 0) throw new Exception("Aucun fichier envoyé.");
            PublishScreen.media = last;
            return ok;
        }, n -> {
            status.setText("");
            toast(n + " fichier(s) envoyé(s).", false);
            host.refresh();
        }, e -> {
            status.setText("");
            toast(Api.hint(e), true);
        });
    }

    private String ns0(List<Uri> uris, int i) { return Api.nameSize(host, uris.get(i))[0]; }

    private void showLibrary(JSONArray arr) {
        root.removeViewAt(root.getChildCount() - 1);
        rc = 1;
        LinearLayout box = section("Bibliothèque");
        final List<JSONObject> files = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject f = arr.optJSONObject(i);
            if (f != null && "file".equals(f.optString("type"))) files.add(f);
        }
        Collections.sort(files, (a, b) -> b.optString("name").compareTo(a.optString("name")));
        if (files.isEmpty()) {
            box.addView(empty("Aucun média."));
            add(box);
            return;
        }
        int n = Math.min(60, files.size());
        LinearLayout row = null;
        for (int i = 0; i < n; i++) {
            if (i % 2 == 0) {
                row = new LinearLayout(host);
                row.setOrientation(LinearLayout.HORIZONTAL);
                box.addView(row, Ui.lp(Ui.MATCH, Ui.WRAP, 0, 0, 0, 10));
            }
            View cell = cell(files.get(i));
            row.addView(cell, Ui.lp(0, Ui.WRAP, i % 2 == 0 ? 0 : 5, 0, i % 2 == 0 ? 5 : 0, 0));
            ((LinearLayout.LayoutParams) cell.getLayoutParams()).weight = 1f;
        }
        if (n % 2 == 1) {
            View sp = new View(host);
            row.addView(sp, Ui.lp(0, 1, 5, 0, 0, 0));
            ((LinearLayout.LayoutParams) sp.getLayoutParams()).weight = 1f;
        }
        if (files.size() > 60) box.addView(empty("60 plus récents affichés sur " + files.size() + "."));
        add(box);
    }

    private View cell(final JSONObject f) {
        final String name = f.optString("name");
        final String path = f.optString("path");
        final String kind = PublishScreen.kind(name);
        LinearLayout m = Ui.vbox(host);
        m.setBackground(Ui.roundS(Ui.SOFT, Ui.LINE, 14));
        m.setPadding(Ui.dp(6), Ui.dp(6), Ui.dp(6), Ui.dp(8));

        final ImageView iv = new ImageView(host);
        iv.setScaleType(ImageView.ScaleType.CENTER_CROP);
        iv.setBackground(Ui.round(Ui.BG, 10));
        m.addView(iv, new LinearLayout.LayoutParams(Ui.MATCH, Ui.dp(110)));
        if ("video".equals(kind)) {
            iv.setImageResource(R.drawable.ic_play);
            iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
            iv.setPadding(Ui.dp(36), Ui.dp(36), Ui.dp(36), Ui.dp(36));
            iv.setColorFilter(Ui.MUTED, android.graphics.PorterDuff.Mode.SRC_IN);
        } else if (f.optLong("size") < 1500000L) {
            Api.EXT.execute(() -> {
                try {
                    byte[] data = Api.getBytes("/repos/" + Api.data + "/contents/" + Api.cp(path));
                    BitmapFactory.Options o = new BitmapFactory.Options();
                    o.inJustDecodeBounds = true;
                    BitmapFactory.decodeByteArray(data, 0, data.length, o);
                    int s = 1;
                    while (o.outWidth / (s * 2) >= 400) s *= 2;
                    o = new BitmapFactory.Options();
                    o.inSampleSize = s;
                    final Bitmap bm = BitmapFactory.decodeByteArray(data, 0, data.length, o);
                    if (bm == null) return;
                    Api.MAIN.post(() -> {
                        if (!alive) return;
                        iv.setImageBitmap(bm);
                        iv.setAlpha(0f);
                        iv.animate().alpha(1f).setDuration(350).start();
                    });
                } catch (Exception e) { /* vignette absente */ }
            });
        } else {
            iv.setImageResource(R.drawable.ic_image);
            iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
            iv.setPadding(Ui.dp(36), Ui.dp(36), Ui.dp(36), Ui.dp(36));
            iv.setColorFilter(Ui.MUTED, android.graphics.PorterDuff.Mode.SRC_IN);
        }
        TextView t = Ui.tv(host, name.replaceFirst("^\\d{10,}-", ""), 12.5f, Ui.INK, true);
        t.setMaxLines(1);
        t.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);
        m.addView(t, Ui.lp(Ui.MATCH, Ui.WRAP, 2, 8, 2, 0));
        long ts = 0;
        try { ts = Long.parseLong(name.split("-")[0]); } catch (Exception e) { /* pas d'horodatage */ }
        m.addView(Ui.tv(host, Ui.fsize(f.optLong("size")) + (ts > 0 ? " · " + Ui.fdate(ts) : ""), 11.5f, Ui.MUTED, false), Ui.lp(Ui.MATCH, Ui.WRAP, 2, 0, 2, 6));

        LinearLayout acts = Ui.hbox(host);
        acts.setGravity(Gravity.CENTER_VERTICAL);
        Ui.Btn use = Ui.btn(host, "Utiliser", 0, 1);
        use.setMinimumHeight(Ui.dp(36));
        use.setPadding(Ui.dp(8), 0, Ui.dp(8), 0);
        use.setOnClickListener(v -> {
            PublishScreen.media = path;
            host.go(MainActivity.PUBLISH);
        });
        Ui.Btn cp = Ui.btn(host, "", R.drawable.ic_copy, 0);
        cp.label.setVisibility(View.GONE);
        cp.setMinimumHeight(Ui.dp(36));
        cp.setPadding(Ui.dp(8), 0, Ui.dp(8), 0);
        cp.setOnClickListener(v -> host.copy(path));
        final Ui.Btn del = Ui.btn(host, "", R.drawable.ic_trash, 2);
        del.label.setVisibility(View.GONE);
        del.setMinimumHeight(Ui.dp(36));
        del.setPadding(Ui.dp(8), 0, Ui.dp(8), 0);
        del.setOnClickListener(v -> confirm("Supprimer ce fichier du dépôt ?",
                () -> doAct(del, () -> {
                    Api.deleteFile(path, name, f.optString("sha"));
                    return null;
                }, "Supprimé.", host::refresh)));
        acts.addView(use, new LinearLayout.LayoutParams(0, Ui.WRAP, 1f));
        acts.addView(cp, Ui.lp(Ui.WRAP, Ui.WRAP, 6, 0, 0, 0));
        acts.addView(del, Ui.lp(Ui.WRAP, Ui.WRAP, 6, 0, 0, 0));
        m.addView(acts);
        return m;
    }
}
