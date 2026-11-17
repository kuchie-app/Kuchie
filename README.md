<p align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Default.png" width="120" alt="Kuchie app icon">
</p>

<h1 align="center">Kuchie</h1>

<p align="center">
  An iPhone reader for manga and webtoons, with Apple Liquid Glass controls on iOS 26.
</p>

<p align="center">
  <a href="https://github.com/kuchie-app/Kuchie/actions/workflows/ci.yml"><img src="https://github.com/kuchie-app/Kuchie/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/kuchie-app/Kuchie/releases/latest"><img src="https://img.shields.io/github/v/release/kuchie-app/Kuchie" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="License: MPL-2.0"></a>
  <img src="https://img.shields.io/badge/platform-iOS-lightgrey" alt="Platform: iOS">
</p>

---

Kuchie lets you read from two kinds of collection. Pick one the first time you open the app and switch any time from **Library** or **More → Collection mode**; each keeps its own library.

- **Local** keeps your library, history and downloads on your iPhone. Import CBZ/ZIP archives and image folders from Files, add Kuchie extension repositories, or add any [Mihon extension store](docs/local-extensions.md#mihon-extension-stores).
- **Server** connects to a [Suwayomi](https://github.com/Suwayomi/Suwayomi-Server) server for your server library, history, download queue and trackers. Chapters can also be saved to the iPhone for offline reading.

## Features

- **Reader**: paged (right-to-left, left-to-right, vertical) and continuous webtoon modes, chapter-to-chapter reading, zoom, page actions, reading progress synced to the server or kept locally.
- **Library**: categories, filters, sorting, unread badges, search, duplicate finder, ratings, notes and tags.
- **Updates and history** for both collections, with resume-where-you-left-off.
- **Offline**: save chapters to the device, with download progress in Live Activities and the Dynamic Island.
- **Extensions** (Local): Mihon stores (Keiyoushi, Suwayomi, Yūzōnō and others), Kuchie repositories, and imported packages. Every APK is checked against its store's signing key before it runs; see [how Kuchie decides an APK is safe](docs/local-extensions.md#how-kuchie-decides-an-apk-is-safe).
- **Server tools**: extensions, migration between sources, trackers, backups and server settings for Suwayomi.
- **Appearance**: themes, pure black, Liquid Glass, alternate Home Screen icons, and 20+ languages.

## Install

Kuchie is distributed as an unsigned IPA on the [Releases](https://github.com/kuchie-app/Kuchie/releases) page.

1. Download `Kuchie-vX.Y.Z-unsigned.ipa` and check it against the `.sha256` file next to it.
2. Sign and install it with your own Apple ID or developer team, for example with [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or Xcode.

Kuchie needs iOS 15 or later. Liquid Glass controls need iOS 26; earlier versions use the standard controls.

## Getting started

- **Local**: choose *Local* in onboarding, then **Import manga** from Files or **Browse → Extensions → Extension stores → +** to add a store link. Details are in [Local extensions](docs/local-extensions.md).
- **Server**: choose *Server*, enter your Suwayomi address (for example `http://192.168.1.10:4567`), or tap **Search my network**. Kuchie supports no-auth, basic and UI-login servers.

Kuchie uses the bundle ID `app.kuchie.reader` with its own settings, credentials and offline files.

## Build from source

Requirements: macOS with Xcode 26 or newer, the Flutter version pinned in [`.fvmrc`](.fvmrc), and an iOS simulator or device. Flutter resolves the native plugins through Swift Package Manager.

```sh
tool/bootstrap                                   # pub get + code generation
flutter build ios --simulator --debug --no-codesign
flutter run -d <simulator-id>
```

For a physical iPhone, open `ios/Runner.xcworkspace`, pick a signing team for **Runner** and **DownloadLiveActivity**, and use bundle IDs registered to that team (the extension uses the app's bundle ID plus `.DownloadLiveActivity`).

To run Mihon APK extensions on a device, prepare the embedded OpenJDK runtime first (needs JDK 21):

```sh
ios/MihonRuntime/prepare.sh
flutter build ios
```

Builds without the runtime still support the Server collection, Kuchie repositories and file imports. See [the runtime notes](ios/MihonRuntime/README.md) before distributing a build that includes it.

### Release configuration

Release links default to this repository. A fork can point them elsewhere with `--dart-define`:

| Define | Default |
| --- | --- |
| `KUCHIE_PROJECT_URL` | `https://github.com/kuchie-app/Kuchie` |
| `KUCHIE_RELEASES_URL` | `https://github.com/kuchie-app/Kuchie/releases` |
| `KUCHIE_RELEASE_API_URL` | `https://api.github.com/repos/kuchie-app/Kuchie/releases/latest` |
| `KUCHIE_PRIVACY_URL`, `KUCHIE_TRANSLATIONS_URL` | not set (the links are hidden) |

The update check reads GitHub's `tag_name` (`vX.Y.Z`) and `html_url` fields.

## Project layout

| Path | Responsibility |
| --- | --- |
| `lib/src/features/` | Account, Library, Reader, Browse, Downloads, Local Collection, Tracking and Settings. Feature data access and UI live in their respective folders. |
| `lib/src/graphql/` and `lib/src/routes/` | Shared server schema and app navigation. Generated Dart code is rebuilt by `tool/bootstrap`. |
| `lib/src/widgets/` | Shared UI and native platform-view adapters. |
| `ios/Runner/`, `ios/Shared/`, `ios/DownloadLiveActivity/` | iOS bridges, shared ActivityKit types and the widget extension. |
| `ios/MihonRuntime/` | Build and embedding scripts for the optional Local APK runtime. |
| `assets/kuchie/`, `assets/icons/`, `ios/Runner/Assets.xcassets/` | Kiri scenes, in-app artwork and Home Screen icons. |
| `design/kiri/` and `design/icons/` | Editable animation and icon sources. |
| `test/`, `ios/ReaderGestureTests/`, `tool/qa/` | Dart tests, Reader touch tests and disposable QA fixtures. |
| `docs/` | User and developer documentation. |

Data, domain and controller code must not import `presentation/`; `test/architecture/layer_boundaries_test.dart` enforces this. Providers that data code reads, such as the server address, port, credentials and timeouts, live in `lib/src/features/settings/data/server_connection/`. Startup preference upgrades are listed in order in `lib/src/features/settings/data/preference_migrations.dart`.

## Testing

```sh
flutter analyze
flutter test
```

QA fixtures that need no personal accounts:

- **Server**: `python3 tool/qa/server.py --jar /path/to/Suwayomi-Server.jar`, then connect the simulator to `http://127.0.0.1:14567`.
- **Local**: `python3 tool/qa/local_source.py`, then add `http://127.0.0.1:14568/index.json` as an extension store ([details](docs/local-extensions.md#try-the-sample)).
- **APK extensions in the simulator**: `tool/qa/run_simulator_local.sh` starts the extension runtime on the Mac and launches the app connected to it.
- **Reader gestures**: see [Reader XCUITest](ios/ReaderGestureTests/README.md).

## Continuous integration and releases

- [`ci.yml`](.github/workflows/ci.yml) runs code generation, `flutter analyze` and `flutter test` on Linux, and builds the app for the simulator and for iPhone (release, unsigned) on macOS, for every push to `main` and every pull request.
- [`release.yml`](.github/workflows/release.yml) runs when a `v*` tag is pushed. It checks that the tag matches `pubspec.yaml`, builds an unsigned IPA, and attaches it with its SHA-256 to the GitHub release.

To cut a release, bump `version:` in `pubspec.yaml`, merge to `main`, then:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

## Known limitations

- **Mihon APK extensions** run in an embedded JVM, not on Android. Kuchie was tested against 80 public stores and 211 random extensions, with Suwayomi-Server as a reference: every failure left is one the extension, its site or its store has elsewhere too (dead sites, corrupt APKs, extensions built for Mihon forks). See the [compatibility report](docs/extension-compatibility.md).
- Some extensions apply a changed setting only after Kuchie restarts, as in Mihon.
- Android and web launch projects can be added to the shared Flutter source later; the checked-in target is iOS.

## Contributing

Issues and pull requests are welcome. Run `flutter analyze` and `flutter test` before opening a pull request; CI runs the same checks plus the iOS builds.

## Credits

Kuchie stands on the work of these projects and their contributors:

- [Suwayomi-Tsumiru](https://github.com/Suwayomi/Suwayomi-Tsumiru): the Flutter client Kuchie is based on (MPL-2.0), and [Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), which powers the Server collection.
- [Mihon](https://github.com/mihonapp/mihon) and the Tachiyomi community: the extension store formats, the extension API and the signing-key trust model Kuchie follows.
- [Keiyoushi](https://github.com/keiyoushi/extensions), [Yūzōnō](https://github.com/yuzono) and the other extension store maintainers.
- [M-Extension-Server](https://github.com/kodjodevf/M-Extension-Server) by kodjodevf and [1Selxo's iOS runtime fork](https://github.com/1Selxo/M-Extension-Server), which Kuchie embeds with the patches in `ios/MihonRuntime/patches/`.
- [Mangayomi](https://github.com/kodjodevf/mangayomi): Kuchie's remote WebView bridge for Cloudflare challenges is adapted from Mangayomi's (Apache-2.0).
- [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview) for the headless WebViews.
- [OpenJDK](https://openjdk.org) (Zero interpreter) for the on-device extension runtime.
- [Flutter](https://flutter.dev) and the open-source packages listed in [`pubspec.yaml`](pubspec.yaml).
- The translators of Suwayomi-Tsumiru and Kuchie; their notices are in [`assets/licenses/`](assets/licenses/).
- Kiri, the Kuchie mark and the app icons from the Kuchie design work in [`design/`](design/).

## License

Kuchie is licensed under the [Mozilla Public License 2.0](LICENSE). See [NOTICE](NOTICE.md) for source and asset attribution, and the third-party licenses in [`assets/licenses/`](assets/licenses/), [`third_party/`](third_party/) and [`ios/MihonRuntime/THIRD_PARTY_NOTICES.md`](ios/MihonRuntime/THIRD_PARTY_NOTICES.md).
