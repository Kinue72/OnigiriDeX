package android.os;

import java.util.HashMap;
import java.util.Map;

/** Host-only property store for OnigiriZonesTest. */
public final class SystemProperties {
    public static final Map<String, String> VALUES = new HashMap<>();

    public static String get(String key, String def) {
        return VALUES.getOrDefault(key, def);
    }
}
