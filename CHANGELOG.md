# Changelog

All notable changes to Kuchie are listed here. Versions follow [Semantic Versioning](https://semver.org).

## [1.0.0] - 2026-11-16

First public release.

### Collections
- Choose **Local** or **Server** at first launch and switch any time; each collection keeps its own library, history and downloads.
- **Server**: Suwayomi libraries, updates, history, download queue, trackers, migration and backups, with network discovery and no-auth, basic or UI-login servers.
- **Local**: import CBZ/ZIP archives and image folders, Kuchie extension repositories, and offline chapters saved on the iPhone.

### Mihon extension stores
- Add any store Mihon accepts: v2 indexes (`index.pb` protobuf or JSON, gzipped or not, with `extensionListUrl`), `repo.json` with `index_v2`, legacy `index.min.json`, and `mihon://` / `tachiyomi://add-repo` links. Tested with Keiyoushi, Suwayomi and Yūzōnō stores.
- APKs install only when their APK Signature Scheme v2/v3 signature verifies and the signer matches the store's signing key. Tampered APKs, APKs signed by another key, stores without a key, plain-HTTP stores and stores that change their key are refused with a clear message.

### Reader and app
- Paged and continuous reading modes, chapter-to-chapter reading and page actions.
- Live Activities and Dynamic Island for downloads, Liquid Glass controls on iOS 26, themes, alternate app icons and 20+ languages.
- The in-app update check and project links point to github.com/kuchie-app/Kuchie by default.

### Fixed
- History showed the resume page one lower than the reader (for example 1/18 while reading page 2).
- Library category filters could notify listeners while a widget was building, which Riverpod forbids.
- Release logging, HTTP client leaks and startup crash handling.

### Extension runtime
- The embedded runtime is M-Extension-Server v1.0.8.1 (built for iOS from 1Selxo/M-Extension-Server@6a11ad7), which repairs constructors of R8-optimised classes. Release IPAs now include the runtime.
- Accept the empty URLs and blank titles that single-series sources return, as Mihon does.
- In a random sample of 44 extensions, 30 work end to end (browse, details, chapters, pages).

### Known limitations
- No WebView bridge yet, so sources behind Cloudflare challenges fail.
- No extension settings screen yet, so extensions that must be configured first (such as Suwayomi's server address) fail.
- A few extensions still fail in the runtime's dex-to-JVM translation.

[1.0.0]: https://github.com/kuchie-app/Kuchie/releases/tag/v1.0.0
