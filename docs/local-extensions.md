# Kuchie Local extensions

From **Browse → Extensions**, open **Extension stores** and add the store URL. You can also import a `.kuchie-source` or `.json` package from Files. Install the extension and open it from **Browse → Sources**. Choose **Save to device** on a chapter to keep its pages locally.

## Mihon extension stores

Kuchie reads the same extension stores as [Mihon](https://github.com/mihonapp/mihon). Paste any store link Mihon accepts:

| Store format | Example link |
| --- | --- |
| v2 index (protobuf `index.pb` or JSON) | `https://github.com/keiyoushi/extensions/raw/repo/index.pb` |
| `repo.json` that points at a v2 index | `https://raw.githubusercontent.com/yuzono/cursed-manga-repo/repo/repo.json` |
| Legacy `index.min.json` with `repo.json` | `https://raw.githubusercontent.com/suwayomi/tachiyomi-extension/repo/index.min.json` |
| `mihon://` or `tachiyomi://add-repo?url=…` links | opened from a store website |

Gzipped indexes and stores that keep their list behind `extensionListUrl` work as well. Install a package, then choose a source and language from **Browse → Sources**. Kuchie keeps the APK in the Local profile and runs it through [M-Extension-Server](https://github.com/kodjodevf/M-Extension-Server). Extension compatibility depends on the Android APIs and services each source uses: sources behind Cloudflare challenges and sources that must be configured in their own settings do not work yet. Shinigami (Indonesia) also has a built-in adapter for existing Keiyoushi installations.

### How Kuchie decides an APK is safe

Kuchie follows Mihon's trust model and checks it before any extension code runs:

- Store indexes, APKs and icons load over HTTPS only. Plain HTTP is accepted for `127.0.0.1` in debug builds, for the QA fixtures.
- Every store publishes a signing key, the SHA-256 of the certificate it signs APKs with. A store without a valid key is refused.
- Kuchie verifies each APK's Android signature (APK Signature Scheme v2 or v3): the signature over the signed data, the certificate's key, and the digest of the whole archive. A modified APK, or one signed by anyone other than the store, is refused. APKs signed only with the legacy v1 scheme are not supported.
- A store that starts signing with a different key is treated as a different store; refreshing it fails until you remove it and add it again.
- An extension ID installed from one store cannot be replaced by a package from another store.
- Downloads have size limits, redirects are HTTPS-only and limited to five, and the installed APK is re-hashed before each use.

The iPhone device build uses the embedded OpenJDK Zero runtime. Run `ios/MihonRuntime/prepare.sh` before building for a device that needs APK support. For simulator development, `tool/qa/extension_runtime_host.sh` runs the backend on the Mac's loopback address and the Kuchie debug build connects to it. See the [XCUITest setup](../ios/ReaderGestureTests/README.md) for launch variables.

## Kuchie feeds

Kuchie v1 packages declare a JSON catalog URL. Each feed links to the next level.

## Try the sample

Run the fixture from the Kuchie checkout with Python 3. The sample uses HTTP loopback, which Kuchie enables in debug builds.

```sh
python3 tool/qa/local_source.py --export-cbz /tmp/Kuchie-Local-QA.cbz \
  --export-extension /tmp/Kuchie-QA.kuchie-source
```

Enter `http://127.0.0.1:14568/index.json` in the iOS Simulator. Install **QA Lantern Source**, open **QA Lantern Station**, and download **Chapter 01**. The exported archive can also be imported from Files once copied into the simulator's storage. The sample extension file uses the same loopback address as the index.

## Prepare a repository and source

Serve the index, packages, feeds, and images via HTTPS. A repository package URL must share the index's origin. Compute the SHA-256 digest from the exact bytes of the served extension file, then set `sha256` in the index. Use semantic versions and keep IDs stable between revisions.

```json
{
  "format": "kuchie.repository.v1",
  "name": "Example Repository",
  "extensions": [
    {
      "id": "example.press",
      "name": "Example Press",
      "version": "1.0.0",
      "language": "en",
      "url": "press.kuchie-source",
      "sha256": "<lowercase SHA-256 of press.kuchie-source>"
    }
  ]
}
```

The package uses the same ID, name, version, and language as its index entry. An imported package needs an absolute catalog URL. If a package uses a catalog on a different origin, set that origin in its index entry's `catalogOrigin`. An explicit `mediaOrigins` list allows separate origins for covers and page images.

```json
{
  "format": "kuchie.extension.v1",
  "id": "example.press",
  "name": "Example Press",
  "version": "1.0.0",
  "language": "en",
  "catalog": "https://comics.example/catalog.json"
}
```

| Feed | JSON shape |
| --- | --- |
| Catalog | `{"manga":[{"id":"lantern","title":"Lantern Station","chapters":"lantern/chapters.json"}]}` |
| Chapters | `{"chapters":[{"id":"chapter-01","title":"Chapter 01","pages":"chapter-01/pages.json"}]}` |
| Pages | `{"pages":["page-01.png","page-02.png"]}` |

Catalog entries can also include `description` and `cover`. Relative links resolve against the feed that contains them. Return page links in reading order. Keep feed links on the catalog origin and make each URL respond directly. Kuchie uses GET without source-defined request headers and does not follow redirects.
