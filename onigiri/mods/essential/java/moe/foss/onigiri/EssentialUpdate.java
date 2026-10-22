package moe.foss.onigiri;

import java.io.*;
import java.net.*;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.*;
import java.util.zip.*;

/** PIF-style compatible-release feed. Never executes a module's installation scripts. */
public final class EssentialUpdate {
    static final Path DATA = Paths.get("/data/system/onigiri-essential");
    static final Path ROM = Paths.get("/system/framework/onigiri-essential");
    static final String FEED = "https://raw.githubusercontent.com/Kinue72/OnigiriDeX/main/prebuilts/rootmods/updates.properties";
    static final long MAX_ZIP = 64L * 1024 * 1024;

    static String prop(String key) throws Exception {
        return (String) Class.forName("android.os.SystemProperties").getMethod("get", String.class).invoke(null, key);
    }

    static void prop(String key, String value) throws Exception {
        Class.forName("android.os.SystemProperties").getMethod("set", String.class, String.class).invoke(null, key, value);
    }

    static String repo(String id) {
        switch (id) {
            case "hma": return "frknkrc44/HMA-OSS";
            case "tee": return "JingMatrix/TEESimulator";
            case "brene": return "rrr333nnn333/BRENE";
            default: throw new IllegalArgumentException("Unknown component");
        }
    }

    static Properties readProperties(Path path) throws IOException {
        Properties p = new Properties();
        try (InputStream in = Files.newInputStream(path)) { p.load(in); }
        return p;
    }

    static String required(Properties p, String key) throws IOException {
        String value = p.getProperty(key);
        if (value == null || value.isEmpty()) throw new IOException("Missing " + key);
        return value;
    }

    static long copy(InputStream in, OutputStream out, long limit) throws IOException {
        byte[] buf = new byte[32768];
        long total = 0;
        for (int n; (n = in.read(buf)) != -1;) {
            total += n;
            if (total > limit) throw new IOException("Payload too large");
            out.write(buf, 0, n);
        }
        return total;
    }

    static void download(String address, Path dest, long limit) throws IOException {
        URL url = new URL(address);
        for (int hop = 0; hop < 5; hop++) {
            String host = url.getHost();
            if (!url.getProtocol().equals("https") || url.getUserInfo() != null ||
                    (url.getPort() != -1 && url.getPort() != 443) ||
                    !Arrays.asList("github.com", "raw.githubusercontent.com", "release-assets.githubusercontent.com",
                            "objects.githubusercontent.com").contains(host)) throw new IOException("Unexpected download host");
            HttpURLConnection c = (HttpURLConnection) url.openConnection();
            c.setConnectTimeout(15000);
            c.setReadTimeout(20000);
            c.setInstanceFollowRedirects(false);
            c.setRequestProperty("User-Agent", "Onigiri-essential/1");
            try {
                int status = c.getResponseCode();
                if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
                    String location = c.getHeaderField("Location");
                    if (location == null) throw new IOException("Redirect without location");
                    url = new URL(url, location);
                    continue;
                }
                if (status != 200) throw new IOException("HTTP " + status);
                if (c.getContentLengthLong() > limit) throw new IOException("Payload too large");
                try (InputStream in = c.getInputStream(); OutputStream out = Files.newOutputStream(dest)) {
                    copy(in, out, limit);
                }
                return;
            } finally { c.disconnect(); }
        }
        throw new IOException("Too many redirects");
    }

    static String sha256(Path path) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = Files.newInputStream(path)) {
            byte[] buf = new byte[32768];
            for (int n; (n = in.read(buf)) != -1;) digest.update(buf, 0, n);
        }
        StringBuilder result = new StringBuilder();
        for (byte b : digest.digest()) result.append(String.format(Locale.ROOT, "%02x", b & 255));
        return result.toString();
    }

    static byte[] member(ZipFile zip, String name) throws IOException {
        ZipEntry e = zip.getEntry(name);
        if (e == null || e.isDirectory() || e.getSize() < 1 || e.getSize() > MAX_ZIP) throw new IOException("Invalid member " + name);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (InputStream in = zip.getInputStream(e)) { copy(in, out, MAX_ZIP); }
        return out.toByteArray();
    }

    static void write(Path path, byte[] bytes, boolean executable) throws IOException {
        try (FileOutputStream out = new FileOutputStream(path.toFile())) {
            out.write(bytes);
            out.getFD().sync();
        }
        Files.setPosixFilePermissions(path, PosixFilePermissions.fromString(executable ? "r-xr-xr-x" : "r--r--r--"));
    }

    static void atomicText(Path path, String value) throws IOException {
        Path tmp = path.resolveSibling(path.getFileName() + ".new");
        Files.deleteIfExists(tmp);
        write(tmp, (value + "\n").getBytes(StandardCharsets.UTF_8), false);
        Files.move(tmp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        try (FileChannel directory = FileChannel.open(path.getParent(), StandardOpenOption.READ)) { directory.force(true); }
    }

    static void elf(byte[] data) throws IOException {
        if (data.length < 64 || data[0] != 127 || data[1] != 'E' || data[2] != 'L' || data[3] != 'F' ||
                data[4] != 2 || data[5] != 1 || (data[18] & 255) != 183 || data[19] != 0) throw new IOException("Expected arm64 ELF");
    }

    static void extract(String id, Path archive, Path output, Properties feed) throws Exception {
        String prefix = id + ".";
        if (!sha256(archive).equals(required(feed, prefix + "sha256")) ||
                Files.size(archive) != Long.parseLong(required(feed, prefix + "bytes"))) throw new IOException("Checksum or size mismatch");
        Files.createDirectories(output);
        try (ZipFile zip = new ZipFile(archive.toFile())) {
            Set<String> seen = new HashSet<>();
            for (Enumeration<? extends ZipEntry> it = zip.entries(); it.hasMoreElements();) {
                if (!seen.add(it.nextElement().getName())) throw new IOException("Duplicate ZIP member");
            }
            Properties module = new Properties();
            module.load(new ByteArrayInputStream(member(zip, "module.prop")));
            if (!required(feed, prefix + "module").equals(module.getProperty("id")) ||
                    !required(feed, prefix + "code").equals(module.getProperty("versionCode"))) throw new IOException("Wrong upstream module/version");
            if (id.equals("hma")) {
                byte[] dex = member(zip, "classes.dex");
                if (!new String(dex, StandardCharsets.ISO_8859_1).contains("Lorg/frknkrc44/hma_oss/zygote/ZygoteEntry;")) throw new IOException("Unsupported HMA entry point");
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                try (ZipOutputStream jar = new ZipOutputStream(bytes)) {
                    ZipEntry entry = new ZipEntry("classes.dex");
                    entry.setTime(1199145600000L);
                    jar.putNextEntry(entry);
                    jar.write(dex);
                }
                write(output.resolve("hma.jar"), bytes.toByteArray(), false);
                write(output.resolve("manager.apk"), member(zip, "manager.apk"), false);
            } else if (id.equals("tee")) {
                byte[] dex = member(zip, "classes.dex");
                if (!new String(dex, StandardCharsets.ISO_8859_1).contains("Lorg/matrix/TEESimulator/App;")) throw new IOException("Unsupported TEE entry point");
                write(output.resolve("classes.dex"), dex, false);
                for (String name : Arrays.asList("libinject.so", "libTEESimulator.so")) {
                    byte[] bytes = member(zip, "lib/arm64-v8a/" + name);
                    elf(bytes);
                    write(output.resolve(name.equals("libinject.so") ? "inject" : name), bytes, true);
                }
                for (String name : Arrays.asList("keybox.xml", "target.txt")) write(output.resolve(name), member(zip, name), false);
            } else {
                byte[] bytes = member(zip, "tools/susfs");
                elf(bytes);
                write(output.resolve("susfs"), bytes, true);
                String script = new String(member(zip, "post-fs-data.sh"), StandardCharsets.UTF_8);
                Matcher names = Pattern.compile("(?m)^CUSTOM_ROM_NAMES=\"([a-z|]+)\"\\r?$").matcher(script);
                if (!names.find()) throw new IOException("Unsupported BRENE path list");
                write(output.resolve("rom-names"), (names.group(1).replace('|', '\n') + "\n").getBytes(StandardCharsets.US_ASCII), false);
            }
        }
        Properties version = new Properties();
        for (String key : Arrays.asList("version", "code", "adapter", "sha256")) version.setProperty(key, required(feed, prefix + key));
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        version.store(bytes, null);
        write(output.resolve("version.properties"), bytes.toByteArray(), false);
    }

    static Path payload(Path root, Path builtin, String id) throws IOException {
        Path active = root.resolve(id).resolve("active");
        if (!Files.exists(active)) return builtin.resolve(id);
        String hash = new String(Files.readAllBytes(active), StandardCharsets.US_ASCII).trim();
        if (!hash.matches("[a-f0-9]{64}")) throw new IOException("Invalid active reference");
        Path path = root.resolve(id).resolve("releases").resolve(hash);
        if (!Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) throw new IOException("Missing active release");
        Properties current = readProperties(path.resolve("version.properties"));
        Properties shipped = readProperties(builtin.resolve(id).resolve("version.properties"));
        if (!required(current, "adapter").equals(required(shipped, "adapter")) ||
                Long.parseLong(required(current, "code")) <= Long.parseLong(required(shipped, "code"))) return builtin.resolve(id);
        return path;
    }

    static void removeTree(Path path) throws IOException {
        if (Files.isDirectory(path, LinkOption.NOFOLLOW_LINKS)) {
            try (DirectoryStream<Path> files = Files.newDirectoryStream(path)) {
                for (Path child : files) removeTree(child);
            }
        }
        Files.deleteIfExists(path);
    }

    static void verifyManager(Path candidate) throws Exception {
        Class<?> looper = Class.forName("android.os.Looper");
        if (looper.getMethod("getMainLooper").invoke(null) == null) looper.getMethod("prepareMainLooper").invoke(null);
        Class<?> activityThread = Class.forName("android.app.ActivityThread");
        Object thread = activityThread.getMethod("systemMain").invoke(null);
        Object context = activityThread.getMethod("getSystemContext").invoke(thread);
        Object pm = Class.forName("android.content.Context").getMethod("getPackageManager").invoke(context);
        java.lang.reflect.Method archive = Class.forName("android.content.pm.PackageManager")
                .getMethod("getPackageArchiveInfo", String.class, int.class);
        Object next = archive.invoke(pm, candidate.toString(), 0x08000000);
        Object builtin = archive.invoke(pm, ROM.resolve("hma/manager.apk").toString(), 0x08000000);
        if (next == null || builtin == null) throw new IOException("Cannot verify HMA manager");
        Class<?> info = Class.forName("android.content.pm.PackageInfo");
        if (!"org.frknkrc44.hma_oss".equals(info.getField("packageName").get(next))) throw new IOException("Wrong HMA manager package");
        Object nextSign = info.getField("signingInfo").get(next);
        Object oldSign = info.getField("signingInfo").get(builtin);
        java.lang.reflect.Method signers = Class.forName("android.content.pm.SigningInfo").getMethod("getApkContentsSigners");
        Object[] nextCerts = (Object[]) signers.invoke(nextSign);
        Object[] oldCerts = (Object[]) signers.invoke(oldSign);
        if (nextCerts.length != 1 || oldCerts.length != 1 || !nextCerts[0].equals(oldCerts[0])) {
            throw new IOException("HMA signing identity changed; ROM update required");
        }
    }

    static String update(String id) throws Exception {
        repo(id);
        Path dir = DATA.resolve(id);
        Files.createDirectories(dir);
        try (FileChannel lockFile = FileChannel.open(dir.resolve("update.lock"), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock lock = lockFile.tryLock()) {
            if (lock == null) throw new IOException("Update already running");
            if (Files.exists(dir.resolve("trial"))) throw new IOException("Waiting for running version to be verified");
            if (Files.exists(dir.resolve("pending"))) {
                String hash = new String(Files.readAllBytes(dir.resolve("pending")), StandardCharsets.US_ASCII).trim();
                if (!hash.matches("[a-f0-9]{64}")) throw new IOException("Invalid pending reference");
                Properties pending = readProperties(dir.resolve("releases").resolve(hash).resolve("version.properties"));
                prop("sys.onigiri." + id + ".pending_version", required(pending, "version"));
                return "updated";
            }
            Path temp = Files.createTempDirectory(dir, "download-");
            Files.setPosixFilePermissions(temp, PosixFilePermissions.fromString("rwx------"));
            try {
                Path feedPath = temp.resolve("feed");
                download(FEED, feedPath, 65536);
                Properties feed = readProperties(feedPath);
                String p = id + ".";
                if (!"1".equals(required(feed, p + "adapter"))) return "incompatible";
                long code = Long.parseLong(required(feed, p + "code"));
                Properties current = readProperties(payload(DATA, ROM, id).resolve("version.properties"));
                if (code <= Long.parseLong(required(current, "code"))) {
                    return "true".equals(feed.getProperty(p + "newer_requires_rom")) ? "incompatible" : "up_to_date";
                }
                String address = required(feed, p + "url");
                if (!address.startsWith("https://github.com/" + repo(id) + "/releases/download/")) throw new IOException("Unexpected upstream source");
                String hash = required(feed, p + "sha256");
                if (!hash.matches("[a-f0-9]{64}")) throw new IOException("Invalid checksum");
                long size = Long.parseLong(required(feed, p + "bytes"));
                if (size < 1 || size > MAX_ZIP) throw new IOException("Invalid download size");
                String version = required(feed, p + "version");
                if (!version.matches("[A-Za-z0-9._-]{1,48}")) throw new IOException("Invalid version");
                Path archive = temp.resolve("release.zip");
                download(address, archive, size);
                Path extracted = temp.resolve("payload");
                extract(id, archive, extracted, feed);
                if (id.equals("hma")) verifyManager(extracted.resolve("manager.apk"));
                Files.setPosixFilePermissions(extracted, PosixFilePermissions.fromString("rwxr-xr-x"));
                Path releases = dir.resolve("releases");
                Files.createDirectories(releases);
                Path dest = releases.resolve(hash);
                if (!Files.exists(dest)) Files.move(extracted, dest, StandardCopyOption.ATOMIC_MOVE);
                if (new ProcessBuilder("/system/bin/restorecon", "-RF", dest.toString()).start().waitFor() != 0) throw new IOException("Labeling update failed");
                atomicText(dir.resolve("pending"), hash);
                prop("sys.onigiri." + id + ".pending_version", version);
                return "updated";
            } finally { removeTree(temp); }
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("Expected component");
        String id = args[0];
        repo(id);
        String result = "error";
        prop("sys.onigiri." + id + ".update", "checking");
        try { result = update(id); }
        catch (Exception e) { System.err.println("Onigiri update: " + e); }
        finally { prop("sys.onigiri." + id + ".update", result); }
        // Android's network workers can keep app_process alive after main returns.
        System.exit(0);
    }
}
