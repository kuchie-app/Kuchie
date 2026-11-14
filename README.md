# Kuchie

Kuchie is an iPhone reader for manga and webtoons with Apple Liquid Glass controls on iOS 26. Choose a collection when you first open the app, then switch collections from Library or More.

- **Local** keeps your library, history and downloads on your iPhone. Import files or install sources from an [extension store you add](docs/local-extensions.md).
- **Server** connects to Suwayomi for your server library, history, download queue and trackers. You can also save chapters to your iPhone for offline reading.

Kuchie shows download progress in Live Activities and Dynamic Island on supported devices.

## Development

Install the Flutter version in `.fvmrc` and Xcode 26 or newer. Select Xcode through `xcode-select` or `DEVELOPER_DIR` and boot an iOS 26 simulator. Flutter resolves the native plugins through Swift Package Manager.

```sh
tool/bootstrap
flutter build ios --simulator --debug --no-codesign
```

Run `flutter run -d <simulator-id>` to start an interactive session. For a physical iPhone, open `ios/Runner.xcworkspace`, pick a signing team for Runner and DownloadLiveActivity, and use bundle IDs registered to that team. The extension uses the app's bundle ID plus `.DownloadLiveActivity`.

### Layout

| Path | Responsibility |
|---|---|
| `lib/src/features/` | Account, Library, Reader, Browse, Downloads, Local Collection, Tracking and Settings. Feature data access and UI live in their respective folders. |
| `lib/src/graphql/` and `lib/src/routes/` | Shared server schema and app navigation. Generated Dart code is rebuilt by `tool/bootstrap`. |
| `lib/src/widgets/` | Shared UI and native platform-view adapters. |
| `ios/Runner/`, `ios/Shared/`, `ios/DownloadLiveActivity/` | iOS bridges, shared ActivityKit types and the widget extension. |
| `ios/MihonRuntime/` | Build and embedding scripts for the optional Local APK runtime. |
| `assets/kuchie/`, `assets/icons/` and `ios/Runner/Assets.xcassets/` | Kiri scenes, in-app artwork and Home Screen icons. |
| `design/kiri/` and `design/icons/` | Editable animation and icon sources. |
| `test/`, `ios/ReaderGestureTests/` and `tool/qa/` | Dart regression tests, Reader touch tests and a disposable QA catalog. |

Android and web launch projects can be added to the shared Flutter source when those platforms are scheduled. The checked-in build target is iOS.

### Home Screen icon

Open **More → Appearance → App icon**. The five included icons switch through UIKit. To use your own image, pick it from Files, preview the square crop, then export it and follow the in-app Shortcuts instructions. The shortcut opens Kuchie and displays your image on the Home Screen. See [Apple's Shortcuts guide](https://support.apple.com/guide/shortcuts/apd735880972/ios).

### Local verification

```sh
flutter analyze
flutter test
```

For the Server collection, start the disposable catalog with `python3 tool/qa/server.py --jar /path/to/Suwayomi-Server.jar` and connect the Simulator to `http://127.0.0.1:14567`. To test Local mode, use the [Local extension fixture](docs/local-extensions.md#try-the-sample). See [Reader XCUITest](ios/ReaderGestureTests/README.md) for the drag and chapter-end scenarios.

### Distribution

A release build can set `KUCHIE_PROJECT_URL`, `KUCHIE_RELEASES_URL`, `KUCHIE_RELEASE_API_URL`, `KUCHIE_PRIVACY_URL`, and `KUCHIE_TRANSLATIONS_URL` using `--dart-define`. The release feed expects GitHub's `tag_name` and `html_url` fields. Until a Kuchie feed is configured, server update checks remain available and the app omits its own release check.

The bundle ID `app.kuchie.reader` has its own settings, credentials and offline files. Add your existing Suwayomi server in Kuchie to access your server-side Library and history again.

See [NOTICE](NOTICE.md) and [LICENSE](LICENSE) for source and asset attribution.
