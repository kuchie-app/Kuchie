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
- Every APK's Signature Scheme v2/v3 signature is verified. APKs signed by their store's key install directly; others install only after you trust their signer, as in Mihon. Tampered APKs, plain-HTTP stores and stores that change their key are refused with a clear message.

### Reader and app
- Paged and continuous reading modes, chapter-to-chapter reading and page actions. Webtoon (continuous vertical) is the default.
- The page slider starts at page 1 on the left in every reading direction.
- Live Activities and Dynamic Island for downloads, Liquid Glass controls on iOS 26, themes, alternate app icons and 20+ languages.
- The in-app update check and project links point to github.com/kuchie-app/Kuchie by default.

### Fixed
- History showed the resume page one lower than the reader (for example 1/18 while reading page 2).
- Library category filters could notify listeners while a widget was building, which Riverpod forbids.
- Release logging, HTTP client leaks and startup crash handling.

### Extension runtime and compatibility
- The embedded runtime is M-Extension-Server v1.0.8.1, built for iOS with three Kuchie patches (extension user-agents, detached views, WebP and bitmap pixels). Release IPAs include it.
- Cloudflare challenges are solved in a hidden WebView, using Mangayomi's remote WebView bridge.
- **Source settings** for extensions that offer them (server addresses, logins, languages, mirrors).
- Untrusted APKs (not signed by their store's key, or from stores without a SHA-256 key) install after you trust their signer, as in Mihon. Anime extensions and unsupported extension-lib versions are left out, as in Mihon.
- Fixed: UTF-8 requests to the runtime, full chapter data for page lists, empty URLs, large catalogues, long APK loads, and the 32-store limit.
- Tested against 80 public stores and 211 extensions with Suwayomi-Server as a reference; see docs/extension-compatibility.md.

### Known limitations
- Some extensions apply a changed setting only after Kuchie restarts, as in Mihon.
- Extensions built for Mihon forks (Komikku, Kotatsu, novel readers) need APIs Mihon does not have.

[1.0.0]: https://github.com/kuchie-app/Kuchie/releases/tag/v1.0.0
