package androidx.preference;
public class Preference {
    public interface OnPreferenceClickListener { boolean onPreferenceClick(Preference p); }
    public interface OnPreferenceChangeListener { boolean onPreferenceChange(Preference p, Object v); }
    public Preference(android.content.Context c, android.util.AttributeSet a) { }
    public final android.content.Context getContext() { throw null; }
    public String getKey() { throw null; }
    public void onBindViewHolder(PreferenceViewHolder holder) { }
    public void setTitle(CharSequence t) { }
    public void setSummary(CharSequence s) { }
    public final void setVisible(boolean v) { }
    public void setEnabled(boolean v) { }
    public void setOnPreferenceClickListener(OnPreferenceClickListener l) { }
    public void setOnPreferenceChangeListener(OnPreferenceChangeListener l) { }
}
