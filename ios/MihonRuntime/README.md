# iOS extension runtime

The Local collection runs compatible Mihon manga APKs through M-Extension-Server. iPhone builds embed the OpenJDK Zero interpreter as a signed framework. The app starts it on the first request for an extension, opens a loopback listener on an OS-assigned port, and uses a per-process token to authorize API calls. The interpreter stays available for subsequent requests within the app session.

## Preparing an iPhone build

Install JDK 21 and Xcode, then run from the repository root.

```sh
ios/MihonRuntime/prepare.sh
flutter build ios
```

Use `JAVA_HOME` if JDK 21 is installed outside the standard macOS location. The setup script verifies the pinned archives by SHA-256 and prepares the app-local runtime. Xcode embeds the prepared files in iPhone builds and signs the framework when signing is enabled. Other iPhone builds can use the Server collection and local file imports with the runtime omitted.

OpenJDK Zero executes extension bytecode that users choose to download. Confirm Apple's applicable distribution rules before distributing a build with the runtime included. See [third-party notices](THIRD_PARTY_NOTICES.md) for the runtime sources and licenses.

## Kuchie additions

- `BytecodeOverlay` drops the image proxy's HTTP/1.1 pin: Cloudflare refuses a browser user agent over HTTP/1.1 (Danbooru's image server), and the extension's own requests already use HTTP/2.
- `ExtensionRuntime` applies a `/dalvik` request's user agent before the extension loads, because an extension builds its headers once on load.

`ExtensionRuntime.java` and `DexJarCache.java` are compiled into `KuchieExtensionRuntime.jar` by `prepare.sh`:

- If iOS closed the loopback listener while Kuchie was suspended, the next start opens a new one; loaded extensions stay in memory.
- `DELETE /cookies` empties the cookie jar extensions share (Settings → Advanced → Clear cookies).
- `BytecodeOverlay.java` routes the loader's `PackageTools.dex2jar` call to `DexJarCache`, which keeps each translated JAR under the APK's SHA-256 in `MihonExtensions/dex-jar-cache`. Entries are dropped when the runtime JARs change; bump `DexJarCache.FORMAT` when the translation changes without them changing.

The app sends a `User-Agent` header with every `/dalvik` request (Settings → Advanced → User agent), which the runtime makes the extensions' default, and forwards the WebView's cookies for the source's site with `Cookie` and `Source-Base-Url`.

## Server JAR

`fetch_server.sh` downloads `MExtensionServer-ios.jar` from this repository's `ios-runtime-v17` release and checks its SHA-256. It is built from [1Selxo/M-Extension-Server@6a11ad7](https://github.com/1Selxo/M-Extension-Server/tree/6a11ad771bc1c59303ce5d1e2b6f610211dcb819) (v1.0.8.1) with the patches in `patches/`:

- `0001-keep-extension-user-agent.patch`: the default user-agent only fills in a missing header, as in Mihon, so extensions that set their own (MangaDex) are not rejected.
- `0002-detached-view-has-no-parent.patch`: `View.getParent()` returns `null`, as for a detached view on Android, instead of throwing; Turnstile solvers check it.
- `0003-bitmap-webp-and-pixel-access.patch`: `BitmapFactory` falls back to the pure-Java WebP reader when the native one cannot load (always on iOS), and `Bitmap` gains `setPixels`, `getPixel` and `setPixel`, so extensions that descramble pages work.

To rebuild it with JDK 21:

```sh
git clone https://github.com/1Selxo/M-Extension-Server && cd M-Extension-Server
git checkout 6a11ad771bc1c59303ce5d1e2b6f610211dcb819
git apply /path/to/Kuchie/ios/MihonRuntime/patches/*.patch
./AndroidCompat/getAndroid.sh
./gradlew :server:test :server:shadowJar -PiosRuntime=true
```

## Simulator development

The pinned OpenJDK package has only an arm64 iPhone slice, so Simulator builds run the same Java extension bridge on Mac loopback. Install JDK 21 (`brew install openjdk@21`) and build a Debug Simulator app as usual: the Xcode build phase calls `tool/qa/ensure_simulator_runtime.sh`, which starts the bridge on port 14569 (or restarts it when its sources changed) and writes the port and token to `~/development/kuchie-qa-extension-runtime`. The Debug app reads them from there, so no launch environment is needed. Without JDK 21 the build prints a warning and Simulator extensions stay unavailable.

Launch environment variables still take precedence, for UI tests or a second host:

```sh
SIMCTL_CHILD_KUCHIE_QA_EXTENSION_RUNTIME_PORT=14569 \
SIMCTL_CHILD_KUCHIE_QA_EXTENSION_RUNTIME_TOKEN="$(cat ~/development/kuchie-qa-extension-runtime/runtime.token)" \
  xcrun simctl launch booted app.kuchie.reader
```

For a UI test, provide the same port and token in `XCUIApplication.launchEnvironment` without the `SIMCTL_CHILD_` prefix. Simulator access to the Mac host is compiled into Debug only.
