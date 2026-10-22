package moe.foss.onigiri;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.regex.Pattern;

/** Loaded by services.jar; the upstream dex and signed manager remain unchanged. */
public final class HmaLoader implements Runnable {
    private static final String STATE = "sys.onigiri.hma.state";

    public static void start() {
        Thread thread = new Thread(new HmaLoader(), "OnigiriHMA");
        thread.setDaemon(true);
        thread.start();
    }

    @Override public void run() {
        try {
            // The latch survives a system_server restart, but not a full reboot.
            if ("true".equals(EssentialUpdate.prop("sys.onigiri.hma.attempted"))) {
                EssentialUpdate.prop(STATE, "unavailable");
                return;
            }
            boolean ready = false;
            int waited = 0;
            while (waited < 240) {
                if ("ready".equals(EssentialUpdate.prop(STATE))) { ready = true; break; }
                if ("true".equals(EssentialUpdate.prop("sys.onigiri.essential.prepared")) &&
                        !"loading".equals(EssentialUpdate.prop(STATE))) return;
                // Manager reconciliation starts at boot completion, even after a slow first boot.
                if ("1".equals(EssentialUpdate.prop("sys.boot_completed"))) waited++;
                Thread.sleep(1000);
            }
            if (!ready) return;
            EssentialUpdate.prop("sys.onigiri.hma.attempted", "true");
            EssentialUpdate.prop(STATE, "loading");
            Path data = null;
            try (DirectoryStream<Path> dirs = Files.newDirectoryStream(Paths.get("/data/misc"), "hide_my_applist_*")) {
                for (Path path : dirs) {
                    if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) continue;
                    if (data != null) throw new IllegalStateException("Multiple HMA data directories");
                    data = path;
                }
            }
            if (data == null) throw new IllegalStateException("HMA configuration not prepared");
            String config = new String(Files.readAllBytes(data.resolve("config.json")), StandardCharsets.UTF_8);
            if (!Pattern.compile("\"configVersion\"\\s*:\\s*93\\s*[,}]").matcher(config).find()) {
                throw new IllegalStateException("HMA configuration needs migration");
            }
            // This file is disposable runtime status. Config, rules and caches stay intact.
            Path status = data.resolve("status.json");
            Files.deleteIfExists(status);
            Path jar = EssentialUpdate.payload(EssentialUpdate.DATA, EssentialUpdate.ROM, "hma").resolve("hma.jar");
            ClassLoader loader = (ClassLoader) Class.forName("dalvik.system.PathClassLoader")
                    .getConstructor(String.class, ClassLoader.class)
                    .newInstance(jar.toString(), HmaLoader.class.getClassLoader());
            Class.forName("org.frknkrc44.hma_oss.zygote.ZygoteEntry", true, loader).getMethod("main").invoke(null);
            Pattern active = Pattern.compile("\"workMode\"\\s*:\\s*1\\s*[,}]");
            for (int i = 0; i < 90; i++) {
                if (Files.isRegularFile(status) && active.matcher(new String(Files.readAllBytes(status), StandardCharsets.UTF_8)).find()) {
                    EssentialUpdate.prop(STATE, "active");
                    return;
                }
                Thread.sleep(1000);
            }
            throw new IllegalStateException("HMA did not report active hooks");
        } catch (Throwable e) {
            System.err.println("OnigiriHMA: " + e);
            try { EssentialUpdate.prop(STATE, "unavailable"); } catch (Exception ignored) { }
        }
    }
}
