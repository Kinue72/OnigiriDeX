package moe.foss.onigiri.settings;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

/**
 * The picture above the Space around zones slider: the top left corner of a DeX desktop with
 * three snapped windows, in the colours of the zone layout pictures. Its level is the space in
 * pixels, drawn at the size it has on a DeX desktop at its usual 240 dpi.
 */
final class DexZoneGapDemo extends Drawable {
    private static final float DEX_DENSITY = 1.5f;

    private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path mClip = new Path();
    private final float mDensity;
    private final boolean mNight;

    DexZoneGapDemo(Context context) {
        mDensity = context.getResources().getDisplayMetrics().density;
        mNight = (context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
    }

    @Override
    protected boolean onLevelChange(int level) {
        invalidateSelf();
        return true;
    }

    @Override
    public void draw(Canvas canvas) {
        Rect box = getBounds();
        float radius = 12 * mDensity;
        float gap = getLevel() * mDensity / DEX_DENSITY;
        // The lines between the windows; the windows run on past the right and bottom edges.
        float column = box.left + gap + box.width() * 0.4f;
        float row = box.top + gap + box.height() * 0.55f;
        float right = box.right + radius;
        float bottom = box.bottom + radius;
        canvas.save();
        mClip.rewind();
        mClip.addRoundRect(box.left, box.top, box.right, box.bottom, radius, radius, Path.Direction.CW);
        canvas.clipPath(mClip);
        canvas.drawColor(mNight ? 0xff3a3a3d : 0xffeeeef0);
        mPaint.setColor(mNight ? 0xff5c5c61 : 0xffcfcfd4);
        canvas.drawRoundRect(box.left + gap, box.top + gap, column - gap, bottom, radius, radius, mPaint);
        canvas.drawRoundRect(column, row, right, bottom, radius, radius, mPaint);
        mPaint.setColor(0xff387aff);
        canvas.drawRoundRect(column, box.top + gap, right, row - gap, radius, radius, mPaint);
        canvas.restore();
    }

    @Override
    public void setAlpha(int alpha) {
    }

    @Override
    public void setColorFilter(ColorFilter filter) {
    }

    @Override
    public int getOpacity() {
        return PixelFormat.TRANSLUCENT;
    }
}
