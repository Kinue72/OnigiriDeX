package androidx.preference;
public class Preference {
    public interface OnPreferenceChangeListener { boolean onPreferenceChange(Preference p, Object v); }
    public void setIcon(android.graphics.drawable.Drawable d) { }
    public void setSummary(CharSequence s) { }
}
