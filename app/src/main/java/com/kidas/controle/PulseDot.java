package com.kidas.controle;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.View;
import android.view.animation.DecelerateInterpolator;

/** Pastille d'état avec onde qui pulse. */
final class PulseDot extends View {
    private final Paint core = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint ring = new Paint(Paint.ANTI_ALIAS_FLAG);
    private ValueAnimator anim;
    private float t = 0f;
    private boolean pulse = true;
    private int color = Ui.MUTED;

    PulseDot(Context c) {
        super(c);
        ring.setStyle(Paint.Style.STROKE);
        ring.setStrokeWidth(Ui.dp(2));
    }

    void set(int color, boolean pulse) {
        this.color = color;
        this.pulse = pulse;
        restart();
        invalidate();
    }

    private void restart() {
        if (anim != null) anim.cancel();
        if (!pulse || !isAttachedToWindow()) return;
        anim = ValueAnimator.ofFloat(0f, 1f);
        anim.setDuration(1600);
        anim.setRepeatCount(ValueAnimator.INFINITE);
        anim.setInterpolator(new DecelerateInterpolator());
        anim.addUpdateListener(a -> {
            t = (float) a.getAnimatedValue();
            invalidate();
        });
        anim.start();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        restart();
    }

    @Override
    protected void onDetachedFromWindow() {
        if (anim != null) anim.cancel();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onMeasure(int w, int h) {
        setMeasuredDimension(Ui.dp(44), Ui.dp(44));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        float cx = getWidth() / 2f, cy = getHeight() / 2f;
        float r = Ui.dp(8);
        if (pulse) {
            float rr = r + (getWidth() / 2f - r) * t;
            ring.setColor(color);
            ring.setAlpha((int) (200 * (1f - t)));
            canvas.drawCircle(cx, cy, rr, ring);
        }
        core.setColor(color);
        canvas.drawCircle(cx, cy, r, core);
    }
}
