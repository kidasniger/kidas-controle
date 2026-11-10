package com.kidas.controle;

import android.animation.ArgbEvaluator;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;
import android.view.animation.OvershootInterpolator;

/** Interrupteur animé. */
final class ToggleView extends View {
    interface OnToggle { void on(boolean v); }

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();
    private final ArgbEvaluator ev = new ArgbEvaluator();
    private boolean checked;
    private float t = 0f;
    private ValueAnimator anim;
    private OnToggle cb;

    ToggleView(Context c) {
        super(c);
        setClickable(true);
        setOnClickListener(v -> {
            setChecked(!checked, true);
            if (cb != null) cb.on(checked);
        });
    }

    void setOnToggle(OnToggle c) { cb = c; }

    boolean isOn() { return checked; }

    void setChecked(boolean v, boolean animate) {
        checked = v;
        float to = v ? 1f : 0f;
        if (anim != null) anim.cancel();
        if (!animate) {
            t = to;
            invalidate();
            return;
        }
        anim = ValueAnimator.ofFloat(t, to);
        anim.setDuration(260);
        anim.setInterpolator(new OvershootInterpolator(1.4f));
        anim.addUpdateListener(a -> {
            t = (float) a.getAnimatedValue();
            invalidate();
        });
        anim.start();
    }

    @Override
    protected void onMeasure(int w, int h) {
        setMeasuredDimension(Ui.dp(52), Ui.dp(32));
    }

    @Override
    protected void onDraw(Canvas canvas) {
        float w = getWidth(), h = getHeight();
        float tt = Math.max(0f, Math.min(1f, t));
        paint.setColor((Integer) ev.evaluate(tt, Ui.SOFT, Ui.OK));
        rect.set(0, 0, w, h);
        canvas.drawRoundRect(rect, h / 2f, h / 2f, paint);
        float pad = Ui.dp(3);
        float r = h / 2f - pad;
        float x = pad + r + t * (w - 2 * (pad + r));
        paint.setColor(Ui.BG);
        canvas.drawCircle(x, h / 2f, r, paint);
    }
}
