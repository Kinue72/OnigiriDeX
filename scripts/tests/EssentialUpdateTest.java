package moe.foss.onigiri;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;

public final class EssentialUpdateTest {
    interface Action { void run() throws Exception; }
    static void rejects(Action action) throws Exception {
        try { action.run(); } catch (IOException | IllegalArgumentException expected) { return; }
        throw new AssertionError("Accepted invalid input");
    }
    static byte[] zipMember(Path zip, String member) throws Exception {
        try (ZipFile z = new ZipFile(zip.toFile())) { return EssentialUpdate.member(z, member); }
    }

    public static void main(String[] args) throws Exception {
        Path root = Paths.get(args[0]);
        Path temp = Files.createTempDirectory("essential-java-test-");
        try {
            Path inputs = root.resolve("prebuilts/rootmods");
            Properties feed = EssentialUpdate.readProperties(inputs.resolve("bundled.properties"));
            String[] ids = {"hma", "tee", "brene"};
            String[] archives = {"30-hma_oss_zygisk.zip", "40-tricky_store.zip", "60-brene.zip"};
            for (int i = 0; i < ids.length; i++) {
                String id = ids[i];
                Path archive = inputs.resolve("system/etc/onigiri-rootmods/" + archives[i]);
                Path dest = temp.resolve(id);
                EssentialUpdate.extract(id, archive, dest, feed);
                assert EssentialUpdate.compatibleAdapter(feed, id, temp);
                Properties otherAdapter = new Properties(); otherAdapter.putAll(feed);
                otherAdapter.setProperty(id + ".adapter", id.equals("hma") ? "1" : "2");
                assert !EssentialUpdate.compatibleAdapter(otherAdapter, id, temp);
                otherAdapter.remove(id + ".adapter");
                rejects(() -> EssentialUpdate.compatibleAdapter(otherAdapter, id, temp));
                if (id.equals("hma")) {
                    byte[] originalDex = zipMember(archive, "classes.dex");
                    byte[] fixedDex = zipMember(dest.resolve("hma.jar"), "classes.dex");
                    assert !Arrays.equals(originalDex, fixedDex);
                    Path patched = temp.resolve("patched.dex");
                    Files.write(patched, fixedDex);
                    assert EssentialUpdate.sha256(patched).equals("98fce9faddb1ec1695d1e98d1b131a66b2dc5d92e70d3b8d2f9423cb60387264");
                    for (int n = 0; n < originalDex.length; n++) {
                        if ((n >= 8 && n < 32) || (n >= 0x655ae && n < 0x655be) || n == 0x655ce || (n >= 0x7a77c && n < 0x7a780)) continue;
                        assert originalDex[n] == fixedDex[n] : "Unrelated HMA byte changed at " + n;
                    }
                    originalDex[originalDex.length - 1] ^= 1;
                    rejects(() -> HmaHookPatch.apply(originalDex));
                    rejects(() -> HmaHookPatch.apply(fixedDex));
                    assert Arrays.equals(zipMember(archive, "manager.apk"), Files.readAllBytes(dest.resolve("manager.apk")));
                } else if (id.equals("tee")) {
                    assert Arrays.equals(zipMember(archive, "keybox.xml"), Files.readAllBytes(dest.resolve("keybox.xml")));
                    assert Arrays.equals(zipMember(archive, "classes.dex"), Files.readAllBytes(dest.resolve("classes.dex")));
                } else {
                    assert new String(Files.readAllBytes(dest.resolve("rom-names")), "UTF-8").contains("lineage\n");
                    assert Arrays.equals(zipMember(archive, "tools/susfs"), Files.readAllBytes(dest.resolve("susfs")));
                }
                assert !Files.exists(dest.resolve("service.sh"));
                assert !Files.exists(dest.resolve("customize.sh"));
                Properties wrongHash = new Properties(); wrongHash.putAll(feed);
                wrongHash.setProperty(id + ".sha256", new String(new char[64]).replace('\0', '0'));
                rejects(() -> EssentialUpdate.extract(id, archive, temp.resolve("bad-hash"), wrongHash));
                Properties wrongModule = new Properties(); wrongModule.putAll(feed);
                wrongModule.setProperty(id + ".module", "unrelated");
                rejects(() -> EssentialUpdate.extract(id, archive, temp.resolve("bad-module"), wrongModule));
            }
            // The extractor only writes explicitly named members, even in a validly hashed ZIP.
            Path traversal = temp.resolve("traversal.zip");
            Path original = inputs.resolve("system/etc/onigiri-rootmods/30-hma_oss_zygisk.zip");
            try (ZipFile zip = new ZipFile(original.toFile()); ZipOutputStream out = new ZipOutputStream(Files.newOutputStream(traversal))) {
                for (String name : Arrays.asList("module.prop", "classes.dex", "manager.apk")) {
                    out.putNextEntry(new ZipEntry(name)); out.write(EssentialUpdate.member(zip, name)); out.closeEntry();
                }
                out.putNextEntry(new ZipEntry("../../escaped")); out.write(42); out.closeEntry();
            }
            Properties extra = new Properties(); extra.putAll(feed);
            extra.setProperty("hma.sha256", EssentialUpdate.sha256(traversal));
            extra.setProperty("hma.bytes", Long.toString(Files.size(traversal)));
            EssentialUpdate.extract("hma", traversal, temp.resolve("safe"), extra);
            assert !Files.exists(temp.getParent().resolve("escaped"));
            assert !Files.exists(temp.resolve("escaped"));
            rejects(() -> EssentialUpdate.download("http://github.com/payload", temp.resolve("download"), 100));
            rejects(() -> EssentialUpdate.download("https://example.org/payload", temp.resolve("download"), 100));
            rejects(() -> EssentialUpdate.copy(new ByteArrayInputStream(new byte[100]), new ByteArrayOutputStream(), 99));
            Path state = temp.resolve("state/hma"); Files.createDirectories(state);
            EssentialUpdate.atomicText(state.resolve("active"), "../../bad");
            rejects(() -> EssentialUpdate.payload(temp.resolve("state"), temp, "hma"));
            Files.delete(state.resolve("active"));
            assert EssentialUpdate.payload(temp.resolve("state"), temp, "hma").equals(temp.resolve("hma"));
            System.out.println("Upstream payload identity, checksums, module identity, archive boundaries, URL restrictions and fallback passed");
        } finally { EssentialUpdate.removeTree(temp); }
    }
}
