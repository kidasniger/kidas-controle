package com.kidas.controle;

import android.animation.ObjectAnimator;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.PorterDuff;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.LinearInterpolator;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.text.NumberFormat;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

/** Palette monochrome clair/sombre, fabriques de vues, animations et formats. */
final class Ui {
    static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    /* ---------- palette : uniquement blanc en clair, noir en sombre ---------- */
    static boolean DARK = true;
    static int BG, CARD, SOFT, INK, MUTED, LINE, ACCENT, ACCENT2,
            OK, OKBG, WARN, WARNBG, BAD, BADBG, HSUB, FADED;

    static void theme(boolean dark) {
        DARK = dark;
        if (dark) {
            BG = 0xFF0A0A0B; CARD = 0xFF151517; SOFT = 0xFF1F1F22;
            INK = 0xFFF4F4F5; MUTED = 0xFFA2A2A8; LINE = 0xFF26262A;
        } else {
            BG = 0xFFFFFFFF; CARD = 0xFFF5F5F6; SOFT = 0xFFEBEBEC;
            INK = 0xFF121212; MUTED = 0xFF6B6B70; LINE = 0xFFE6E6E8;
        }
        /* accent = noir en clair, blanc en sombre ; statuts en nuances de gris */
        ACCENT = INK; ACCENT2 = MUTED;
        OK = INK; OKBG = SOFT; WARN = MUTED; WARNBG = SOFT; BAD = INK; BADBG = SOFT;
        HSUB = alpha(BG, 0.62f);
        FADED = alpha(INK, 0.55f);
    }

    static int alpha(int color, float a) {
        return (color & 0x00FFFFFF) | (Math.round(a * 255f) << 24);
    }

    private static float density = 1f;

    static void init(Context c) { density = c.getResources().getDisplayMetrics().density; }

    static int dp(float v) { return Math.round(v * density); }

    /* ---------- fonds ---------- */

    static GradientDrawable round(int color, float r) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(dp(r));
        return g;
    }

    static GradientDrawable roundS(int fill, int stroke, float r) {
        GradientDrawable g = round(fill, r);
        g.setStroke(Math.max(1, dp(1)), stroke);
        return g;
    }

    static GradientDrawable gradient(int c1, int c2, float r) {
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{c1, c2});
        g.setCornerRadius(dp(r));
        return g;
    }

    /* ---------- vues de base ---------- */

    static TextView tv(Context c, CharSequence t, float sp, int color, boolean bold) {
        TextView v = new TextView(c);
        v.setText(t);
        v.setTextSize(sp);
        v.setTextColor(color);
        if (bold) v.setTypeface(Typeface.DEFAULT_BOLD);
        return v;
    }

    static LinearLayout.LayoutParams lp(int w, int h, float l, float t, float r, float b) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(w, h);
        p.setMargins(dp(l), dp(t), dp(r), dp(b));
        return p;
    }

    static LinearLayout vbox(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    static LinearLayout hbox(Context c) {
        LinearLayout l = new LinearLayout(c);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }

    static LinearLayout card(Context c) {
        LinearLayout l = vbox(c);
        l.setBackground(roundS(CARD, LINE, 18));
        int p = dp(16);
        l.setPadding(p, p, p, p);
        return l;
    }

    /** Carte inversée (héro) : fond noir en clair, blanc en sombre. */
    static LinearLayout hero(Context c) {
        LinearLayout l = vbox(c);
        l.setBackground(round(INK, 22));
        int p = dp(18);
        l.setPadding(p, p, p, p);
        return l;
    }

    static TextView h2(Context c, String t) {
        TextView v = tv(c, t.toUpperCase(Locale.FRANCE), 12, MUTED, true);
        v.setLetterSpacing(0.08f);
        return v;
    }

    static TextView label(Context c, String t) {
        TextView v = tv(c, t, 13, MUTED, true);
        v.setPadding(0, dp(14), 0, dp(6));
        return v;
    }

    static ImageView icon(Context c, int res, int color, float sizeDp) {
        ImageView i = new ImageView(c);
        i.setImageResource(res);
        i.setColorFilter(color, PorterDuff.Mode.SRC_IN);
        i.setLayoutParams(new LinearLayout.LayoutParams(dp(sizeDp), dp(sizeDp)));
        return i;
    }

    static EditText edit(Context c, String hint, String text, int lines) {
        EditText e = new EditText(c);
        e.setHint(hint);
        e.setText(text);
        e.setHintTextColor(MUTED);
        e.setTextColor(INK);
        e.setTextSize(16);
        e.setBackground(roundS(BG, LINE, 12));
        e.setPadding(dp(12), dp(12), dp(12), dp(12));
        if (lines > 1) {
            e.setMinLines(lines);
            e.setGravity(Gravity.TOP | Gravity.START);
        } else {
            e.setSingleLine(true);
        }
        return e;
    }

    /** kind : 0 neutre, 1 ok, 2 attention, 3 erreur, 4 en cours — tout en nuances de gris. */
    static TextView chip(Context c, String t, int kind) {
        int fg = MUTED, bg = LINE;
        if (kind == 1) { fg = INK; bg = SOFT; }
        else if (kind == 2) { fg = INK; bg = SOFT; }
        else if (kind == 3) { fg = BG; bg = INK; }
        else if (kind == 4) { fg = MUTED; bg = SOFT; }
        TextView v = tv(c, t, 12, fg, true);
        v.setBackground(round(bg, 99));
        v.setPadding(dp(10), dp(3), dp(10), dp(3));
        return v;
    }

    static ShimmerView skeleton(Context c, float heightDp) {
        ShimmerView s = new ShimmerView(c);
        s.setLayoutParams(new LinearLayout.LayoutParams(MATCH, dp(heightDp)));
        return s;
    }

    /** Tuile chiffre : l'icône, le libellé et la valeur (TextView dans le tag). */
    static LinearLayout kpi(Context c, int iconRes, int tint, String label) {
        LinearLayout k = vbox(c);
        k.setBackground(roundS(CARD, LINE, 16));
        k.setPadding(dp(14), dp(12), dp(14), dp(12));
        LinearLayout top = hbox(c);
        top.addView(icon(c, iconRes, tint, 16));
        TextView l = tv(c, label, 12, MUTED, false);
        top.addView(l, lp(WRAP, WRAP, 6, 0, 0, 0));
        k.addView(top);
        TextView v = tv(c, "-", 26, INK, true);
        k.addView(v, lp(WRAP, WRAP, 0, 4, 0, 0));
        k.setTag(v);
        return k;
    }

    static TextView kpiValue(View k) { return (TextView) k.getTag(); }

    static LinearLayout row2(Context c, View a, View b) {
        LinearLayout r = new LinearLayout(c);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.addView(a, lp(0, WRAP, 0, 0, 5, 0));
        ((LinearLayout.LayoutParams) a.getLayoutParams()).weight = 1f;
        r.addView(b, lp(0, WRAP, 5, 0, 0, 0));
        ((LinearLayout.LayoutParams) b.getLayoutParams()).weight = 1f;
        return r;
    }

    /* ---------- bouton ---------- */

    /** kind : 0 neutre, 1 principal (noir/blanc inversé), 2 danger, 3 ok. */
    static final class Btn extends LinearLayout {
        final ImageView icon;
        final TextView label;
        private final int iconRes;
        private ObjectAnimator spin;

        Btn(Context c, String t, int iconRes, int kind) {
            super(c);
            this.iconRes = iconRes;
            setOrientation(HORIZONTAL);
            setGravity(Gravity.CENTER);
            int fg = INK, bg = SOFT, st = LINE;
            if (kind == 1) { bg = ACCENT; fg = BG; st = ACCENT; }
            else if (kind == 2) { bg = BADBG; fg = BAD; st = BADBG; }
            else if (kind == 3) { bg = OKBG; fg = OK; st = OKBG; }
            setBackground(roundS(bg, st, 12));
            setMinimumHeight(dp(44));
            setPadding(dp(14), 0, dp(14), 0);
            setClickable(true);
            setFocusable(true);
            icon = new ImageView(c);
            icon.setColorFilter(fg, PorterDuff.Mode.SRC_IN);
            addView(icon, new LinearLayout.LayoutParams(dp(18), dp(18)));
            if (iconRes != 0) icon.setImageResource(iconRes); else icon.setVisibility(GONE);
            label = new TextView(c);
            label.setText(t);
            label.setTextColor(fg);
            label.setTextSize(14.5f);
            label.setTypeface(Typeface.DEFAULT_BOLD);
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(WRAP, WRAP);
            p.leftMargin = iconRes != 0 ? dp(8) : 0;
            addView(label, p);
            press(this);
        }

        void setBusy(boolean busy) {
            setEnabled(!busy);
            setAlpha(busy ? 0.6f : 1f);
            if (busy) {
                icon.setVisibility(VISIBLE);
                icon.setImageResource(R.drawable.ic_refresh);
                spin = ObjectAnimator.ofFloat(icon, "rotation", 0f, 360f);
                spin.setDuration(800);
                spin.setRepeatCount(ValueAnimator.INFINITE);
                spin.setInterpolator(new LinearInterpolator());
                spin.start();
            } else {
                if (spin != null) { spin.cancel(); spin = null; }
                icon.setRotation(0f);
                if (iconRes != 0) icon.setImageResource(iconRes); else icon.setVisibility(GONE);
            }
        }
    }

    static Btn btn(Context c, String t, int iconRes, int kind) { return new Btn(c, t, iconRes, kind); }

    /* ---------- animations ---------- */

    static void press(final View v) {
        v.setOnTouchListener((x, e) -> {
            int a = e.getActionMasked();
            if (a == MotionEvent.ACTION_DOWN) {
                x.animate().scaleX(0.96f).scaleY(0.96f).setDuration(90).start();
            } else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL) {
                x.animate().scaleX(1f).scaleY(1f).setDuration(150).start();
            }
            return false;
        });
    }

    static void reveal(final View v, int i) {
        v.setAlpha(0f);
        v.setTranslationY(dp(24));
        v.animate().alpha(1f).translationY(0f)
                .setStartDelay(Math.min(i, 10) * 55L)
                .setDuration(400)
                .setInterpolator(new DecelerateInterpolator(1.6f))
                .withEndAction(() -> v.animate().setStartDelay(0))
                .start();
    }

    static void countUp(final TextView t, final double to) {
        ValueAnimator a = ValueAnimator.ofFloat(0f, 1f);
        a.setDuration(950);
        a.setInterpolator(new DecelerateInterpolator(2f));
        a.addUpdateListener(x -> t.setText(nf(to * (float) x.getAnimatedValue())));
        a.start();
    }

    /* ---------- formats ---------- */

    static String nf(double v) {
        return NumberFormat.getIntegerInstance(Locale.FRANCE).format(Math.round(v));
    }

    static String pct(double last, double prev) {
        if (prev == 0) return "";
        double p = (last - prev) / Math.abs(prev) * 100.0;
        return (p >= 0 ? "+" : "") + String.format(Locale.FRANCE, "%.1f", p) + " %";
    }

    static String isoNow() { return isoOf(System.currentTimeMillis()); }

    static String isoOf(long ms) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        f.setTimeZone(TimeZone.getTimeZone("UTC"));
        return f.format(new Date(ms));
    }

    static long iso(String s) {
        if (s == null || s.isEmpty()) return -1;
        String[] pats = {"yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ssZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd"};
        for (String p : pats) {
            try {
                Date d = new SimpleDateFormat(p, Locale.US).parse(s);
                if (d != null) return d.getTime();
            } catch (Exception e) { /* essai suivant */ }
        }
        return -1;
    }

    static String dur(long ms) {
        long s = Math.round(ms / 1000.0);
        if (s < 60) return s + " s";
        long m = s / 60;
        if (m < 60) return m + " min";
        long h = m / 60;
        if (h < 24) return h + " h " + (m % 60) + " min";
        return (h / 24) + " j " + (h % 24) + " h";
    }

    static String rel(long ms) {
        if (ms < 0) return "";
        double s = (System.currentTimeMillis() - ms) / 1000.0;
        if (s < 0) return "dans " + dur((long) (-s * 1000));
        if (s < 45) return "à l'instant";
        if (s < 3600) return "il y a " + Math.round(s / 60) + " min";
        if (s < 86400) return "il y a " + Math.round(s / 3600) + " h";
        return "il y a " + Math.round(s / 86400) + " j";
    }

    static String rel(String iso) { return rel(iso(iso)); }

    static String fdate(long ms) {
        if (ms < 0) return "";
        return new SimpleDateFormat("dd MMM HH:mm", Locale.FRANCE).format(new Date(ms));
    }

    static String fsize(long n) {
        if (n > 1048576) return String.format(Locale.FRANCE, "%.1f", n / 1048576.0) + " Mo";
        return Math.max(1, Math.round(n / 1024.0)) + " Ko";
    }
}
