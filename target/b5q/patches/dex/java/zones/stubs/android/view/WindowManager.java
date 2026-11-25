package android.view;

/** Shadows the SDK class for the hidden LayoutParams.privateFlags. Constants are the SDK's. */
public interface WindowManager extends ViewManager {
    void removeViewImmediate(View view);

    class InvalidDisplayException extends RuntimeException {
    }

    class LayoutParams extends ViewGroup.LayoutParams {
        public static final int FLAG_NOT_FOCUSABLE = 0x8;
        public static final int FLAG_NOT_TOUCHABLE = 0x10;
        public static final int FLAG_LAYOUT_IN_SCREEN = 0x100;
        public static final int FLAG_LAYOUT_NO_LIMITS = 0x200;
        public int gravity;
        public int privateFlags;
        public LayoutParams(int w, int h, int type, int flags, int format) { super(w, h); }
        public final void setTitle(CharSequence title) {}
        public void setFitInsetsTypes(int types) {}
    }
}
