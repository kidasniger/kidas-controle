package com.kidas.controle;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.view.View;
import android.view.animation.LinearInterpolator;

/** Rectangle qui brille en attendant les données. */
final class ShimmerView extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Matrix matrix = new Matrix();
    private final RectF rect = new RectF();
    private LinearGradient shader;
    private ValueAnimator anim;
    private float t = 0f;

    ShimmerView(Context c) {
        super(c);
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        shader = new LinearGradient(0, 0, w, 0,
                new int[]{Ui.CARD, Ui.SOFT, Ui.CARD}, new float[]{0f, 0.5f, 1f}, Shader.TileMode.CLAMP);
        paint.setShader(shader);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        anim = ValueAnimator.ofFloat(-1f, 1f);
        anim.setDuration(1300);
        anim.setRepeatCount(ValueAnimator.INFINITE);
        anim.setInterpolator(new LinearInterpolator());
        anim.addUpdateListener(a -> {
            t = (float) a.getAnimatedValue();
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
        if (shader == null) return;
        matrix.setTranslate(t * getWidth(), 0f);
        shader.setLocalMatrix(matrix);
        rect.set(0, 0, getWidth(), getHeight());
        canvas.drawRoundRect(rect, Ui.dp(16), Ui.dp(16), paint);
    }
}
