package moe.foss.onigiri.update;

import android.content.Context;
import android.content.res.TypedArray;
import android.util.AttributeSet;
import android.widget.TextView;

import androidx.preference.Preference;
import androidx.preference.PreferenceViewHolder;

/**
 * A row that only shows text (the header and What's new). AndroidX greys the title of a row that
 * can't be tapped; this keeps its layout's own colors.
 */
public class TextPreference extends Preference {
    public TextPreference(Context context, AttributeSet attrs) {
        super(context, attrs);
    }

    @Override
    public void onBindViewHolder(PreferenceViewHolder holder) {
        super.onBindViewHolder(holder);
        recolor(holder, android.R.id.title, android.R.attr.textColorPrimary);
        // What's new reads as body text; the header's summary is a status line.
        recolor(holder, android.R.id.summary, "onigiri_update_notes".equals(getKey())
                ? android.R.attr.textColorPrimary : android.R.attr.textColorSecondary);
    }

    private void recolor(PreferenceViewHolder holder, int id, int attr) {
        TextView view = (TextView) holder.findViewById(id);
        TypedArray values = view.getContext().obtainStyledAttributes(new int[] {attr});
        try {
            view.setTextColor(values.getColorStateList(0));
        } finally {
            values.recycle();
        }
    }
}
