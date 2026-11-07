package com.kidas.controle;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;
import android.view.animation.LinearInterpolator;

/** Barres qui poussent les unes après les autres. */
final class BarChartView extends View {
    private float[] vals = new float[0];
    private String[] labs = null;
    private int color = Ui.ACCENT;
    private float prog = 0f;
    private ValueAnimator anim;
    private final Paint pBar = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pTxt = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();

    BarChartView(Context c) {
        super(c);
        pTxt.setTextSize(Ui.dp(11));
        pTxt.setTextAlign(Paint.Align.CENTER);
    }

    void setData(float[] v, String[] l, int c) {
        vals = v == null ? new float[0] : v;
        labs = (l != null && l.length == vals.length) ? l : null;
        color = c;
        if (anim != null) anim.cancel();
        anim = ValueAnimator.ofFloat(0f, 1f);
        anim.setDuration(1100);
        anim.setInterpolator(new LinearInterpolator());
        anim.addUpdateListener(a -> {
            prog = (float) a.getAnimatedValue();
            invalidate();
        });
        anim.start();
    }

    @Override
    protected void onDetachedFromWindow() {
        if (anim != null) anim.cancel();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        int n = vals.length;
        int w = getWidth(), h = getHeight();
        if (n == 0) {
            pTxt.setColor(Ui.MUTED);
            canvas.drawText("Pas de données", w / 2f, h / 2f, pTxt);
            return;
        }
        float l = Ui.dp(6), r = w - Ui.dp(6), t = Ui.dp(24), b = h - Ui.dp(24);
        float gap = Ui.dp(8);
        float bw = (r - l - gap * (n - 1)) / n;
        float max = 1f;
        for (float v : vals) if (v > max) max = v;
        for (int i = 0; i < n; i++) {
            float p = Math.max(0f, Math.min(1f, (prog * (n + 3f) - i) / 3f));
            p = 1f - (1f - p) * (1f - p) * (1f - p);
            float x = l + i * (bw + gap);
            float bh = Math.max(0f, vals[i]) / max * (b - t) * p;
            pBar.setColor(color);
            pBar.setAlpha(i == n - 1 ? 255 : 150);
            rect.set(x, b - bh, x + bw, b);
            canvas.drawRoundRect(rect, Ui.dp(6), Ui.dp(6), pBar);
            if (p > 0.85f) {
                pTxt.setColor(Ui.INK);
                canvas.drawText(Ui.nf(vals[i]), x + bw / 2f, b - bh - Ui.dp(6), pTxt);
            }
            if (labs != null) {
                pTxt.setColor(Ui.MUTED);
                canvas.drawText(labs[i], x + bw / 2f, h - Ui.dp(6), pTxt);
            }
        }
    }
}
