package com.kidas.controle;

import android.content.Context;
import android.graphics.PorterDuff;
import android.view.Gravity;
import android.view.View;
import android.view.animation.OvershootInterpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Barre de navigation basse avec pastille qui glisse. */
final class NavBar extends FrameLayout {
    interface OnTab { void tab(int i); }

    private final int n;
    private final View pill;
    private final ImageView[] icons;
    private final TextView[] labels;
    private final TextView[] badges;
    private int sel = -1;
    private int itemW = 0;

    NavBar(Context c, String[] names, int[] res, final OnTab cb) {
        super(c);
        n = names.length;
        icons = new ImageView[n];
        labels = new TextView[n];
        badges = new TextView[n];
        setBackgroundColor(Ui.CARD);

        pill = new View(c);
        pill.setBackground(Ui.round(Ui.SOFT, 16));
        pill.setAlpha(0f);
        addView(pill, new FrameLayout.LayoutParams(Ui.dp(40), Ui.dp(46)));

        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        addView(row, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));

        for (int i = 0; i < n; i++) {
            final int idx = i;
            FrameLayout item = new FrameLayout(c);
            item.setClickable(true);
            item.setOnClickListener(v -> {
                if (idx != sel) {
                    select(idx);
                    cb.tab(idx);
                }
            });
            LinearLayout col = new LinearLayout(c);
            col.setOrientation(LinearLayout.VERTICAL);
            col.setGravity(Gravity.CENTER);
            ImageView ic = new ImageView(c);
            ic.setImageResource(res[i]);
            ic.setColorFilter(Ui.MUTED, PorterDuff.Mode.SRC_IN);
            col.addView(ic, new LinearLayout.LayoutParams(Ui.dp(22), Ui.dp(22)));
            TextView lb = Ui.tv(c, names[i], n > 6 ? 10f : 11f, Ui.MUTED, true);
            lb.setSingleLine(true);
            col.addView(lb, Ui.lp(Ui.WRAP, Ui.WRAP, 0, 3, 0, 0));
            item.addView(col, new FrameLayout.LayoutParams(Ui.MATCH, Ui.MATCH));
            TextView bd = Ui.tv(c, "", 10, 0xFFFFFFFF, true);
            bd.setGravity(Gravity.CENTER);
            bd.setBackground(Ui.round(Ui.BAD, 99));
            bd.setMinWidth(Ui.dp(16));
            bd.setMinHeight(Ui.dp(16));
            bd.setPadding(Ui.dp(4), 0, Ui.dp(4), 0);
            bd.setVisibility(View.GONE);
            FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(Ui.WRAP, Ui.WRAP, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
            bp.leftMargin = Ui.dp(26);
            bp.topMargin = Ui.dp(6);
            item.addView(bd, bp);
            row.addView(item, new LinearLayout.LayoutParams(0, Ui.MATCH, 1f));
            icons[i] = ic;
            labels[i] = lb;
            badges[i] = bd;
        }
        View line = new View(c);
        line.setBackgroundColor(Ui.LINE);
        addView(line, new FrameLayout.LayoutParams(Ui.MATCH, 1));
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        itemW = w / n;
        FrameLayout.LayoutParams p = new FrameLayout.LayoutParams(Math.max(1, itemW - Ui.dp(14)), Ui.dp(46));
        p.topMargin = Ui.dp(8);
        pill.setLayoutParams(p);
        pill.setTranslationX(sel >= 0 ? sel * itemW + Ui.dp(7) : 0f);
    }

    /** i &lt; 0 : aucun onglet actif (par exemple les réglages). */
    void select(int i) {
        int old = sel;
        sel = i;
        for (int k = 0; k < n; k++) {
            boolean on = k == i;
            int col = on ? Ui.ACCENT : Ui.MUTED;
            icons[k].setColorFilter(col, PorterDuff.Mode.SRC_IN);
            labels[k].setTextColor(col);
            icons[k].animate().scaleX(on ? 1.15f : 1f).scaleY(on ? 1.15f : 1f).setDuration(220).start();
        }
        if (i < 0) {
            pill.animate().alpha(0f).setDuration(180).start();
            return;
        }
        float x = i * itemW + Ui.dp(7);
        if (old < 0) {
            pill.setTranslationX(x);
            pill.animate().alpha(1f).setDuration(220).start();
        } else {
            pill.animate().alpha(1f).translationX(x).setDuration(340)
                    .setInterpolator(new OvershootInterpolator(0.9f)).start();
        }
    }

    void setBadge(int i, int count) {
        if (i < 0 || i >= n) return;
        TextView b = badges[i];
        if (count <= 0) {
            b.setVisibility(View.GONE);
            return;
        }
        b.setText(count > 99 ? "99+" : String.valueOf(count));
        if (b.getVisibility() != View.VISIBLE) {
            b.setVisibility(View.VISIBLE);
            b.setScaleX(0f);
            b.setScaleY(0f);
            b.animate().scaleX(1f).scaleY(1f).setDuration(300).setInterpolator(new OvershootInterpolator(2f)).start();
        }
    }
}
