package moe.foss.onigiri;

import android.os.SystemProperties;

public final class HmaLoaderWaitTest {
    public static void main(String[] args) {
        SystemProperties.reset(300, 310, false);
        new HmaLoader().run();
        assert SystemProperties.attempted : "Slow boot missed HMA startup";
        assert SystemProperties.elapsed == 310;

        SystemProperties.reset(300, 600, false);
        new HmaLoader().run();
        assert !SystemProperties.attempted : "Loaded after readiness deadline";
        assert SystemProperties.elapsed == 540 : "Deadline must start after boot completion";

        SystemProperties.reset(300, 310, true);
        new HmaLoader().run();
        assert !SystemProperties.attempted;
        assert SystemProperties.elapsed == 0 : "Disabled HMA should stop waiting immediately";
        System.out.println("HMA slow boot, bounded readiness and disabled startup passed");
    }
}
