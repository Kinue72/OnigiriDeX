package moe.foss.onigiri;

/** Host tests for the keybox refresh policy. The network path needs a device. */
public final class KeyboxUpdateTest {
    public static void main(String[] args) throws Exception {
        // Nothing in place: ours to install.
        assert KeyboxUpdate.replaceable(null, null, null, false);
        // The file is the one this module recorded.
        assert KeyboxUpdate.replaceable("aaa", "aaa", null, false);
        // A working file it did not install, and did not record, is someone else's.
        assert !KeyboxUpdate.replaceable(null, "bbb", "aaa", false);
        assert !KeyboxUpdate.replaceable(null, "bbb", null, false);
        // A recorded file that changed underneath us was replaced by hand: leave it alone.
        assert !KeyboxUpdate.replaceable("aaa", "bbb", "bbb", false);
        // An upgrade from a build without the marker adopts the ROM payload it seeded.
        assert KeyboxUpdate.replaceable(null, "aaa", "aaa", false);
        // A dead keybox cannot be serving anyone, whoever installed it.
        assert KeyboxUpdate.replaceable(null, "bbb", "aaa", true);
        assert KeyboxUpdate.replaceable("aaa", "bbb", null, true);
        // The mirror serves base64; a pinned URL may serve the XML directly.
        byte[] xml = "<AndroidAttestation/>".getBytes();
        assert java.util.Arrays.equals(KeyboxUpdate.decode(xml), xml);
        assert java.util.Arrays.equals(KeyboxUpdate.decode(
                java.util.Base64.getMimeEncoder().encode(xml)), xml);
        assert java.util.Arrays.equals(KeyboxUpdate.decode(("  \n" + new String(xml)).getBytes()),
                ("  \n" + new String(xml)).getBytes());
        // Garbage in place is dead, so a refresh may replace it.
        assert KeyboxUpdate.dead("not a keybox".getBytes());
        System.out.println("Keybox refresh policy passed");
    }
}
