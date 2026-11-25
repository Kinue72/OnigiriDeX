package android.graphics;

/** Host-only stand-in with the parts of android.graphics.Rect that OnigiriZones uses. */
public final class Rect {
    public int left, top, right, bottom;

    public Rect() {
    }

    public Rect(int left, int top, int right, int bottom) {
        set(left, top, right, bottom);
    }

    public Rect(Rect other) {
        set(other);
    }

    public void set(int left, int top, int right, int bottom) {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }

    public void set(Rect other) {
        set(other.left, other.top, other.right, other.bottom);
    }

    public int width() {
        return right - left;
    }

    public int height() {
        return bottom - top;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof Rect && toString().equals(other.toString());
    }

    @Override
    public int hashCode() {
        return toString().hashCode();
    }

    @Override
    public String toString() {
        return left + "," + top + "," + right + "," + bottom;
    }
}
