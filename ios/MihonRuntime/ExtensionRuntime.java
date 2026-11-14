package io.kuchie.runtime;

import fi.iki.elonen.NanoHTTPD;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.CountDownLatch;
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
            return active.getListeningPort();
        }
        if (token.length() < 32) {
            throw new IllegalArgumentException("Missing runtime token");
        }
        if (!dependenciesReady) {
            MainKt.initApplication(dataDirectory);
            InjektKt.getInjekt().addSingleton(() -> ProtoBuf.class, ProtoBuf.Default);
            dependenciesReady = true;
        }
        var listener = new ExtensionRuntime(port, token);
        listener.start(SOCKET_READ_TIMEOUT, false);
        MihonImageProxy.INSTANCE.configure(listener.getListeningPort());
        active = listener;
        return listener.getListeningPort();
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
        if (!path.equals("/capabilities") && !path.equals("/dalvik")) {
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
                    "imageProxy":true,"sourceUrls":true,"extensionHandles":true,"extensionInfo":true}
                    """);
        }
        if (path.equals("/dalvik") && method == Method.POST) {
            return new DalvikHandler().serve(request);
        }
        return newFixedLengthResponse(Response.Status.METHOD_NOT_ALLOWED, MIME_PLAINTEXT, "");
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
