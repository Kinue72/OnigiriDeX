package moe.foss.onigiri;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.zip.ZipFile;

/**
 * Host tests for the keybox refresh policy. The network path needs a device.
 *
 * <p>The multi-entry cases use the keybox inside the pinned TEESimulator archive: an EC chain and
 * an RSA chain, each with its own certificates and private key, which is the shape the old
 * single-chain parser could not read.
 */
public final class KeyboxUpdateTest {
    public static void main(String[] args) throws Exception {
        // Nothing in place: ours to install.
        assert KeyboxUpdate.replaceable(null, null, null, null);
        // The file is the one this module recorded, or the one it is installing right now.
        assert KeyboxUpdate.replaceable("aaa", "aaa", null, null);
        assert KeyboxUpdate.replaceable("aaa", "old", "aaa", null);
        // The payload's own keybox, seeded before this module kept a marker.
        assert KeyboxUpdate.replaceable("aaa", null, null, "aaa");
        // A file it never installed is someone else's, whatever state it is in.
        assert !KeyboxUpdate.replaceable("bbb", null, null, "aaa");
        assert !KeyboxUpdate.replaceable("bbb", "aaa", "ccc", "ddd");
        // The mirror serves base64, with line breaks the decoder must ignore.
        byte[] xml = "<AndroidAttestation/>".getBytes();
        assert java.util.Arrays.equals(KeyboxUpdate.decode(
                java.util.Base64.getMimeEncoder(16, new byte[]{'\n'}).encode(xml)), xml);
        try {
            KeyboxUpdate.decode("not base64".getBytes());
            assert false : "non-base64 download accepted";
        } catch (java.io.IOException expected) { }

        byte[] archive = archivedKeybox(Paths.get(args[0]));
        // The keybox three earlier releases installed has to keep the identity this module
        // recognises, or those devices never get a working key again.
        assert sha(archive).equals(KeyboxUpdate.ARCHIVE);
        List<KeyboxUpdate.Entry> entries = KeyboxUpdate.entries(archive);
        assert entries.size() == 2 : "expected an EC and an RSA chain, got " + entries.size();
        for (KeyboxUpdate.Entry entry : entries) {
            // Every key signs for its own certificate, EC and RSA alike.
            KeyboxUpdate.match(entry.leaf(), entry.key);
        }
        // Both entries' signatures verify within their own chain, and the file is then refused
        // because it ends at the AOSP software root rather than a Google attestation root.
        try {
            KeyboxUpdate.verify(archive);
            assert false : "software keybox accepted";
        } catch (Exception expected) {
            assert expected.getMessage().contains("attestation root") : expected.toString();
        }
        // Without the clock, the same file still stops at the root: the pin is what refuses it.
        try {
            KeyboxUpdate.verify(archive, false);
            assert false : "software keybox accepted without its dates";
        } catch (Exception expected) {
            assert expected.getMessage().contains("attestation root") : expected.toString();
        }

        // One <Keybox> holding both keys is the common factory shape, and each key keeps its own
        // chain: the daemon reads them one at a time, so merging them would fail on a good file.
        String text = new String(archive, java.nio.charset.StandardCharsets.UTF_8);
        java.util.regex.Matcher blocks = java.util.regex.Pattern
                .compile("<Key\\b[^>]*>[\\s\\S]*?</Key>").matcher(text);
        java.util.List<String> keys = new java.util.ArrayList<>();
        while (blocks.find()) keys.add(blocks.group());
        assert keys.size() == 2 : "expected two keys, got " + keys.size();
        String merged = "<AndroidAttestation><Keybox DeviceID=\"1\">" + keys.get(0) + keys.get(1)
                + "</Keybox></AndroidAttestation>";
        byte[] both = merged.getBytes(java.nio.charset.StandardCharsets.UTF_8);
        assert KeyboxUpdate.entries(both).size() == 2;
        for (KeyboxUpdate.Entry entry : KeyboxUpdate.entries(both)) KeyboxUpdate.match(entry.leaf(), entry.key);

        // Swapping the two private keys must be caught: they no longer sign for their chains.
        java.util.regex.Matcher pems = java.util.regex.Pattern.compile(
                "-----BEGIN (?:EC |RSA )?PRIVATE KEY-----[\\s\\S]*?-{5}END (?:EC |RSA )?PRIVATE KEY-----")
                .matcher(merged);
        assert pems.find();
        String ec = pems.group();
        assert pems.find();
        String rsaKey = pems.group();
        String swapped = merged.replace(ec, "\u0000").replace(rsaKey, ec).replace("\u0000", rsaKey);
        try {
            for (KeyboxUpdate.Entry entry : KeyboxUpdate.entries(
                    swapped.getBytes(java.nio.charset.StandardCharsets.UTF_8)))
                KeyboxUpdate.match(entry.leaf(), entry.key);
            assert false : "private key of another entry accepted";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("private key") : expected.toString();
        }
        // A file that stops early, or hides text in a comment, is not the file the daemon reads.
        try {
            KeyboxUpdate.entries(text.substring(0, text.lastIndexOf("</Keybox>") + 9)
                    .getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assert false : "truncated keybox accepted";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("Not a keybox") : expected.toString();
        }
        // A key hidden in a comment is not a key, and must not count as one.
        byte[] commented = text.replaceFirst("<Key\\b", "<!--<Key>x</Key>--><Key")
                .getBytes(java.nio.charset.StandardCharsets.UTF_8);
        assert KeyboxUpdate.entries(commented).size() == 2 : "comment read as markup";
        try {
            KeyboxUpdate.entries(text.replaceFirst("<Key\\b", "<!DOCTYPE x><Key")
                    .getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assert false : "keybox with a DTD accepted";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("DTD") : expected.toString();
        }

        // A key that cannot be checked is refused, and so is an entry with no key at all, because
        // the whole file gets published and the daemon will try every entry in it.
        String keyless = text.replaceFirst("(?s)-----BEGIN RSA PRIVATE KEY-----.*?-{5}END RSA PRIVATE KEY-----", "");
        assert !keyless.equals(text);
        try {
            KeyboxUpdate.entries(keyless.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assert false : "entry without a private key accepted";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("private key") : expected.toString();
        }
        java.util.regex.Matcher rsa = java.util.regex.Pattern
                .compile("-----BEGIN RSA PRIVATE KEY-----.*?-{5}END RSA PRIVATE KEY-----",
                        java.util.regex.Pattern.DOTALL)
                .matcher(text);
        assert rsa.find();
        String certless = "<AndroidAttestation><Keybox><Key algorithm=\"rsa\">" + rsa.group()
                + "</Key></Keybox></AndroidAttestation>";
        try {
            KeyboxUpdate.entries(certless.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            assert false : "entry without a certificate accepted";
        } catch (Exception expected) {
            assert expected.getMessage().contains("certificate") : expected.toString();
        }
        // With the archive's own roots pinned for this test, the same file passes: structure,
        // links and key possession are sound, and only the root held it back.
        List<String> roots = KeyboxUpdate.ROOTS;
        List<String> original = new java.util.ArrayList<>(roots);
        for (int i = 0; i < entries.size(); i++) {
            List<java.security.cert.X509Certificate> chain = entries.get(i).chain;
            roots.set(i, KeyboxUpdate.spki(chain.get(chain.size() - 1)));
        }
        assert KeyboxUpdate.verify(archive, false) != null : "sound keybox refused";
        for (int i = 0; i < original.size(); i++) roots.set(i, original.get(i));

        // Publication: create, rotate, and the two cases where someone else got there first.
        Path temp = java.nio.file.Files.createTempDirectory("keybox-install");
        Path store = temp.resolve("tricky_store/keybox.xml");
        Path records = temp.resolve("records");
        byte[] one = "one".getBytes(), two = "two".getBytes(), three = "three".getBytes();
        KeyboxUpdate.install(store, records, one, sha(one), null);
        assert java.util.Arrays.equals(one, java.nio.file.Files.readAllBytes(store));
        assert sha(one).equals(KeyboxUpdate.read(records.resolve("shipped")));
        assert KeyboxUpdate.read(records.resolve("installing")) == null : "pending record kept";
        KeyboxUpdate.install(store, records, two, sha(two), sha(one));
        assert java.util.Arrays.equals(two, java.nio.file.Files.readAllBytes(store));
        assert sha(two).equals(KeyboxUpdate.read(records.resolve("shipped")));
        // Another writer replaced the store while this one was downloading.
        try {
            KeyboxUpdate.install(store, records, three, sha(three), sha(one));
            assert false : "replaced a keybox that changed during the refresh";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("changed") : expected.toString();
        }
        assert java.util.Arrays.equals(two, java.nio.file.Files.readAllBytes(store));
        assert KeyboxUpdate.read(records.resolve("installing")) == null : "pending record left behind";
        // A first install loses the race to a file that appeared meanwhile.
        try {
            KeyboxUpdate.install(store, records, three, sha(three), null);
            assert false : "replaced a keybox that appeared during the refresh";
        } catch (java.io.IOException expected) {
            assert expected.getMessage().contains("appeared") : expected.toString();
        }
        assert java.util.Arrays.equals(two, java.nio.file.Files.readAllBytes(store));
        assert KeyboxUpdate.read(records.resolve("installing")) == null;

        System.out.println("Keybox refresh policy passed");
    }

    private static String sha(byte[] bytes) throws Exception {
        StringBuilder hex = new StringBuilder();
        for (byte value : java.security.MessageDigest.getInstance("SHA-256").digest(bytes))
            hex.append(String.format("%02x", value));
        return hex.toString();
    }

    private static byte[] archivedKeybox(Path root) throws Exception {
        Path archive = root.resolve("prebuilts/rootmods/system/etc/onigiri-rootmods/40-tricky_store.zip");
        try (ZipFile zip = new ZipFile(archive.toFile());
             InputStream in = zip.getInputStream(zip.getEntry("keybox.xml"))) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            for (int read; (read = in.read(buffer)) > 0; ) out.write(buffer, 0, read);
            return out.toByteArray();
        }
    }
}
