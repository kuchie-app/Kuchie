package io.kuchie.runtime;

import fi.iki.elonen.NanoHTTPD;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.CountDownLatch;
import eu.kanade.tachiyomi.network.NetworkHelper;
import kotlinx.serialization.protobuf.ProtoBuf;
import mextensionserver.MainKt;
import mextensionserver.controller.DalvikHandler;
import mextensionserver.controller.ImageProxyHandler;
import mextensionserver.impl.MExtensionServerLoader;
import mextensionserver.impl.MihonImageProxy;
import uy.kohesive.injekt.InjektKt;

public final class ExtensionRuntime extends NanoHTTPD {
    private static final String AUTH_HEADER = "x-kuchie-runtime-token";
    private static ExtensionRuntime active;
    private static boolean dependenciesReady;
    private final byte[] token;

    private ExtensionRuntime(int port, String token) {
        super("127.0.0.1", port);
        this.token = token.getBytes(StandardCharsets.US_ASCII);
    }

    public static synchronized int start(int port, String dataDirectory, String token)
            throws IOException {
        if (active != null) {
            if (accepting(active.getListeningPort())) {
                return active.getListeningPort();
            }
            // iOS reclaims a suspended app's listening sockets. Open a new
            // listener; loaded extensions stay in memory.
            active.stop();
            active = null;
        }
        if (token.length() < 32) {
            throw new IllegalArgumentException("Missing runtime token");
        }
        if (!dependenciesReady) {
            MainKt.initApplication(dataDirectory);
            DexJarCache.configure(dataDirectory);
            InjektKt.getInjekt().addSingleton(() -> ProtoBuf.class, ProtoBuf.Default);
            dependenciesReady = true;
        }
        var listener = new ExtensionRuntime(port, token);
        listener.start(SOCKET_READ_TIMEOUT, false);
        MihonImageProxy.INSTANCE.configure(listener.getListeningPort());
        active = listener;
        return listener.getListeningPort();
    }

    private static boolean accepting(int port) {
        try (var probe = new Socket()) {
            probe.connect(new InetSocketAddress("127.0.0.1", port), 1000);
            return true;
        } catch (IOException error) {
            return false;
        }
    }

    public static synchronized void shutdown() {
        if (active != null) {
            active.stop();
            active = null;
            MExtensionServerLoader.INSTANCE.cleanupTempFiles();
        }
    }

    @Override
    public Response serve(IHTTPSession request) {
        String path = request.getUri();
        Method method = request.getMethod();
        if (path.startsWith(ImageProxyHandler.ROUTE_PREFIX) && method == Method.GET) {
            return new ImageProxyHandler().serve(request);
        }
        if (!path.equals("/capabilities") && !path.equals("/dalvik") && !path.equals("/cookies")) {
            return newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "");
        }
        String supplied = request.getHeaders().get(AUTH_HEADER);
        if (supplied == null ||
                !MessageDigest.isEqual(token, supplied.getBytes(StandardCharsets.US_ASCII))) {
            return newFixedLengthResponse(Response.Status.FORBIDDEN, MIME_PLAINTEXT, "");
        }
        if (path.equals("/capabilities") && method == Method.GET) {
            return newFixedLengthResponse(Response.Status.OK, "application/json",
                    """
                    {"mangayomiMihonBridge":1,"sourceFactory":true,"preferenceCallbacks":true,
                    "imageProxy":true,"sourceUrls":true,"extensionHandles":true,"extensionInfo":true,
                    "clearCookies":true}
                    """);
        }
        if (path.equals("/dalvik") && method == Method.POST) {
            // DalvikHandler loads the extension before it applies the request's
            // user agent, and an extension builds its headers, user agent
            // included, once on load. Applying it first keeps image requests
            // (Danbooru's CDN refuses the desktop Firefox default) on the
            // user agent Kuchie chose.
            applyUserAgent(request.getHeaders().get("user-agent"));
            return new DalvikHandler().serve(request);
        }
        if (path.equals("/cookies") && method == Method.DELETE) {
            // Extensions share one in-memory cookie jar, which also holds
            // Cloudflare clearance; Settings clears it with the WebView's.
            try {
                NetworkHelper network = InjektKt.getInjekt().getInstance(NetworkHelper.class);
                network.getCookieJar().clear();
                return newFixedLengthResponse(Response.Status.NO_CONTENT, MIME_PLAINTEXT, "");
            } catch (RuntimeException error) {
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, MIME_PLAINTEXT, "");
            }
        }
        return newFixedLengthResponse(Response.Status.METHOD_NOT_ALLOWED, MIME_PLAINTEXT, "");
    }

    private static void applyUserAgent(String userAgent) {
        if (userAgent == null || userAgent.isBlank()) {
            return;
        }
        try {
            NetworkHelper network = InjektKt.getInjekt().getInstance(NetworkHelper.class);
            network.setUA(userAgent.trim());
        } catch (RuntimeException error) {
            // DalvikHandler applies it again once the extension is loaded.
        }
    }

    public static void main(String[] args) throws InterruptedException, IOException {
        String token = System.getenv("KUCHIE_QA_EXTENSION_RUNTIME_TOKEN");
        if (args.length != 2 || token == null) {
            throw new IllegalArgumentException("Set a QA runtime token and supply a port and data directory");
        }
        int port = start(Integer.parseInt(args[0]), args[1], token);
        Runtime.getRuntime().addShutdownHook(new Thread(ExtensionRuntime::shutdown));
        System.out.println("Extension runtime listening on 127.0.0.1:" + port);
        new CountDownLatch(1).await();
    }
}
