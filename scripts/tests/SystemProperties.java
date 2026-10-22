package android.os;

/** Host-only property service and virtual clock for the HMA readiness loop. */
public final class SystemProperties {
    public static int elapsed, bootAt, readyAt;
    public static boolean disabled, attempted;

    public static void reset(int boot, int ready, boolean off) {
        elapsed = 0;
        bootAt = boot;
        readyAt = ready;
        disabled = off;
        attempted = false;
    }

    public static String get(String key) {
        switch (key) {
            case "sys.onigiri.hma.attempted": return Boolean.toString(attempted);
            case "sys.onigiri.essential.prepared": return "true";
            case "sys.boot_completed": return elapsed >= bootAt ? "1" : "0";
            case "sys.onigiri.hma.state": return disabled ? "off" : elapsed >= readyAt ? "ready" : "loading";
            default: return "";
        }
    }

    public static void set(String key, String value) {
        if (key.equals("sys.onigiri.hma.attempted")) attempted = value.equals("true");
        if (key.equals("sys.onigiri.hma.state") && value.equals("loading") && attempted) {
            throw new IllegalStateException("Host test stops before accessing Android hooks");
        }
    }

    public static void tick() { elapsed++; }
}
