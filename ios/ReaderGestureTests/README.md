# Reader slider XCUITest

Start Kuchie on a portrait iPhone 17 Pro Simulator running iOS 26. Open an 18-page chapter with the horizontal reader controls visible. Use the same reader mode and chapter for comparisons. The test calibrates the thumb against the rendered track and measures the two directions separately.

From the repository root, use Xcode to build the test bundle.

```sh
xcodebuild build-for-testing \
  -project ios/ReaderGestureTests/ReaderGestureTests.xcodeproj \
  -scheme ReaderSliderUITests \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/kuchie-reader-xctest \
  CODE_SIGNING_ALLOWED=NO
```

Run the assertions on the booted Simulator. Set `READER_SIMULATOR_ID` to its UDID and give each run a distinct result path.

```sh
xcodebuild test-without-building \
  -xctestrun /tmp/kuchie-reader-xctest/Build/Products/ReaderSliderUITests_*.xctestrun \
  -destination "platform=iOS Simulator,id=$READER_SIMULATOR_ID" \
  -parallel-testing-enabled NO \
  -only-testing:ReaderSliderUITests/ReaderSliderUITests/testDragSliderThumb \
  -resultBundlePath /tmp/reader-slider.xcresult
```

The runner activates the installed Kuchie app. It seeks to page 7 during setup if needed, then holds the current thumb and drags it toward the other page six times. `READER_DRAG` log lines include the starting page, target, reported page, and gesture timestamps. For a build that misses the release point, use `testRecordSliderThumbBaseline` to collect all six attempts. That test restores the starting page between measured drags if needed to keep the same drag distance. Collect frame timings separately and report unsuccessful drags alongside the timings.

Run `testFinishedMarker` separately to move to the final page, scroll to the end, and attach a screenshot of the chapter marker to its result bundle. This requires a chapter with no next chapter.

Run `AppIconUITests/testAlternateAppIconAndFilesPicker` with **More → Appearance** open. It switches to a built-in option, restores the previous one, and attaches a screenshot after the Files picker opens. The Shortcuts setup is a separate manual check.

For the on-device download smoke test, open **QA - Lantern Station** from the local QA server with offline downloads enabled, then run `ReaderSliderUITests/testSaveChapterOnDevice`. Use a fresh QA app profile or a chapter that has yet to be saved.

## Local and Server collections

Use a dedicated iPhone Simulator with a clean Kuchie debug installation. Start the [Local extension fixture](../../docs/local-extensions.md) and a disposable Suwayomi server. The Server smoke test defaults to `http://127.0.0.1:14567` and expects **QA - Lantern Station** from `tool/qa/server.py`.

Run the test methods in this order on the same simulator:

1. `LocalCollectionUITests/testInstallSourceDownloadAndReopen` installs the fixture manually, downloads Chapter 01, and reopens it after relaunch.
2. `CollectionModeServerUITests/testConnectServerAndSwitchWithoutLosingShelf` sets up Suwayomi, verifies that the shelves are separate, and returns to the configured Server shelf.
3. Stop the Local fixture. `LocalCollectionUITests/testReadSavedChapterWithSourceOffline` opens the saved chapter from History, drags the native slider, and checks Downloads.
4. Restart the Local fixture with `--delay 0.8`. `LocalCollectionUITests/testLocalActivityOnHomeScreen` downloads Chapter 01 from QA Night Ferry and takes a Home Screen screenshot during transfer.

Use distinct result bundle paths. Confirm the XCTest log shows the expected test count. If an individual method filter executes zero tests, select the class and skip the other methods. Export captures with `xcrun xcresulttool export attachments --path <bundle> --output-path <directory>`.

For a live Keiyoushi test, set `KUCHIE_QA_EXTENSION_RUNTIME_TOKEN` to a random 64-character hex string and `KUCHIE_QA_EXTENSION_RUNTIME_PORT` to a free Mac loopback port. Start `tool/qa/extension_runtime_host.sh` with both variables. Put the same values in `ReaderSliderUITests.EnvironmentVariables` in a private copy of the `.xctestrun` file next to the generated file. Set `KUCHIE_QA_MIHON_EXTENSION` and `KUCHIE_QA_MIHON_SOURCE` to the extension and source labels. For a multilingual package, set `KUCHIE_QA_MIHON_LANGUAGE` to the displayed language. Use `KUCHIE_QA_MIHON_ADD_REPO=1` if the store has yet to be added. Set `KUCHIE_QA_MIHON_MANGA` to exercise search, local download, and opening the chapter in Reader. Set `KUCHIE_QA_MIHON_SEARCH_ONLY=1` to stop after verifying the search result. Run `LocalCollectionUITests/testInstallMihonRuntimeExtension` with the debug app installed on the booted simulator.
