package moe.foss.onigiri;

import java.io.IOException;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.zip.Adler32;

/** Adapter 2: prepare oss-173's original-call trampoline before publishing its hook. */
final class HmaHookPatch {
    private static byte[] hex(String text) {
        byte[] bytes = new byte[text.length() / 2];
        for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(text.substring(i * 2, i * 2 + 2), 16);
        return bytes;
    }

    static byte[] apply(byte[] original) throws Exception {
        // These offsets and registers belong only to the reviewed upstream dex, never a guessed version.
        MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
        if (!Arrays.equals(sha256.digest(original), hex("a23261736dad9c0110b2cd481e20cc2f4cd970121a8701571ff023ec296f3a27"))) {
            throw new IOException("Unsupported HMA hook engine; ROM update required");
        }
        byte[] dex = original.clone();
        // Hooks.hookSwap: invoker -> original first, then target -> invoker. Save the first result in v2/v3.
        byte[] calls = hex("7140b70b94ba0b027140b70b49100b00");
        System.arraycopy(calls, 0, dex, 0x655ae, calls.length);
        dex[0x655ae + 32] = 0x32; // Pair.second boxes v2/v3 instead of p0/p1.
        MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
        sha1.update(dex, 32, dex.length - 32);
        System.arraycopy(sha1.digest(), 0, dex, 12, 20);
        Adler32 checksum = new Adler32();
        checksum.update(dex, 12, dex.length - 12);
        long value = checksum.getValue();
        for (int i = 0; i < 4; i++) dex[8 + i] = (byte) (value >>> (i * 8));
        if (!Arrays.equals(sha256.digest(dex), hex("a93a489843bd52753d50c1caf127dc9878a33af1f3a8c2eb8562bf2a61ae88a0"))) {
            throw new IOException("HMA hook patch verification failed");
        }
        return dex;
    }
}
