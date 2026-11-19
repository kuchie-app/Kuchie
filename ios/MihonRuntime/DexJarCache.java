package io.kuchie.runtime;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Comparator;
import mextensionserver.util.PackageTools;

/**
 * Keeps the JVM classes translated from each extension APK between launches.
 *
 * <p>The runtime translates an APK's DEX code to JVM classes every time it loads
 * the extension. Under the Zero interpreter that translation is the slowest part
 * of opening an extension after Kuchie restarts. BytecodeOverlay routes the
 * loader's {@code PackageTools.dex2jar} call here; the translated JAR is stored
 * under the APK's SHA-256 in app-private storage and copied back on the next
 * load. Entries are dropped whenever the runtime's own JARs change.
 */
public final class DexJarCache {
    // Bump when the DEX translation changes without the runtime JARs changing.
    private static final String FORMAT = "1";
    private static final int MAX_ENTRIES = 48;
    private static final String STAMP_FILE = "runtime-stamp";
    private static volatile File directory;

    private DexJarCache() {}

    static synchronized void configure(String dataDirectory) {
        if (directory != null) {
            return;
        }
        File candidate = new File(dataDirectory, "dex-jar-cache");
        if (!candidate.isDirectory() && !candidate.mkdirs()) {
            return;
        }
        String stamp = runtimeStamp();
        File stampFile = new File(candidate, STAMP_FILE);
        try {
            String previous = stampFile.isFile()
                    ? Files.readString(stampFile.toPath(), StandardCharsets.UTF_8)
                    : "";
            if (!stamp.equals(previous)) {
                clear(candidate);
                Files.writeString(stampFile.toPath(), stamp, StandardCharsets.UTF_8);
            }
            directory = candidate;
        } catch (IOException | RuntimeException error) {
            // Without a trustworthy stamp the cache stays off; loading still works.
        }
    }

    /** Called instead of {@code PackageTools.INSTANCE.dex2jar(apk, jar)}. */
    public static void dex2jar(PackageTools tools, File apk, File jar) {
        File cacheDirectory = directory;
        String key = cacheDirectory == null ? null : key(apk);
        if (key != null) {
            File cached = new File(cacheDirectory, key + ".jar");
            if (cached.isFile() && cached.length() > 0) {
                try {
                    Files.copy(cached.toPath(), jar.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    cached.setLastModified(System.currentTimeMillis());
                    return;
                } catch (IOException | RuntimeException error) {
                    cached.delete();
                }
            }
        }
        tools.dex2jar(apk, jar);
        if (key != null && jar.isFile() && jar.length() > 0) {
            store(cacheDirectory, key, jar);
        }
    }

    private static void store(File cacheDirectory, String key, File jar) {
        File partial = new File(cacheDirectory, key + ".partial");
        try {
            Files.copy(jar.toPath(), partial.toPath(), StandardCopyOption.REPLACE_EXISTING);
            Files.move(partial.toPath(), new File(cacheDirectory, key + ".jar").toPath(),
                    StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            prune(cacheDirectory);
        } catch (IOException | RuntimeException error) {
            partial.delete();
        }
    }

    private static void prune(File cacheDirectory) {
        File[] entries = cacheDirectory.listFiles((dir, name) -> name.endsWith(".jar"));
        if (entries == null || entries.length <= MAX_ENTRIES) {
            return;
        }
        Arrays.sort(entries, Comparator.comparingLong(File::lastModified));
        for (int i = 0; i < entries.length - MAX_ENTRIES; i++) {
            entries[i].delete();
        }
    }

    private static void clear(File cacheDirectory) {
        File[] entries = cacheDirectory.listFiles();
        if (entries == null) {
            return;
        }
        for (File entry : entries) {
            if (entry.isFile()) {
                entry.delete();
            }
        }
    }

    private static String key(File apk) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(Files.readAllBytes(apk.toPath()));
            var text = new StringBuilder(digest.length * 2);
            for (byte value : digest) {
                text.append(Character.forDigit((value >> 4) & 0xf, 16))
                        .append(Character.forDigit(value & 0xf, 16));
            }
            return text.toString();
        } catch (IOException | NoSuchAlgorithmException | RuntimeException error) {
            return null;
        }
    }

    /** Identifies the runtime build: each class path JAR's name, size and date. */
    private static String runtimeStamp() {
        var stamp = new StringBuilder(FORMAT);
        String classPath = System.getProperty("java.class.path", "");
        for (String entry : classPath.split(File.pathSeparator)) {
            File file = new File(entry);
            stamp.append('\n').append(file.getName()).append(':').append(file.length())
                    .append(':').append(file.lastModified());
        }
        return stamp.toString();
    }
}
