package com.honeyspace.ui.honeypots.homescreen.screengrid;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Rect;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.lifecycle.ViewModelKt;
import com.honeyspace.common.context.ContextExtensionKt;
import com.honeyspace.common.interfaces.SupportedGridStyle;
import com.honeyspace.ui.honeypots.homescreen.viewmodel.HomeGridViewModel;
import java.util.Locale;
import kotlin.jvm.internal.Ref;
import kotlinx.coroutines.BuildersKt;
import v3.f;

/**
 * Onigiri: Home screen grid editor on the primary cover.
 *
 * Stock One UI Home reuses its phone landscape layout here: the title and Cancel/Done share
 * one row and collide on the 748 px cover, and the size chips only offer the hardcoded
 * GridList.foldableCoverGridList (4x6, 5x6). On the cover this puts Cancel, title and Done on
 * one row, and replaces the chips with a column stepper under the preview and a row stepper
 * beside it. A step does what a chip tap does (selects the grid in HomeGridViewModel.k and emits
 * "UpdateHomeGrid"), so the stock preview, Done and Cancel paths handle the rest.
 */
public final class OnigiriCoverGridControls
        implements View.OnClickListener, ViewTreeObserver.OnPreDrawListener, View.OnAttachStateChangeListener {

    // Visual columns and rows. The cover is landscape, so the launcher's portrait grid point is
    // transposed on screen: x is the row count, y the column count. Rows stop at 4: on restart
    // GridController reads a saved 5 as 4 rows and leaves 6 or more untransposed.
    private static final int MIN_COLS = 3, MAX_COLS = 7, MIN_ROWS = 3, MAX_ROWS = 4;

    private static final int ID_PANEL = 0x7f0a0498; // R.id.screen_grid_panel, the tag key
    private static final int ID_TITLE_LAYOUT = 0x7f0a049b; // R.id.screen_grid_title_layout
    private static final int ID_TITLE = 0x7f0a049a; // R.id.screen_grid_title
    private static final int ID_ACTIONS = 0x7f0a0101; // R.id.cancel_save_button_layout
    private static final int ID_CHIPS = 0x7f0a0496; // R.id.screen_grid_buttons
    private static final String PAGE =
            "com.honeyspace.ui.honeypots.workspace.presentation.WorkspaceCellLayoutContainer";

    private final ScreenGridPanel panel;
    private HomeGridViewModel vm;
    private final LinearLayout colPill, rowPill;
    private final TextView colMinus, colValue, colPlus, rowPlus, rowValue, rowMinus;
    private boolean active, saved;
    private float stockTitleSize, stockButtonSize;
    private int stockTitleGravity, color;
    private String shown;
    private ViewGroup pages;
    private final Rect rect = new Rect();
    private final int[] loc = new int[2];

    /** Called by ScreenGridPanel.b() after it clears the chip row. True: skip the stock chips. */
    public static boolean bind(ScreenGridPanel panel, HomeGridViewModel vm, SupportedGridStyle style) {
        boolean cover = vm != null && style.isCoverGridState()
                && ContextExtensionKt.isPrimaryCoverDisplay(panel.getContext());
        OnigiriCoverGridControls c = get(panel, cover);
        if (c == null) return false;
        c.vm = vm;
        c.setActive(cover);
        return cover;
    }

    /** ScreenGridPanel.onMeasure, before super: drop the cover layout once the panel leaves the cover. */
    public static void beforeMeasure(ScreenGridPanel panel) {
        OnigiriCoverGridControls c = get(panel, false);
        if (c != null && c.active && !ContextExtensionKt.isPrimaryCoverDisplay(panel.getContext())) {
            c.setActive(false);
        }
    }

    /** ScreenGridPanel.onLayout, after super: one row for Cancel, title and Done. */
    public static void afterLayout(ScreenGridPanel panel) {
        OnigiriCoverGridControls c = get(panel, false);
        if (c != null && c.active) c.layoutBar();
    }

    private static OnigiriCoverGridControls get(ScreenGridPanel panel, boolean create) {
        Object tag = panel.getTag(ID_PANEL);
        if (tag instanceof OnigiriCoverGridControls) return (OnigiriCoverGridControls) tag;
        if (!create) return null;
        OnigiriCoverGridControls c = new OnigiriCoverGridControls(panel);
        panel.setTag(ID_PANEL, c);
        return c;
    }

    private OnigiriCoverGridControls(ScreenGridPanel panel) {
        this.panel = panel;
        Context ctx = panel.getContext();
        colPill = pill(ctx, LinearLayout.HORIZONTAL);
        colMinus = step(ctx, colPill, "−", "Fewer columns");
        colValue = value(ctx, colPill, false);
        colPlus = step(ctx, colPill, "+", "More columns");
        rowPill = pill(ctx, LinearLayout.VERTICAL);
        rowPlus = step(ctx, rowPill, "+", "More rows");
        rowValue = value(ctx, rowPill, true);
        rowMinus = step(ctx, rowPill, "−", "Fewer rows");
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.LEFT);
        panel.addView(colPill, lp);
        panel.addView(rowPill, new FrameLayout.LayoutParams(lp));
        panel.addOnAttachStateChangeListener(this);
        if (panel.isAttachedToWindow()) onViewAttachedToWindow(panel);
    }

    private void setActive(boolean on) {
        TextView title = panel.findViewById(ID_TITLE);
        Button done = panel.e, cancel = panel.f;
        if (on) {
            if (title != null && done != null && cancel != null) {
                if (!saved) {
                    stockTitleSize = title.getTextSize();
                    stockTitleGravity = title.getGravity();
                    stockButtonSize = cancel.getTextSize();
                    saved = true;
                }
                title.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 18);
                title.setGravity(Gravity.CENTER);
                cancel.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 17);
                done.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 17);
            }
            shown = null;
            refresh();
        } else if (active && saved && title != null && done != null && cancel != null) {
            title.setTextSize(TypedValue.COMPLEX_UNIT_PX, stockTitleSize);
            title.setGravity(stockTitleGravity);
            cancel.setTextSize(TypedValue.COMPLEX_UNIT_PX, stockButtonSize);
            done.setTextSize(TypedValue.COMPLEX_UNIT_PX, stockButtonSize);
        }
        active = on;
        int visibility = on ? View.VISIBLE : View.GONE;
        colPill.setVisibility(visibility);
        rowPill.setVisibility(visibility);
    }

    private void layoutBar() {
        View title = panel.findViewById(ID_TITLE_LAYOUT);
        View actions = panel.findViewById(ID_ACTIONS);
        Button done = panel.e, cancel = panel.f;
        if (title == null || actions == null || done == null || cancel == null) return;
        int w = panel.getWidth(), edge = dp(12);
        actions.layout(0, actions.getTop(), w, actions.getBottom());
        int cw = cancel.getMeasuredWidth(), dw = done.getMeasuredWidth();
        cancel.layout(edge, cancel.getTop(), edge + cw, cancel.getBottom());
        done.layout(w - edge - dw, done.getTop(), w - edge, done.getBottom());
        // Buttons center their text in a min-width box: keep the title clear of the text only.
        int side = Math.max((cw + textWidth(cancel)) / 2, (dw + textWidth(done)) / 2);
        int avail = w - 2 * (edge + side + dp(8));
        int tw = title.getMeasuredWidth(), th = title.getMeasuredHeight();
        if (tw > avail) {
            tw = Math.max(avail, 0);
            title.measure(View.MeasureSpec.makeMeasureSpec(tw, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(th, View.MeasureSpec.EXACTLY));
        }
        int left = (w - tw) / 2, top = actions.getTop() + (actions.getHeight() - th) / 2;
        title.layout(left, top, left + tw, top + th);
        place();
    }

    private static int textWidth(TextView t) {
        return (int) Math.ceil(t.getPaint().measureText(t.getText().toString()));
    }

    @Override
    public boolean onPreDraw() {
        if (active && panel.isShown()) {
            refresh();
            place();
        }
        return true;
    }

    /**
     * Column stepper under the preview, row stepper centered in the gap left of it (the next page
     * peeks in on the right), or right of it when the left gap is too narrow.
     */
    private void place() {
        Rect p = preview();
        View chips = panel.findViewById(ID_CHIPS);
        if (p == null || chips == null) return;
        int pw = rowPill.getWidth(), ph = rowPill.getHeight();
        float rx = p.left >= pw + dp(8) ? (p.left - pw) / 2f : (p.right + panel.getWidth() - pw) / 2f;
        rowPill.setTranslationX(rx);
        rowPill.setTranslationY(p.centerY() - ph / 2f);
        colPill.setTranslationX(p.centerX() - colPill.getWidth() / 2f);
        colPill.setTranslationY(chips.getTop() + (chips.getHeight() - colPill.getHeight()) / 2f);
    }

    /** The current workspace page card in panel coordinates: the most visible page container. */
    private Rect preview() {
        if (pages == null || !pages.isAttachedToWindow()) {
            View page = find(panel.getRootView());
            pages = page != null && page.getParent() instanceof ViewGroup ? (ViewGroup) page.getParent() : null;
            if (pages == null) return null;
        }
        int best = 0, l = 0, t = 0, r = 0, b = 0;
        for (int i = 0; i < pages.getChildCount(); i++) {
            View v = pages.getChildAt(i);
            if (!v.isShown() || !v.getGlobalVisibleRect(rect)) continue;
            int area = rect.width() * rect.height();
            if (area > best) {
                best = area;
                l = rect.left;
                t = rect.top;
                r = rect.right;
                b = rect.bottom;
            }
        }
        if (best == 0) return null;
        panel.getLocationInWindow(loc);
        rect.set(l - loc[0], t - loc[1], r - loc[0], b - loc[1]);
        return rect;
    }

    private static View find(View v) {
        if (PAGE.equals(v.getClass().getName())) return v;
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) {
                View found = find(g.getChildAt(i));
                if (found != null) return found;
            }
        }
        return null;
    }

    @Override
    public void onClick(View v) {
        int[] grid = grid();
        if (grid == null) return;
        int rows = grid[0], cols = grid[1];
        if (v == colMinus) cols--;
        else if (v == colPlus) cols++;
        else if (v == rowMinus) rows--;
        else if (v == rowPlus) rows++;
        // What a stock chip tap does (l3.h): select the grid, then emit "UpdateHomeGrid" with its
        // name, which redraws the workspace preview. The workspace keeps a landscape grid inverted
        // (columns first) and its handler takes the name as is, so send it in that order.
        vm.k.setValue(vm.b(rows, cols));
        boolean inverted = ContextExtensionKt.getInversionGrid(panel.getContext());
        Ref.ObjectRef name = new Ref.ObjectRef();
        name.element = SupportedGridStyle.Companion.formatGridName(vm.c,
                inverted ? cols + "x" + rows : rows + "x" + cols, "x");
        BuildersKt.launch$default(ViewModelKt.getViewModelScope(vm), null, null, new f(vm, name, null), 3, null);
        refresh();
    }

    /** Rows and columns of the editor's selected grid, or null. */
    private int[] grid() {
        if (vm == null) return null;
        Object value = vm.k.getValue();
        if (!(value instanceof String)) return null;
        String[] parts = ((String) value).split("x");
        if (parts.length != 2) return null;
        boolean swapped = vm.d(); // Arabic digit locales store "YxX"
        try {
            // A saved 5 rows (stock 5x6) already loads as 4, so show and step from that.
            int rows = Math.min(Integer.parseInt(parts[swapped ? 1 : 0]), MAX_ROWS);
            return new int[] {rows, Integer.parseInt(parts[swapped ? 0 : 1])};
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private void refresh() {
        TextView title = panel.findViewById(ID_TITLE);
        int c = title != null ? title.getCurrentTextColor() : 0xfffafaff;
        if (c != color) recolor(c);
        Object value = vm != null ? vm.k.getValue() : null;
        if (value == null || value.equals(shown)) return;
        shown = value.toString();
        int[] grid = grid();
        if (grid == null) return;
        int rows = grid[0], cols = grid[1];
        Locale locale = panel.getResources().getConfiguration().getLocales().get(0);
        colValue.setText(String.format(locale, "%d", cols));
        rowValue.setText(String.format(locale, "%d", rows));
        colValue.setContentDescription(cols + " columns");
        rowValue.setContentDescription(rows + " rows");
        enable(colMinus, cols > MIN_COLS);
        enable(colPlus, cols < MAX_COLS);
        enable(rowMinus, rows > MIN_ROWS);
        enable(rowPlus, rows < MAX_ROWS);
    }

    private static void enable(View v, boolean on) {
        v.setEnabled(on);
        v.setAlpha(on ? 1f : 0.3f);
    }

    private void recolor(int c) {
        color = c;
        int rgb = c & 0x00ffffff;
        for (LinearLayout pill : new LinearLayout[] {colPill, rowPill}) {
            ((GradientDrawable) pill.getBackground()).setColor(rgb | 0x26000000);
            for (int i = 0; i < pill.getChildCount(); i++) {
                TextView t = (TextView) pill.getChildAt(i);
                t.setTextColor(c);
                if (t.isClickable()) {
                    GradientDrawable mask = new GradientDrawable();
                    mask.setShape(GradientDrawable.OVAL);
                    mask.setColor(0xff000000);
                    t.setBackground(new RippleDrawable(ColorStateList.valueOf(rgb | 0x40000000), null, mask));
                }
            }
        }
    }

    private LinearLayout pill(Context ctx, int orientation) {
        LinearLayout pill = new LinearLayout(ctx);
        pill.setOrientation(orientation);
        pill.setGravity(Gravity.CENTER);
        pill.setPadding(dp(2), dp(2), dp(2), dp(2));
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(20));
        pill.setBackground(bg);
        pill.setVisibility(View.GONE);
        return pill;
    }

    private TextView step(Context ctx, LinearLayout pill, String label, String description) {
        TextView t = new TextView(ctx);
        t.setText(label);
        t.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 22);
        t.setGravity(Gravity.CENTER);
        t.setContentDescription(description);
        t.setClickable(true);
        t.setOnClickListener(this);
        pill.addView(t, new LinearLayout.LayoutParams(dp(36), dp(36)));
        return t;
    }

    private TextView value(Context ctx, LinearLayout pill, boolean vertical) {
        TextView t = new TextView(ctx);
        t.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 18);
        t.setTypeface(android.graphics.Typeface.create("sec", android.graphics.Typeface.BOLD));
        t.setGravity(Gravity.CENTER);
        t.setMinWidth(dp(24));
        pill.addView(t, vertical ? new LinearLayout.LayoutParams(dp(36), dp(26))
                : new LinearLayout.LayoutParams(-2, dp(36)));
        return t;
    }

    private int dp(int v) {
        return Math.round(v * panel.getResources().getDisplayMetrics().density);
    }

    @Override
    public void onViewAttachedToWindow(View v) {
        v.getViewTreeObserver().addOnPreDrawListener(this);
    }

    @Override
    public void onViewDetachedFromWindow(View v) {
        v.getViewTreeObserver().removeOnPreDrawListener(this);
        pages = null;
    }
}
