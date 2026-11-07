package com.kidas.controle;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PathMeasure;
import android.graphics.RectF;
import android.graphics.Shader;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.animation.DecelerateInterpolator;

/** Courbe lissée qui se dessine, avec zone dégradée et info-bulle au toucher. */
final class LineChartView extends View {
    private float[] vals = new float[0];
    private String[] labs = null;
    private float[] xs = new float[0];
    private float[] ys = new float[0];
    private int color = Ui.ACCENT;
    private float prog = 0f;
    private int sel = -1;
    private ValueAnimator anim;
    private float downX, downY;
    private final int slop;

    private final Paint pLine = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pFill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pGrid = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pTxt = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint pDot = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final Path seg = new Path();
    private final Path fillP = new Path();
    private final float[] pos = new float[2];
    private final RectF bubble = new RectF();

    LineChartView(Context c) {
        super(c);
        slop = ViewConfiguration.get(c).getScaledTouchSlop();
        pLine.setStyle(Paint.Style.STROKE);
        pLine.setStrokeWidth(Ui.dp(3));
        pLine.setStrokeCap(Paint.Cap.ROUND);
        pLine.setStrokeJoin(Paint.Join.ROUND);
        pFill.setStyle(Paint.Style.FILL);
        pGrid.setStyle(Paint.Style.STROKE);
        pGrid.setStrokeWidth(Math.max(1, Ui.dp(1)));
        pGrid.setColor(Ui.LINE);
        pTxt.setTextSize(Ui.dp(11));
        pTxt.setColor(Ui.MUTED);
    }

    void setData(float[] v, String[] l, int c) {
        vals = v == null ? new float[0] : v;
        labs = (l != null && l.length == vals.length) ? l : null;
        color = c;
        sel = -1;
        xs = new float[vals.length];
        ys = new float[vals.length];
        play();
    }

    void play() {
        if (anim != null) anim.cancel();
        anim = ValueAnimator.ofFloat(0f, 1f);
        anim.setDuration(1200);
        anim.setInterpolator(new DecelerateInterpolator(1.6f));
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
        int w = getWidth(), h = getHeight();
        float l = Ui.dp(10), r = w - Ui.dp(10), t = Ui.dp(26), b = h - Ui.dp(26);
        for (int k = 0; k < 4; k++) {
            float y = t + (b - t) * k / 3f;
            canvas.drawLine(l, y, r, y, pGrid);
        }
        int n = vals.length;
        if (n < 2) {
            pTxt.setTextAlign(Paint.Align.CENTER);
            canvas.drawText("Pas assez de données", w / 2f, h / 2f, pTxt);
            return;
        }
        float mn = vals[0], mx = vals[0];
        for (float v : vals) {
            if (v < mn) mn = v;
            if (v > mx) mx = v;
        }
        float lo = mn, hi = mx;
        if (hi - lo < 1e-6f) { lo -= 1f; hi += 1f; }
        float pad = (hi - lo) * 0.08f;
        lo -= pad;
        hi += pad;
        for (int i = 0; i < n; i++) {
            xs[i] = l + (r - l) * i / (n - 1f);
            ys[i] = b - (vals[i] - lo) / (hi - lo) * (b - t);
        }
        path.reset();
        path.moveTo(xs[0], ys[0]);
        for (int i = 1; i < n; i++) {
            float cx = (xs[i - 1] + xs[i]) / 2f;
            path.cubicTo(cx, ys[i - 1], cx, ys[i], xs[i], ys[i]);
        }
        PathMeasure pm = new PathMeasure(path, false);
        float len = pm.getLength();
        seg.reset();
        pm.getSegment(0f, len * prog, seg, true);
        pm.getPosTan(len * prog, pos, null);

        int base = color & 0x00FFFFFF;
        pFill.setShader(new LinearGradient(0, t, 0, b, base | 0x66000000, base, Shader.TileMode.CLAMP));
        fillP.reset();
        fillP.addPath(seg);
        fillP.lineTo(pos[0], b);
        fillP.lineTo(xs[0], b);
        fillP.close();
        canvas.drawPath(fillP, pFill);
        pLine.setColor(color);
        canvas.drawPath(seg, pLine);

        pTxt.setTextAlign(Paint.Align.LEFT);
        pTxt.setColor(Ui.MUTED);
        canvas.drawText(Ui.nf(mx), l, t - Ui.dp(8), pTxt);
        canvas.drawText(Ui.nf(mn), l, b - Ui.dp(6), pTxt);
        if (labs != null) {
            float ly = h - Ui.dp(6);
            pTxt.setTextAlign(Paint.Align.LEFT);
            canvas.drawText(labs[0], l, ly, pTxt);
            pTxt.setTextAlign(Paint.Align.RIGHT);
            canvas.drawText(labs[n - 1], r, ly, pTxt);
            if (n > 4) {
                pTxt.setTextAlign(Paint.Align.CENTER);
                canvas.drawText(labs[n / 2], xs[n / 2], ly, pTxt);
            }
        }

        pDot.setStyle(Paint.Style.FILL);
        if (sel >= 0 && sel < n) {
            pGrid.setColor(color & 0x66FFFFFF);
            canvas.drawLine(xs[sel], t, xs[sel], b, pGrid);
            pGrid.setColor(Ui.LINE);
            pDot.setColor(color);
            canvas.drawCircle(xs[sel], ys[sel], Ui.dp(6), pDot);
            pDot.setColor(Ui.CARD);
            canvas.drawCircle(xs[sel], ys[sel], Ui.dp(3), pDot);
            String txt = Ui.nf(vals[sel]) + (labs != null ? "  " + labs[sel] : "");
            pTxt.setTextAlign(Paint.Align.LEFT);
            pTxt.setColor(Ui.INK);
            float tw = pTxt.measureText(txt);
            float bw = tw + Ui.dp(20), bh = Ui.dp(26);
            float bx = Math.max(Ui.dp(2), Math.min(w - bw - Ui.dp(2), xs[sel] - bw / 2f));
            float by = Math.max(Ui.dp(2), ys[sel] - Ui.dp(40));
            bubble.set(bx, by, bx + bw, by + bh);
            pDot.setColor(Ui.SOFT);
            canvas.drawRoundRect(bubble, Ui.dp(10), Ui.dp(10), pDot);
            canvas.drawText(txt, bx + Ui.dp(10), by + bh / 2f + Ui.dp(4), pTxt);
            pTxt.setColor(Ui.MUTED);
        } else if (prog > 0.98f) {
            pDot.setColor(color);
            canvas.drawCircle(xs[n - 1], ys[n - 1], Ui.dp(5), pDot);
            pDot.setColor(color & 0x55FFFFFF);
            canvas.drawCircle(xs[n - 1], ys[n - 1], Ui.dp(9), pDot);
        }
    }

    private int nearest(float x) {
        int n = vals.length;
        if (n < 2) return -1;
        float l = Ui.dp(10), r = getWidth() - Ui.dp(10);
        int i = Math.round((x - l) / (r - l) * (n - 1));
        return Math.max(0, Math.min(n - 1, i));
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        switch (e.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                downX = e.getX();
                downY = e.getY();
                sel = nearest(downX);
                invalidate();
                return true;
            case MotionEvent.ACTION_MOVE:
                float dx = Math.abs(e.getX() - downX), dy = Math.abs(e.getY() - downY);
                if (dx > slop && dx > dy) {
                    if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(true);
                    sel = nearest(e.getX());
                    invalidate();
                }
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (getParent() != null) getParent().requestDisallowInterceptTouchEvent(false);
                return true;
            default:
                return super.onTouchEvent(e);
        }
    }
}
