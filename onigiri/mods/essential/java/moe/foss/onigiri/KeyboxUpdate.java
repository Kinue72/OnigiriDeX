package moe.foss.onigiri;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Collection;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Refreshes the shipped keybox without a ROM update.
 *
 * <p>Shared attestation keys are revoked every few days, so a keybox baked into an image is stale
 * long before the next release. This fetches the newest one the mirror publishes, checks that its
 * entries form real Google attestation chains with a matching private key, and only then replaces
 * the one the ROM seeded. A keybox put there by hand, or by another module, is never touched.
 */
public final class KeyboxUpdate {
    static final Path STORE = Paths.get("/data/adb/tricky_store/keybox.xml");
    static final Path DIR = EssentialUpdate.DATA.resolve("keybox");
    static final Path SHIPPED = DIR.resolve("shipped");
    // Written before the store is replaced, so an interrupted install is still recognisable.
    static final Path NEXT = DIR.resolve("installing");
    static final String MIRROR = "https://evoker.qzz.io/key";
    // The one host this module is allowed to talk to; a redirect anywhere else fails closed.
    static final Collection<String> HOSTS = Collections.singletonList("evoker.qzz.io");
    // SHA-256 of the SubjectPublicKeyInfo of the roots Google issues attestation keys under:
    // Key Attestation CA1 (RKP) and the hardware attestation root. Anything else is not a key
    // Google will accept, including the AOSP software key upstream ships.
    static final Collection<String> ROOTS = Arrays.asList(
            "3ee44512a1af2beb39c889490c60ea3f82e43f5d5a5532f5ab9419f676cd07ec",
            "feb2ea7551ee316ed4bb443c8293b884dbfdea40b603ee3e4f4a897e4580fbae");
    static final long MAX_KEYBOX = 1024L * 1024;
    // A key with days left is not worth replacing a working one with.
    static final long MIN_LIFE = TimeUnit.DAYS.toMillis(2);
    static final Pattern BOX = Pattern.compile("<Keybox\\b[\\s\\S]*?</Keybox>");
    static final Pattern PEM = Pattern.compile("-----BEGIN (?:EC |RSA )?PRIVATE KEY-----([\\s\\S]*?)-{5}END");

    /** One {@code <Keybox>} entry: its certificate chain and the public point its key carries. */
    static final class Entry {
        final List<X509Certificate> chain;
        final byte[] point;

        Entry(List<X509Certificate> chain, byte[] point) {
            this.chain = chain;
            this.point = point;
        }

        X509Certificate leaf() { return chain.get(0); }
    }

    /** A marker's value, or null when the file is missing or empty. */
    static String read(Path path) {
        try {
            String value = new String(Files.readAllBytes(path), StandardCharsets.US_ASCII).trim();
            return value.isEmpty() ? null : value;
        } catch (IOException e) { return null; }
    }

    static List<X509Certificate> certificates(String text) throws Exception {
        Matcher pem = Pattern.compile("-----BEGIN CERTIFICATE-----([\\s\\S]*?)-----END CERTIFICATE-----")
                .matcher(text);
        CertificateFactory factory = CertificateFactory.getInstance("X.509");
        List<X509Certificate> chain = new ArrayList<>();
        while (pem.find()) {
            chain.add((X509Certificate) factory.generateCertificate(
                    new ByteArrayInputStream(Base64.getMimeDecoder().decode(pem.group(1)))));
        }
        return chain;
    }

    /**
     * Every entry a keybox holds. A keybox may carry several, one per key type (typically an EC
     * chain and an RSA chain), and each has its own separate chain.
     */
    static List<Entry> entries(byte[] xml) throws Exception {
        String text = new String(xml, StandardCharsets.UTF_8);
        if (!text.contains("<AndroidAttestation")) throw new IOException("Not a keybox");
        List<Entry> entries = new ArrayList<>();
        Matcher box = BOX.matcher(text);
        while (box.find()) {
            List<X509Certificate> chain = certificates(box.group());
            if (chain.isEmpty()) continue;
            Matcher pem = PEM.matcher(box.group());
            byte[] point = null;
            if (pem.find()) {
                try { point = publicPoint(Base64.getMimeDecoder().decode(pem.group(1))); }
                catch (IOException ignored) { }
            }
            entries.add(new Entry(chain, point));
        }
        if (entries.isEmpty()) throw new IOException("No keybox entries");
        return entries;
    }

    /** The certificate this entry signs with, once its chain and private key check out. */
    static X509Certificate verify(byte[] xml) throws Exception {
        Exception failure = null;
        for (Entry entry : entries(xml)) {
            try { return valid(entry); }
            catch (Exception e) { failure = e; }
        }
        throw failure != null ? failure : new IOException("No usable keybox entry");
    }

    static X509Certificate valid(Entry entry) throws Exception {
        List<X509Certificate> chain = entry.chain;
        if (chain.size() < 2) throw new IOException("Incomplete certificate chain");
        // Signatures first: it also keeps each chain's certificates separate, since one entry
        // never signs for another.
        for (int i = 0; i + 1 < chain.size(); i++) chain.get(i).verify(chain.get(i + 1).getPublicKey());
        if (!ROOTS.contains(spki(chain.get(chain.size() - 1))))
            throw new IOException("Chain does not end at a Google attestation root");
        for (X509Certificate certificate : chain) certificate.checkValidity();
        // The attestation leaf is itself a CA — it signs device certificates — so only its chain,
        // its remaining life and the key it claims are checked here.
        entry.leaf().checkValidity(new Date(System.currentTimeMillis() + MIN_LIFE));
        match(entry.leaf(), entry.point);
        return entry.leaf();
    }

    static String spki(X509Certificate certificate) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(certificate.getPublicKey().getEncoded());
        StringBuilder hex = new StringBuilder();
        for (byte value : hash) hex.append(String.format("%02x", value));
        return hex.toString();
    }

    /**
     * The public point an EC private key carries, when it carries one. Used to tell whether the
     * key can actually sign for the certificate next to it.
     */
    static byte[] publicPoint(byte[] der) throws IOException {
        int[] top = tlv(der, 0);
        if (top[0] != 0x30) throw new IOException("Not a private key");
        int at = top[1];
        int end = top[1] + top[2];
        int[] first = tlv(der, at);
        if (first[0] == 0x02) {
            // PKCS#8 continues with an algorithm identifier, then the key in an OCTET STRING;
            // a bare SEC1 key continues with the private scalar instead.
            int after = first[1] + first[2];
            int[] second = after < end ? tlv(der, after) : null;
            if (second != null && second[0] == 0x30) {
                int wrapped = second[1] + second[2];
                int[] third = wrapped < end ? tlv(der, wrapped) : null;
                if (third != null && third[0] == 0x04) {
                    try { return publicPoint(Arrays.copyOfRange(der, third[1], third[1] + third[2])); }
                    catch (IOException ignored) { }
                }
                return null;
            }
        }
        while (at < end) {
            int[] field = tlv(der, at);
            if (field[0] == 0xa1) {
                int[] bits = tlv(der, field[1]);
                if (bits[0] != 0x03 || der[bits[1]] != 0) throw new IOException("Bad public key");
                return Arrays.copyOfRange(der, bits[1] + 1, bits[1] + bits[2]);
            }
            at = field[1] + field[2];
        }
        return null;
    }

    private static int[] tlv(byte[] der, int at) throws IOException {
        if (at + 2 > der.length) throw new IOException("Truncated key");
        int tag = der[at] & 0xff;
        int length = der[at + 1] & 0xff;
        int start = at + 2;
        if ((length & 0x80) != 0) {
            int count = length & 0x7f;
            if (count < 1 || count > 3) throw new IOException("Unsupported key length");
            length = 0;
            for (int i = 0; i < count; i++) length = (length << 8) | (der[start + i] & 0xff);
            start += count;
        }
        if (start + length > der.length) throw new IOException("Truncated key");
        return new int[]{tag, start, length};
    }

    /** Fails when the entry's private key is not the one its certificate was issued for. */
    static void match(X509Certificate leaf, byte[] point) throws IOException {
        if (point == null) return;
        byte[] encoded = leaf.getPublicKey().getEncoded();
        if (encoded.length < point.length || !Arrays.equals(
                Arrays.copyOfRange(encoded, encoded.length - point.length, encoded.length), point))
            throw new IOException("Private key does not match the certificate");
    }

    /**
     * Whether the keybox in place can be replaced: nothing is installed, or this module installed
     * it. A keybox supplied by hand or by another module belongs to them and is never touched.
     */
    static boolean replaceable(String current, String tracked, String next, String builtin) {
        if (current == null) return true;
        return current.equals(tracked) || current.equals(next) || current.equals(builtin);
    }

    static byte[] decode(byte[] raw) throws IOException {
        try { return Base64.getMimeDecoder().decode(raw); }
        catch (IllegalArgumentException e) { throw new IOException("Keybox is not base64"); }
    }

    static void install(byte[] xml, String sha, String expected) throws Exception {
        Path dir = STORE.getParent();
        Files.createDirectories(dir);
        Path staged = Files.createTempFile(dir, "keybox-", ".tmp");
        try {
            Files.setPosixFilePermissions(staged, PosixFilePermissions.fromString("rw-------"));
            try (OutputStream out = Files.newOutputStream(staged)) {
                out.write(xml);
                out.flush();
            }
            try (FileChannel file = FileChannel.open(staged, StandardOpenOption.WRITE)) { file.force(true); }
            // Label the keybox before it is published; the daemon reads it from another domain.
            if (new ProcessBuilder("/system/bin/restorecon", staged.toString()).start().waitFor() != 0)
                throw new IOException("Labeling the keybox failed");
            // Nothing else installed a keybox while this one was downloading.
            if (!Objects.equals(Files.isRegularFile(STORE) ? EssentialUpdate.sha256(STORE) : null, expected))
                throw new IOException("Keybox changed during refresh");
            EssentialUpdate.atomicText(NEXT, sha);
            Files.move(staged, STORE, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            EssentialUpdate.atomicText(SHIPPED, sha);
        } finally { Files.deleteIfExists(staged); }
    }

    static String refresh() throws Exception {
        Files.createDirectories(DIR);
        Files.setPosixFilePermissions(DIR, PosixFilePermissions.fromString("rwx------"));
        try (FileChannel lockFile = FileChannel.open(DIR.resolve("update.lock"),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock lock = lockFile.tryLock()) {
            if (lock == null) return "busy";
            // A run killed by its timeout leaves a partial download behind.
            try (DirectoryStream<Path> stale = Files.newDirectoryStream(DIR, "fetch-*")) {
                for (Path path : stale) EssentialUpdate.removeTree(path);
            } catch (IOException ignored) { }
            // Check ownership before touching the network: a keybox someone else installed is
            // final, and no boot should phone home for it.
            String current = Files.isRegularFile(STORE) ? EssentialUpdate.sha256(STORE) : null;
            Path builtin = EssentialUpdate.ROM.resolve("tee/keybox.xml");
            if (!replaceable(current, read(SHIPPED), read(NEXT),
                    Files.isReadable(builtin) ? EssentialUpdate.sha256(builtin) : null))
                return "custom";
            Path temp = Files.createTempDirectory(DIR, "fetch-");
            try {
                Path encoded = temp.resolve("key");
                EssentialUpdate.download(MIRROR, encoded, MAX_KEYBOX, HOSTS);
                byte[] xml = decode(Files.readAllBytes(encoded));
                X509Certificate leaf = verify(xml);
                Path next = temp.resolve("keybox.xml");
                Files.write(next, xml);
                String sha = EssentialUpdate.sha256(next);
                if (sha.equals(current)) {
                    EssentialUpdate.prop("sys.onigiri.keybox.expires", leaf.getNotAfter().toInstant().toString());
                    return "current";
                }
                install(xml, sha, current);
                EssentialUpdate.prop("sys.onigiri.keybox.expires", leaf.getNotAfter().toInstant().toString());
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
