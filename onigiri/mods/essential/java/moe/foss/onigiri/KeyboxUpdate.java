package moe.foss.onigiri;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collection;
import java.util.Date;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Refreshes the shipped keybox without a ROM update.
 *
 * <p>Shared attestation keys are revoked every few days, so a keybox baked into an image is
 * stale long before the next release. This fetches the newest one the mirror publishes, checks
 * that its certificate chain is intact and that its leaf still has life left, and only then
 * replaces the one the ROM seeded. A working keybox put there by hand, or by another module, is
 * never touched: the file has to match the checksum recorded when this module installed it, or be
 * the keybox in the payload, or be unusable.
 */
public final class KeyboxUpdate {
    static final Path STORE = Paths.get("/data/adb/tricky_store/keybox.xml");
    static final Path DIR = EssentialUpdate.DATA.resolve("keybox");
    static final Path SHIPPED = DIR.resolve("shipped");
    static final String MIRROR = "https://evoker.qzz.io/key";
    static final Collection<String> HOSTS = Arrays.asList("evoker.qzz.io", "github.com",
            "raw.githubusercontent.com", "release-assets.githubusercontent.com",
            "objects.githubusercontent.com");
    static final long MAX_KEYBOX = 1024L * 1024;
    // A key with days left is not worth replacing a working one with.
    static final long MIN_LIFE = TimeUnit.DAYS.toMillis(2);

    static String read(Path path) {
        try { return new String(Files.readAllBytes(path), StandardCharsets.US_ASCII).trim(); }
        catch (IOException e) { return null; }
    }

    /** The PEM certificates a keybox embeds, in order. */
    static List<X509Certificate> chain(byte[] xml) throws Exception {
        String text = new String(xml, StandardCharsets.UTF_8);
        if (!text.contains("<AndroidAttestation") || !text.contains("<Keybox"))
            throw new IOException("Not a keybox");
        Matcher pem = Pattern.compile("-----BEGIN CERTIFICATE-----([\\s\\S]*?)-----END CERTIFICATE-----").matcher(text);
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        List<X509Certificate> chain = new ArrayList<>();
        while (pem.find()) {
            chain.add((X509Certificate) factory.generateCertificate(
                    new ByteArrayInputStream(Base64.getMimeDecoder().decode(pem.group(1)))));
        }
        return chain;
    }

    /** The leaf certificate, after checking the chain and how much life it has left. */
    static X509Certificate verify(byte[] xml) throws Exception {
        List<X509Certificate> chain = chain(xml);
        if (chain.size() < 2) throw new IOException("Incomplete certificate chain");
        for (int i = 0; i + 1 < chain.size(); i++) chain.get(i).verify(chain.get(i + 1).getPublicKey());
        // The attestation leaf is itself a CA — it signs device certificates — so only its chain
        // and its remaining life are checked here.
        X509Certificate leaf = chain.get(0);
        leaf.checkValidity(new Date(System.currentTimeMillis() + MIN_LIFE));
        chain.get(chain.size() - 1).checkValidity();
        return leaf;
    }

    /** Whether the keybox in place is unusable: unreadable, not a keybox, or expired. */
    static boolean dead(byte[] xml) {
        try {
            for (X509Certificate certificate : chain(xml)) certificate.checkValidity();
            return false;
        } catch (Exception e) { return true; }
    }

    static void install(byte[] xml, String sha) throws Exception {
        Files.createDirectories(STORE.getParent());
        Path staged = STORE.resolveSibling("keybox.xml.new");
        Files.deleteIfExists(staged);
        try (OutputStream out = Files.newOutputStream(staged)) {
            out.write(xml);
            out.flush();
        }
        try (FileChannel file = FileChannel.open(staged, StandardOpenOption.WRITE)) { file.force(true); }
        Files.setPosixFilePermissions(staged, PosixFilePermissions.fromString("rw-------"));
        Files.move(staged, STORE, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        EssentialUpdate.atomicText(SHIPPED, sha);
        new ProcessBuilder("/system/bin/restorecon", STORE.toString()).start().waitFor();
    }

    /**
     * Whether the keybox in place can be replaced: nothing is installed, this module installed it,
     * or it is unusable. A working keybox supplied by hand or by another module belongs to them
     * and is never touched; a dead one cannot be serving anyone, so replacing it loses nothing —
     * that is what rescues an install whose key this module seeded before the marker existed.
     */
    static boolean replaceable(String tracked, String current, String builtin, boolean dead) {
        if (current == null) return true;
        if (dead) return true;
        if (tracked != null) return tracked.equals(current);
        return builtin != null && builtin.equals(current);
    }

    /** The mirror serves base64; an operator-pinned URL may serve the XML itself. */
    static byte[] decode(byte[] raw) throws IOException {
        int start = 0;
        while (start < raw.length && Character.isWhitespace(raw[start])) start++;
        if (start < raw.length && raw[start] == '<') return raw;
        try { return Base64.getMimeDecoder().decode(raw); }
        catch (IllegalArgumentException e) { throw new IOException("Keybox is neither XML nor base64"); }
    }

    static String refresh() throws Exception {
        Files.createDirectories(DIR);
        Files.setPosixFilePermissions(DIR, PosixFilePermissions.fromString("rwx------"));
        try (FileChannel lockFile = FileChannel.open(DIR.resolve("update.lock"),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock lock = lockFile.tryLock()) {
            if (lock == null) return "busy";
            // Check ownership before touching the network: a keybox someone else installed is
            // final, and no boot should phone home for it.
            byte[] inPlace = Files.isRegularFile(STORE) ? Files.readAllBytes(STORE) : null;
            String current = inPlace == null ? null : EssentialUpdate.sha256(STORE);
            Path builtin = EssentialUpdate.ROM.resolve("tee/keybox.xml");
            String shipped = read(SHIPPED);
            if (!replaceable(shipped, current, Files.isReadable(builtin) ? EssentialUpdate.sha256(builtin) : null,
                    inPlace != null && dead(inPlace)))
                return "custom";
            String address = EssentialUpdate.prop("persist.sys.onigiri.keybox.url");
            if (address == null || address.isEmpty()) address = MIRROR;
            Path temp = Files.createTempDirectory(DIR, "fetch-");
            try {
                Path encoded = temp.resolve("key");
                EssentialUpdate.download(address, encoded, MAX_KEYBOX, HOSTS);
                byte[] xml = decode(Files.readAllBytes(encoded));
                X509Certificate leaf = verify(xml);
                Path next = temp.resolve("keybox.xml");
                Files.write(next, xml);
                String sha = EssentialUpdate.sha256(next);
                EssentialUpdate.prop("sys.onigiri.keybox.expires", leaf.getNotAfter().toInstant().toString());
                if (sha.equals(current)) return "current";
                install(xml, sha);
                return "updated";
            } finally { EssentialUpdate.removeTree(temp); }
        }
    }

    public static void main(String[] args) {
        String result;
        try { result = refresh(); }
        catch (Exception e) {
            System.err.println("Onigiri keybox: " + e);
            result = "unavailable";
        }
        try { EssentialUpdate.prop("sys.onigiri.keybox.state", result); } catch (Exception ignored) { }
        // Android's network workers can keep app_process alive after main returns.
        System.exit(0);
    }
}
