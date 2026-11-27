package moe.foss.onigiri;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.Signature;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.security.spec.PKCS8EncodedKeySpec;
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
 * keys form real Google attestation chains with a matching private key, and only then replaces
 * the one the ROM seeded. A keybox put there by hand, or by another module, is left alone: only a
 * file whose bytes this module recorded can be replaced, and a writer that skips its lock and
 * publishes between the final check and the rename can lose that write.
 */
public final class KeyboxUpdate {
    static final Path STORE = Paths.get("/data/adb/tricky_store/keybox.xml");
    static final Path DIR = EssentialUpdate.DATA.resolve("keybox");
    static final Path RESTORECON = Paths.get("/system/bin/restorecon");
    static final Path SHIPPED = DIR.resolve("shipped");
    // Written before the store is replaced, so an interrupted install is still recognisable.
    static final Path NEXT = DIR.resolve("installing");
    static final String MIRROR = "https://evoker.qzz.io/key";
    // The one host this module is allowed to talk to; a redirect anywhere else fails closed.
    static final Collection<String> HOSTS = Collections.singletonList("evoker.qzz.io");
    // SHA-256 of the SubjectPublicKeyInfo of the roots Google issues attestation keys under:
    // Key Attestation CA1 (RKP) and the hardware attestation root. Anything else is not a key
    // Google will accept, including the AOSP software key upstream ships.
    static final List<String> ROOTS = new ArrayList<>(Arrays.asList(
            "3ee44512a1af2beb39c889490c60ea3f82e43f5d5a5532f5ab9419f676cd07ec",
            "feb2ea7551ee316ed4bb443c8293b884dbfdea40b603ee3e4f4a897e4580fbae"));
    // SHA-256 of the archive keybox that releases before the seed marker installed. That file came
    // from this ROM, so it is this module's to replace even though no marker names it.
    static final String ARCHIVE = "773abeca64bdb537bde8ca37ee6071674cc1409f940b70ec8119a563e2867164";
    static final long MAX_KEYBOX = 1024L * 1024;
    // A key with days left is not worth replacing a working one with.
    static final long MIN_LIFE = TimeUnit.DAYS.toMillis(2);
    // The daemon reads one <Key> at a time, wherever it sits, and ignores <Keybox> and
    // NumberOfKeyboxes. One <Keybox> may hold several, typically an EC and an RSA key.
    static final Pattern KEY = Pattern.compile("<Key\\b[^>]*>[\\s\\S]*?</Key>");
    static final Pattern PEM = Pattern.compile("-----BEGIN (?:EC |RSA )?PRIVATE KEY-----([\\s\\S]*?)-{5}END");

    /** One {@code <Key>}: its certificate chain and its private key. */
    static final class Entry {
        final List<X509Certificate> chain;
        final byte[] key;

        Entry(List<X509Certificate> chain, byte[] key) {
            this.chain = chain;
            this.key = key;
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
     * Every key a keybox holds, in document order. Each carries its own certificate chain, and one
     * keybox may group an EC key and an RSA key side by side, so they are never merged.
     */
    static List<Entry> entries(byte[] xml) throws Exception {
        String text = plain(new String(xml, StandardCharsets.UTF_8));
        // The daemon parses real XML, so a file that stops early is not guessed at either.
        if (!text.contains("<AndroidAttestation") || !text.trim().endsWith("</AndroidAttestation>"))
            throw new IOException("Not a keybox");
        List<Entry> entries = new ArrayList<>();
        Matcher key = KEY.matcher(text);
        while (key.find()) entries.add(entry(key.group()));
        if (entries.isEmpty()) throw new IOException("No keys in the keybox");
        return entries;
    }

    /**
     * The document with its comments and character data removed, so text a pattern would read as
     * markup cannot pass for it. Mirrors carry a banner comment, so this drops them instead of
     * refusing the file; a key shared inside one is simply not read, and fails as an empty entry.
     */
    static String plain(String text) throws IOException {
        if (text.contains("<!DOCTYPE")) throw new IOException("Keybox declares a DTD");
        String stripped = text.replaceAll("(?s)<!--.*?-->", "")
                .replaceAll("(?s)<!\\[CDATA\\[.*?\\]\\]>", "");
        if (stripped.contains("<!--") || stripped.contains("<![CDATA["))
            throw new IOException("Keybox carries an unclosed comment");
        return stripped;
    }

    static Entry entry(String block) throws Exception {
        List<X509Certificate> chain = certificates(block);
        if (chain.isEmpty()) throw new IOException("Key without a certificate");
        Matcher pem = PEM.matcher(block);
        // A key without its private key cannot attest, and must not ride along with one that can.
        if (!pem.find()) throw new IOException("Key without a private key");
        return new Entry(chain, Base64.getMimeDecoder().decode(pem.group(1)));
    }

    /**
     * The first certificate this keybox signs with, once every key in it checks out. One good key
     * is not enough: the file is published whole, so all of it has to be sound.
     */
    static X509Certificate verify(byte[] xml) throws Exception { return verify(xml, true); }

    /**
     * @param dates whether to hold the certificates to the clock. The image may carry a key that
     *     is already old, because a connected device replaces it at boot; a key published onto a
     *     device may not.
     */
    static X509Certificate verify(byte[] xml, boolean dates) throws Exception {
        X509Certificate first = null;
        for (Entry entry : entries(xml)) {
            X509Certificate leaf = valid(entry, dates);
            if (first == null) first = leaf;
        }
        return first;
    }

    static X509Certificate valid(Entry entry, boolean dates) throws Exception {
        List<X509Certificate> chain = entry.chain;
        if (chain.size() < 2) throw new IOException("Incomplete certificate chain");
        // Signatures first: it also keeps each chain's certificates separate, since one entry
        // never signs for another.
        for (int i = 0; i + 1 < chain.size(); i++) chain.get(i).verify(chain.get(i + 1).getPublicKey());
        if (!ROOTS.contains(spki(chain.get(chain.size() - 1))))
            throw new IOException("Chain does not end at a Google attestation root");
        if (dates) {
            for (X509Certificate certificate : chain) certificate.checkValidity();
            // The attestation leaf is itself a CA — it signs device certificates — so only its
            // chain, its remaining life and the key it claims are checked here.
            entry.leaf().checkValidity(new Date(System.currentTimeMillis() + MIN_LIFE));
        }
        match(entry.leaf(), entry.key);
        return entry.leaf();
    }

    static String spki(X509Certificate certificate) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(certificate.getPublicKey().getEncoded());
        StringBuilder hex = new StringBuilder();
        for (byte value : hash) hex.append(String.format("%02x", value));
        return hex.toString();
    }

    /**
     * Fails unless the private key can sign for the certificate beside it. Reading the public
     * values out of the key would accept a damaged private half; a signature is the only thing
     * that proves the key works, which is what the daemon needs from it.
     */
    static void match(X509Certificate leaf, byte[] key) throws Exception {
        PublicKey published = leaf.getPublicKey();
        String algorithm = published.getAlgorithm();
        String scheme = "RSA".equals(algorithm) ? "SHA256withRSA"
                : "EC".equals(algorithm) ? "SHA256withECDSA" : null;
        if (scheme == null) throw new IOException("Unsupported key type");
        PrivateKey privateKey;
        try {
            privateKey = KeyFactory.getInstance(algorithm)
                    .generatePrivate(new PKCS8EncodedKeySpec(pkcs8(key, published)));
        } catch (Exception e) { throw new IOException("Cannot read the private key", e); }
        byte[] challenge = new byte[32];
        new SecureRandom().nextBytes(challenge);
        Signature signer = Signature.getInstance(scheme);
        signer.initSign(privateKey);
        signer.update(challenge);
        byte[] proof = signer.sign();
        Signature check = Signature.getInstance(scheme);
        check.initVerify(published);
        check.update(challenge);
        if (!check.verify(proof)) throw new IOException("Private key does not match the certificate");
    }

    /**
     * PKCS#8 for a key that may be stored bare, which is how keyboxes usually carry them: RSA as
     * PKCS#1 and EC as SEC1. The algorithm identifier is copied from the certificate's own public
     * key, so a named curve needs no table here.
     */
    static byte[] pkcs8(byte[] der, PublicKey published) throws IOException {
        int[] top = tlv(der, 0);
        if (top[0] != 0x30) throw new IOException("Not a private key");
        int end = top[1] + top[2];
        int[] first = tlv(der, top[1]);
        if (first[0] == 0x02) {
            int after = first[1] + first[2];
            // PKCS#8 puts an algorithm identifier where the bare forms keep their second integer.
            if (after < end && tlv(der, after)[0] == 0x30) return Arrays.copyOfRange(der, 0, end);
        }
        byte[] spki = published.getEncoded();
        int[] outer = tlv(spki, 0);
        int[] algorithm = tlv(spki, outer[1]);
        if (algorithm[0] != 0x30) throw new IOException("Unsupported public key");
        return der(0x30, concat(new byte[]{0x02, 0x01, 0x00}, concat(
                Arrays.copyOfRange(spki, outer[1], algorithm[1] + algorithm[2]),
                der(0x04, der))));
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

    /** One DER element: the tag, its length and its content. */
    static byte[] der(int tag, byte[] content) {
        int size = content.length;
        ByteArrayOutputStream out = new ByteArrayOutputStream(size + 5);
        out.write(tag);
        if (size < 0x80) {
            out.write(size);
        } else {
            int bytes = 0;
            for (int left = size; left > 0; left >>>= 8) bytes++;
            out.write(0x80 | bytes);
            for (int i = bytes - 1; i >= 0; i--) out.write(size >>> (8 * i));
        }
        out.write(content, 0, size);
        return out.toByteArray();
    }

    static byte[] concat(byte[] first, byte[] second) {
        byte[] out = Arrays.copyOf(first, first.length + second.length);
        System.arraycopy(second, 0, out, first.length, second.length);
        return out;
    }

    /**
     * Whether the keybox in place can be replaced: nothing is installed, or this module installed
     * it. A keybox supplied by hand or by another module belongs to them and is left alone, so
     * this is the only gate that decides whether a boot may fetch and swap the file.
     */
    static boolean replaceable(String current, String tracked, String next, String builtin) {
        if (current == null) return true;
        return current.equals(tracked) || current.equals(next) || current.equals(builtin)
                || current.equals(ARCHIVE);
    }

    static byte[] decode(byte[] raw) throws IOException {
        try { return Base64.getMimeDecoder().decode(raw); }
        catch (IllegalArgumentException e) { throw new IOException("Keybox is not base64"); }
    }

    static void install(byte[] xml, String sha, String expected) throws Exception {
        install(STORE, DIR, xml, sha, expected);
    }

    /**
     * Publishes {@code xml} at {@code store}, recording it in {@code records}. A writer that
     * skips this lock and replaces the store between the final checksum and the rename can still
     * lose its file: POSIX has no compare-and-swap rename, and no other writer takes this lock.
     */
    static void install(Path store, Path records, byte[] xml, String sha, String expected)
            throws Exception {
        Path dir = store.getParent();
        Path shipped = records.resolve("shipped");
        Path next = records.resolve("installing");
        Files.createDirectories(dir);
        Files.createDirectories(records);
        // Named so a run killed mid-install leaves only something this module will clean up.
        Path staged = Files.createTempFile(dir, ".onigiri-keybox-", ".tmp");
        try {
            Files.setPosixFilePermissions(staged, PosixFilePermissions.fromString("rw-------"));
            try (OutputStream out = Files.newOutputStream(staged)) {
                out.write(xml);
                out.flush();
            }
            try (FileChannel file = FileChannel.open(staged, StandardOpenOption.WRITE)) { file.force(true); }
            // Label the keybox before it is published; the daemon reads it from another domain.
            // The host has no restorecon; a device always does.
            if (Files.isExecutable(RESTORECON)
                    && new ProcessBuilder(RESTORECON.toString(), staged.toString()).start().waitFor() != 0)
                throw new IOException("Labeling the keybox failed");
            // Written before the swap, so an install interrupted anywhere after this is still
            // recognisable as this module's.
            EssentialUpdate.atomicText(next, sha);
            if (expected == null) {
                // Nothing was there: create rather than replace, and let link(2) lose the race
                // against any writer that got there first.
                try { Files.createLink(store, staged); }
                catch (FileAlreadyExistsException e) {
                    Files.deleteIfExists(next);
                    throw new IOException("Keybox appeared during refresh");
                }
                // The daemon reloads on a write that closes, not on a create. Open it for writing
                // and close it untouched, so a first install is read without a restart.
                try (FileChannel notice = FileChannel.open(store, StandardOpenOption.WRITE)) { }
            } else {
                // Nothing else installed a keybox while this one was downloading.
                if (!Objects.equals(Files.isRegularFile(store) ? EssentialUpdate.sha256(store) : null, expected)) {
                    Files.deleteIfExists(next);
                    throw new IOException("Keybox changed during refresh");
                }
                Files.move(staged, store, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            }
            // Published, and on disk before a marker claims it is: a power cut between the two
            // must not leave the old key beside a digest of the new one.
            try (FileChannel directory = FileChannel.open(dir, StandardOpenOption.READ)) {
                directory.force(true);
            } catch (IOException e) { throw new IOException("Keybox is not durable", e); }
            EssentialUpdate.atomicText(shipped, sha);
            // The pending record only covers the moment before publication; left behind, an old
            // digest would keep vouching for a file this module no longer installed.
            Files.deleteIfExists(next);
        } finally { Files.deleteIfExists(staged); }
    }

    static void clearExpiry() {
        try { EssentialUpdate.prop("sys.onigiri.keybox.expires", ""); } catch (Exception ignored) { }
    }

    static String refresh() throws Exception {
        Files.createDirectories(DIR);
        Files.setPosixFilePermissions(DIR, PosixFilePermissions.fromString("rwx------"));
        try (FileChannel lockFile = FileChannel.open(DIR.resolve("update.lock"),
                StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock lock = lockFile.tryLock()) {
            if (lock == null) return "busy";
            // A run killed by its timeout leaves a partial download, or a staged key, behind.
            try (DirectoryStream<Path> stale = Files.newDirectoryStream(STORE.getParent(), ".onigiri-keybox-*.tmp")) {
                for (Path path : stale) Files.deleteIfExists(path);
            } catch (IOException ignored) { }
            try (DirectoryStream<Path> stale = Files.newDirectoryStream(DIR, "fetch-*")) {
                for (Path path : stale) EssentialUpdate.removeTree(path);
            } catch (IOException ignored) { }
            // Check ownership before touching the network: a keybox someone else installed is
            // final, and no boot should phone home for it.
            String current = Files.isRegularFile(STORE) ? EssentialUpdate.sha256(STORE) : null;
            Path builtin = EssentialUpdate.ROM.resolve("tee/keybox.xml");
            if (!replaceable(current, read(SHIPPED), read(NEXT),
                    Files.isReadable(builtin) ? EssentialUpdate.sha256(builtin) : null)) {
                clearExpiry();
                return "custom";
            }
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
            clearExpiry();
            result = "unavailable";
        }
        try { EssentialUpdate.prop("sys.onigiri.keybox.state", result); } catch (Exception ignored) { }
        // Android's network workers can keep app_process alive after main returns.
        System.exit(0);
    }
}
