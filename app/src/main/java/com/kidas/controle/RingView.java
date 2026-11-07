package com.kidas.controle;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.view.View;
import android.view.animation.DecelerateInterpolator;

/** Anneau de progression animé avec pourcentage au centre. */
final class RingView extends View {
    private float target = 0f;
    private float prog = 0f;
    private int color = Ui.ACCENT;
    private ValueAnimator anim;
    private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint arc = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint txt = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();

    RingView(Context c) {
        super(c);
        track.setStyle(Paint.Style.STROKE);
        track.setColor(Ui.LINE);
        arc.setStyle(Paint.Style.STROKE);
        arc.setStrokeCap(Paint.Cap.ROUND);
        txt.setTextAlign(Paint.Align.CENTER);
        txt.setColor(Ui.INK);
        txt.setTypeface(Typeface.DEFAULT_BOLD);
    }

    void set(float p, int c) {
        target = Math.max(0f, Math.min(1f, p));
        color = c;
        if (anim != null) anim.cancel();
        anim = ValueAnimator.ofFloat(0f, 1f);
        anim.setDuration(1300);
        anim.setInterpolator(new DecelerateInterpolator(2f));
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
        float w = getWidth(), h = getHeight();
        float s = Math.min(w, h);
        float sw = s * 0.12f;
        track.setStrokeWidth(sw);
        arc.setStrokeWidth(sw);
        arc.setColor(color);
        float rad = s / 2f - sw;
        float cx = w / 2f, cy = h / 2f;
        rect.set(cx - rad, cy - rad, cx + rad, cy + rad);
        canvas.drawCircle(cx, cy, rad, track);
        canvas.drawArc(rect, -90f, 360f * target * prog, false, arc);
        txt.setTextSize(s * 0.26f);
        canvas.drawText(Math.round(target * prog * 100f) + "%", cx, cy + s * 0.09f, txt);
    }
}
