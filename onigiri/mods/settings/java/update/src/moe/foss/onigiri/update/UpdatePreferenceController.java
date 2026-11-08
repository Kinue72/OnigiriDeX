package moe.foss.onigiri.update;

import android.content.Context;
import android.content.Intent;
import android.os.SemSystemProperties;

import androidx.preference.Preference;

import com.android.settings.core.BasePreferenceController;
import com.samsung.android.settings.cube.ControlResult;
import com.samsung.android.settings.cube.ControlValue;
import com.samsung.android.settings.cube.Controllable;

/** The Software update row in Onigiri Software, which opens UpdateSettingsFragment. */
public class UpdatePreferenceController extends BasePreferenceController {
    private final Context mContext;

    public UpdatePreferenceController(Context context, String key) {
        super(context, key);
        mContext = context;
    }

    @Override
    public int getAvailabilityStatus() {
        return 0;
    }

    @Override
    public void updateState(Preference preference) {
        Updates.Offer offer = Updates.cached(mContext);
        String summary;
        if (offer != null && !offer.upToDate && offer.file != null) {
            summary = Updates.string(mContext, "onigiri_update_row_available", offer.tag, Updates.size(mContext, offer.size));
        } else if (offer != null && offer.installedTag != null) {
            summary = "Onigiri " + offer.installedTag;
        } else {
            summary = SemSystemProperties.get("ro.onigiri.build", "");
        }
        preference.setSummary(summary);
    }

    // Samsung's BasePreferenceController leaves these Controllable and Sliceable methods abstract,
    // and the Settings action and slice indexers call them on every controller.
    @Override
    public Intent getLaunchIntent() {
        return null;
    }

    @Override
    public String getStatusText() {
        return null;
    }

    @Override
    public ControlValue getValue() {
        return null;
    }

    @Override
    public boolean isControllable() {
        return false;
    }

    @Override
    public Controllable.ControllableType needUserInteraction(Object value) {
        return Controllable.ControllableType.NO_INTERACTION;
    }

    @Override
    public boolean runDefaultAction() {
        return false;
    }

    @Override
    public ControlResult setValue(ControlValue value) {
        return null;
    }

    @Override
    public int getSliceHighlightMenuRes() {
        return 0;
    }
}
