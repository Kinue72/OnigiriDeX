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
        List<KeyboxUpdate.Entry> entries = KeyboxUpdate.entries(archive);
        assert entries.size() == 2 : "expected an EC and an RSA chain, got " + entries.size();
        boolean checked = false;
        for (KeyboxUpdate.Entry entry : entries) {
            if (entry.point == null) continue;
            // The EC entry's private key belongs to its own certificate, checked off-device.
            KeyboxUpdate.match(entry.leaf(), entry.point);
            checked = true;
        }
        assert checked : "no entry published a public point to check";
        // Both entries' signatures verify within their own chain, and the file is then refused
        // because it ends at the AOSP software root rather than a Google attestation root.
        try {
            KeyboxUpdate.verify(archive);
            assert false : "software keybox accepted";
        } catch (Exception expected) {
            assert expected.getMessage().contains("attestation root") : expected.toString();
        }
        System.out.println("Keybox refresh policy passed");
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
