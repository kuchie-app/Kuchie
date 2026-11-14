// Copyright (c) 2026 Contributors to the Suwayomi project
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import XCTest

final class AppIconUITests: XCTestCase {
    func testAlternateAppIconAndFilesPicker() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.activate()
        let iconSettings = app.descendants(matching: .any)
            .matching(identifier: "kuchie.app-icon.settings").firstMatch
        if !iconSettings.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(iconSettings.waitForExistence(timeout: 8), "Open More → Appearance before running.")
        iconSettings.tap()

        func option(_ name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: "kuchie.app-icon.\(name)").firstMatch
        }
        let primary = option("kiri")
        let alternate = option("panelKiri")
        XCTAssertTrue(alternate.waitForExistence(timeout: 8))
        let choices = [primary, alternate, option("capKertas"), option("syalPenanda"), option("openFrame")]
        let original = try XCTUnwrap(choices.first { $0.exists && $0.isSelected })
        let target = primary.isSelected ? alternate : primary

        target.tap()
        dismissIconConfirmation(in: app)
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: target
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
        let chosenIcon = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        chosenIcon.name = "Kuchie selected app icon"
        chosenIcon.lifetime = .keepAlways
        add(chosenIcon)

        original.tap()
        dismissIconConfirmation(in: app)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: original
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 8), .completed)

        let chooseFile = app.descendants(matching: .any)
            .matching(identifier: "kuchie.app-icon.choose-file").firstMatch
        if !chooseFile.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(chooseFile.isHittable)
        chooseFile.tap()
        let chooseImageButton = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Choose image", "Pilih gambar"])
        ).firstMatch
        let busy = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"), object: chooseImageButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [busy], timeout: 5), .completed)
        // Files is rendered by an iOS remote view service outside Kuchie's tree.
        let filesPicker = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        filesPicker.name = "Kuchie Files picker"
        filesPicker.lifetime = .keepAlways
        add(filesPicker)
    }

    private func dismissIconConfirmation(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for candidate in [app, springboard] {
            let ok = candidate.buttons["OK"].firstMatch
            if ok.waitForExistence(timeout: 2) && ok.isHittable {
                ok.tap()
                return
            }
        }
        // UIKit's icon confirmation can be outside both accessibility trees on iOS 26.
        // Its centered OK button falls here on the portrait iPhone 17 Pro fixture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.578)).tap()
    }
}

final class ReaderSliderUITests: XCTestCase {
    private let bundleIdentifier = "app.kuchie.reader"
    private let sliderIdentifier = "kuchie.reader.page-slider"
    private let firstPage = 7
    private let secondPage = 13
    private let pageCount = 18

    func testDragSliderThumb() throws {
        let reached = try dragSliderThumb(verifyCommittedPage: true)
        let expected = [secondPage, firstPage, secondPage, firstPage, secondPage, firstPage]
        XCTAssertEqual(reached, expected.map(Optional.some), "Actual pages after the six thumb drags: \(reached)")
    }

    func testRecordSliderThumbBaseline() throws {
        let reached = try dragSliderThumb(resetFailedStart: true)
        XCTAssertEqual(reached.count, 6)
    }

    func testSaveChapterOnDevice() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.activate()
        let chapter = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Chapter 03")).firstMatch
        let save = app.buttons["Save to device"].firstMatch
        if !save.waitForExistence(timeout: 4) { app.swipeUp() }
        if save.waitForExistence(timeout: 4) {
            save.tap()
        } else {
            XCTAssertTrue(chapter.waitForExistence(timeout: 5), "Open QA - Lantern Station before running.")
            chapter.press(forDuration: 0.65)
            app.buttons["Keep offline"].firstMatch.tap()
        }
        let saved = app.buttons["Remove from device"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 20), "The chapter should finish saving to the device.")
    }

    func testFinishedMarker() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.activate()
        let slider = app.sliders[sliderIdentifier]
        let toggleControls = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        if !slider.waitForExistence(timeout: 2) {
            toggleControls.tap()
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "Open the 18-page Webtoon chapter before running.")

        if slider.value as? String != "\(pageCount) / \(pageCount)" {
            // Move away from the final thumb first so a track tap cannot land inside it.
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.37, dy: 0.5)).tap()
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            let last = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "\(pageCount) / \(pageCount)"),
                object: slider
            )
            XCTAssertEqual(XCTWaiter.wait(for: [last], timeout: 5), .completed)
        }
        toggleControls.tap()

        // Flutter may merge the marker, chapter name and terminal note into one label.
        let englishMarker = NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                         "Finished", "Chapter completed")
        let marker = app.descendants(matching: .any).matching(englishMarker).firstMatch
        let lowerContent = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let upperContent = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.29))
        for _ in 0..<12 {
            if marker.exists { break }
            lowerContent.press(forDuration: 0.04, thenDragTo: upperContent,
                               withVelocity: .fast, thenHoldForDuration: 0)
        }
        XCTAssertTrue(marker.exists, "The end of the final page must show the finished marker.")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Webtoon finished marker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func dragSliderThumb(resetFailedStart: Bool = false, verifyCommittedPage: Bool = false) throws -> [Int?] {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.activate()
        let slider = app.sliders[sliderIdentifier]
        let showControls = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
        for _ in 0..<3 where !slider.waitForExistence(timeout: 2) { showControls.tap() }
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "Open the 18-page Webtoon chapter before running.")

        let frame = slider.frame
        print("READER_SLIDER_FRAME \(frame) app=\(app.frame)")
        XCTAssertEqual(app.frame.width, 402, accuracy: 1,
                       "The measured points are calibrated for a portrait iPhone 17 Pro.")
        func reportedPage() -> Int? {
            guard let value = slider.value as? String else { return nil }
            let parts = value.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, Int(parts[1]) == pageCount else { return nil }
            return Int(parts[0])
        }

        let screenOrigin = app.coordinate(withNormalizedOffset: .zero)
        func coordinate(atX x: CGFloat) -> XCUICoordinate {
            screenOrigin.withOffset(CGVector(dx: x, dy: frame.midY - app.frame.minY))
        }

        // Use the rendered endpoints: the AX frame can shift independently of the UISlider track.
        func thumbX() throws -> CGFloat {
            let image = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
            let scale = CGFloat(image.width) / app.frame.width
            let width = image.width
            let y = Int((frame.midY - app.frame.minY) * scale)
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: y, width: width, height: 1)))
            var rgba = [UInt8](repeating: 0, count: width * 4)
            let ctx = try XCTUnwrap(CGContext(data: &rgba, width: width, height: 1,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: 1))
            let white = (Int(95 * scale)..<Int(307 * scale)).filter { x in
                rgba[x * 4] >= 248 && rgba[x * 4 + 1] >= 248 && rgba[x * 4 + 2] >= 248
            }
            let runs = white.reduce(into: [[Int]]()) { runs, x in
                if let last = runs.last?.last, last + 1 == x {
                    runs[runs.count - 1].append(x)
                } else {
                    runs.append([x])
                }
            }
            let thumb = try XCTUnwrap(runs.max(by: { $0.count < $1.count }))
            XCTAssertGreaterThan(thumb.count, Int(16 * scale))
            return CGFloat(thumb.first! + thumb.last!) / (2 * scale)
        }

        coordinate(atX: 264).tap()
        let rightPage = try XCTUnwrap(reportedPage())
        let rightX = try thumbX()
        coordinate(atX: 133).tap()
        let leftPage = try XCTUnwrap(reportedPage())
        let leftX = try thumbX()
        // Interior pages avoid boundary correction when the first/last image is short.
        XCTAssertGreaterThan(abs(rightPage - leftPage), 8)
        XCTAssertGreaterThan(rightX - leftX, 70)
        let step = (rightX - leftX) / CGFloat(rightPage - leftPage)
        print("READER_PAINTED_TRACK p\(leftPage)=\(leftX) p\(rightPage)=\(rightX) step=\(step)")
        func x(at page: Int) -> CGFloat {
            leftX + CGFloat(page - leftPage) * step
        }
        func coordinate(at page: Int) -> XCUICoordinate {
            coordinate(atX: x(at: page))
        }
        func drag(from page: Int, to target: Int) {
            // Keep the delivered endpoint inside the target page's rounding interval.
            // iOS can quantize the synthesized motion a few points toward its origin.
            let travel = x(at: target) - x(at: page)
            let endpoint = x(at: target) + (step > 0 ? (travel > 0 ? 0.4 : -0.4) * step : 0)
            coordinate(at: page).press(
                forDuration: 0.16,
                thenDragTo: coordinate(atX: endpoint),
                withVelocity: XCUIGestureVelocity(rawValue: 140), thenHoldForDuration: 0.12)
        }

        func prepare(_ page: Int) {
            for offset in [CGFloat.zero, 0.4, -0.4, 0.8, -0.8] {
                let current = reportedPage()
                guard current != page else { return }
                // The native control ignores taps inside the current thumb.
                if let current, abs(current - page) < 4 {
                    coordinate(at: page < 10 ? 17 : 2).tap()
                }
                coordinate(atX: x(at: page) + offset * step).tap()
            }
            XCTAssertEqual(reportedPage(), page, "Could not prepare page \(page) before a drag.")
        }
        prepare(firstPage)

        var reached: [Int?] = []
        for index in 0..<6 {
            if resetFailedStart {
                // A missed target must not change the distance of the next measured drag.
                prepare(index.isMultiple(of: 2) ? firstPage : secondPage)
            }
            let current = try XCTUnwrap(reportedPage())
            let target = current == secondPage ? firstPage : secondPage
            let began = ProcessInfo.processInfo.systemUptime
            let wallBegan = Date().timeIntervalSince1970
            drag(from: current, to: target)
            let ended = ProcessInfo.processInfo.systemUptime
            let wallEnded = Date().timeIntervalSince1970
            let actual = reportedPage()
            reached.append(actual)
            print("READER_DRAG \(index + 1) \(current) \(target) \(began) \(ended) actual=\(actual.map(String.init) ?? "unknown") wall=\(wallBegan)–\(wallEnded)")
        }

        if verifyCommittedPage && reached.last == firstPage {
            drag(from: firstPage, to: secondPage)
            XCTAssertEqual(reportedPage(), secondPage)
            let toggleControls = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            toggleControls.tap()
            let committedPage = app.staticTexts["\(secondPage) / \(pageCount)"]
            XCTAssertTrue(committedPage.waitForExistence(timeout: 5),
                          "Reader content must commit the page displayed by the native slider.")
            toggleControls.tap()
        }
        return reached
    }
}

final class LocalCollectionUITests: XCTestCase {
    func testSourceReaderChapterNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let library = element(app, ["Collection mode"])
        if library.waitForExistence(timeout: 6) {
            try tap(app, ["Collection mode"])
            try tap(app, ["Local"])
        }
        try tap(app, ["Browse"])
        try tap(app, ["Sources"])
        try tap(app, ["QA Lantern Source"], includeDetails: true)
        let measureOnly = ProcessInfo.processInfo.environment["KUCHIE_QA_READER_MEASURE_ONLY"] == "1"
        try tap(app, [measureOnly ? "QA Reader Benchmark" : "QA Paper Signal"], includeDetails: true)
        if !measureOnly {
            let addToLibrary = element(app, ["Add to library"])
            if addToLibrary.waitForExistence(timeout: 3), addToLibrary.isHittable {
                addToLibrary.tap()
            }
            XCTAssertTrue(element(app, ["In library"]).waitForExistence(timeout: 8), app.debugDescription)
        }
        attach(app, named: "Local manga details")
        try tap(app, ["Chapter 02"], includeDetails: true)
        let openStarted = ProcessInfo.processInfo.systemUptime
        let slider = app.sliders["kuchie.reader.page-slider"]
        let pageActions = element(app, ["1 / 18"])
        let reader = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            slider.exists || pageActions.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reader], timeout: 45), .completed, app.debugDescription)
        print("LOCAL_READER_OPEN_SECONDS \(ProcessInfo.processInfo.systemUptime - openStarted)")
        if !slider.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 12), app.debugDescription)
        if !measureOnly {
            let picker = app.buttons["kuchie.toolbar.reader-chapter-picker"].firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 6), app.debugDescription)
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: picker
            )
            if XCTWaiter.wait(for: [ready], timeout: 3) == .completed {
                picker.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.105)).tap()
            }
            let otherChapter = element(app, ["Chapter 01"], includeDetails: true)
            XCTAssertTrue(otherChapter.waitForExistence(timeout: 8), app.debugDescription)
            attach(app, named: "Local reader chapter picker")
            try tap(app, ["Chapter 01"], includeDetails: true)
            let title = app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "kuchie.toolbar.reader-chapter-picker", "Chapter 01"
            )).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 25), app.debugDescription)
        }
        let first = slider.value as? String
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
        let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
        thumb.press(forDuration: 0.16, thenDragTo: middle,
                    withVelocity: XCUIGestureVelocity(rawValue: 140), thenHoldForDuration: 0.12)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", first ?? ""), object: slider)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        attach(app, named: "Local reader after chapter change and thumb drag")
    }

    func testInstallSourceDownloadAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let repository = ProcessInfo.processInfo.environment["KUCHIE_QA_REPOSITORY_URL"]
            ?? "http://127.0.0.1:14568/index.json"
        app.launch()

        if element(app, ["How would you like to read?", "Bagaimana Anda ingin membaca?"]).waitForExistence(timeout: 10) {
            attach(app, named: "Welcome")
            try tap(app, ["Local", "Lokal"], includeDetails: true)
            try tap(app, ["Start reading", "Mulai membaca"])
        } else if element(app, ["Collection mode", "Mode koleksi"]).exists {
            try tap(app, ["Collection mode", "Mode koleksi"])
            try tap(app, ["Local", "Lokal"])
        }
        XCTAssertTrue(element(app, ["Your local library is empty", "Perpustakaan lokal masih kosong"]).waitForExistence(timeout: 12))
        attach(app, named: "Clean Local Library")
        try tap(app, ["Add a source", "Tambah sumber"])
        try addRepository(repository, app: app)
        try tap(app, ["Install", "Pasang"])
        XCTAssertTrue(element(app, ["Install extension?", "Pasang ekstensi?"])
            .waitForExistence(timeout: 8))
        try tap(app, ["OK", "Ok"])

        XCTAssertTrue(element(app, ["Installed", "Terpasang"]).waitForExistence(timeout: 12),
                      "The source should be installed before changing tabs.")
        attach(app, named: "Local Extensions")
        try tap(app, ["Sources", "Sumber"])
        try tap(app, ["QA Lantern Source"], includeDetails: true)
        attach(app, named: "Source Catalog")
        try tap(app, ["QA Lantern Station"], includeDetails: true)

        let save = element(app, ["Save to device", "Simpan ke perangkat"])
        XCTAssertTrue(save.waitForExistence(timeout: 12), "The chapter list should have download controls.")
        save.tap()
        attach(app, named: "Local chapter transfer")

        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                        "Saved to device", "Tersimpan di perangkat")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 60), "The chapter should finish saving to the device.")
        try tap(app, ["Chapter 01"], includeDetails: true)
        verifyReader(app, screenshotName: "Local chapter reader")

        app.terminate()
        app.launch()
        if !element(app, ["QA Lantern Station"], includeDetails: true).waitForExistence(timeout: 4) {
            try tap(app, ["Library", "Perpustakaan"])
        }
        try tap(app, ["QA Lantern Station"], includeDetails: true)
        XCTAssertTrue(element(app, ["18 pages", "18 halaman"]).waitForExistence(timeout: 8)
            || element(app, ["Chapter 01\n18 pages", "Chapter 01\n18 halaman"]).exists,
            "The library should retain the downloaded chapter with 18 pages.")
        attach(app, named: "Saved Chapter")
        try tap(app, ["Chapter 01"], includeDetails: true)
        verifyReader(app, screenshotName: "Saved chapter after relaunch")
    }

    func testKeiyoushiShinigamiOnDevice() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["KUCHIE_QA_KEIYOUSHI"] == "1" else {
            throw XCTSkip("Enable to test the live Keiyoushi catalog on a QA simulator.")
        }
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Collection mode"].firstMatch.waitForExistence(timeout: 15))
        attach(app, named: "Server Library with cloud mode icon")
        for _ in 0..<3 {
            try tap(app, ["Collection mode"])
            if element(app, ["Local"], includeDetails: true).waitForExistence(timeout: 2) {
                break
            }
        }
        try tap(app, ["Local"], includeDetails: true)
        let mode = app.buttons["Collection mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        attach(app, named: "Local Library with device mode icon")
        let browse = app.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            browse.tap()
            if element(app, ["Sources"]).waitForExistence(timeout: 2) { break }
        }
        let readerOnly = ProcessInfo.processInfo.environment["KUCHIE_QA_SHINIGAMI_READER"] == "1"
        if !readerOnly {
            try tap(app, ["Extensions"])
            let package = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Shinigami\n")
            ).firstMatch
            if !package.waitForExistence(timeout: 3) {
                try addRepository("https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json", app: app)
            }
            XCTAssertTrue(package.waitForExistence(timeout: 12), app.debugDescription)
            let installButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Install"))
            if let install = installButtons.allElementsBoundByIndex.first(where: { $0.identifier.isEmpty && $0.isHittable }) {
                install.tap()
                try tap(app, ["OK", "Ok"])
                XCTAssertTrue(app.buttons["Uninstall"].firstMatch.waitForExistence(timeout: 12))
                XCTAssertFalse(app.staticTexts["Could not complete the action. Try again."].exists)
            }
            XCTAssertTrue(element(app, ["Installed"]).waitForExistence(timeout: 12))
            attach(app, named: "Local Keiyoushi installed Shinigami")
            try tap(app, ["Sources"])
        }
        try tap(app, ["Shinigami"], includeDetails: true)
        attach(app, named: "Shinigami Local source catalog")
        if readerOnly {
            try tap(app, ["Latest"])
            let savedResults = element(app, ["Showing saved results"])
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Retry")).firstMatch.exists ||
                savedResults.exists
            }, object: nil)
            _ = XCTWaiter.wait(for: [settled], timeout: 4)
            attach(app, named: "Shinigami Latest")
        }
        try tap(app, ["kuchie.toolbar.search-source", "Search"])
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("The Villain Wants to Live\n")
        try tap(app, ["The Villain Wants To Live"], includeDetails: true)
        if readerOnly {
            let firstChapter = app.buttons.matching(NSPredicate(
                format: "label == %@ OR label BEGINSWITH %@", "Chapter 1", "Chapter 1\n"
            )).firstMatch
            let start = app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Start Chapter 1"
            )).firstMatch
            let savedChapter = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Saved to device")).firstMatch
            let available = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                start.exists || savedChapter.exists || firstChapter.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 18), .completed, app.debugDescription)
            attach(app, named: "The Villain Wants To Live details")
            let chapter = [savedChapter, start, firstChapter].first(where: \.isHittable)
            let entry = try XCTUnwrap(chapter, app.debugDescription)
            entry.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
            let picker = app.buttons["kuchie.toolbar.reader-chapter-picker"].firstMatch
            if !picker.waitForExistence(timeout: 4) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
            }
            XCTAssertTrue(picker.waitForExistence(timeout: 20), app.debugDescription)
            picker.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
            let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Chapter "))
            let selected = rows.matching(NSPredicate(format: "selected == true")).firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 12), app.debugDescription)
            let selectedLabel = selected.label.components(separatedBy: "\n")[0]
            let otherChapter = try XCTUnwrap(rows.allElementsBoundByIndex.last {
                !$0.isSelected && !$0.frame.isEmpty && $0.isHittable
            }, app.debugDescription)
            let otherLabel = otherChapter.label.components(separatedBy: "\n")[0]
            XCTAssertNotEqual(otherLabel, selectedLabel)
            attach(app, named: "Shinigami reader chapter picker")
            otherChapter.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "kuchie.toolbar.reader-chapter-picker", otherLabel
            )).firstMatch.waitForExistence(timeout: 32), app.debugDescription)
            let slider = app.sliders["kuchie.reader.page-slider"]
            XCTAssertTrue(slider.waitForExistence(timeout: 20), app.debugDescription)
            let before = try XCTUnwrap(slider.value as? String)
            let pages = before.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(pages.count, 2)
            let current = try XCTUnwrap(Int(pages[0]))
            let total = try XCTUnwrap(Int(pages[1]))
            XCTAssertGreaterThan(total, 1)
            let progress = CGFloat(current - 1) / CGFloat(total - 1)
            let thumb = slider.coordinate(withNormalizedOffset: .init(dx: 0.12 + 0.76 * progress, dy: 0.5))
            let target = slider.coordinate(withNormalizedOffset: .init(dx: current <= total / 2 ? 0.55 : 0.26, dy: 0.5))
            thumb.press(forDuration: 0.16, thenDragTo: target,
                        withVelocity: XCUIGestureVelocity(rawValue: 140), thenHoldForDuration: 0.12)
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: slider)
            XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
            print("SHINIGAMI_READER \(selectedLabel) -> \(otherLabel) thumb \(before) -> \(slider.value ?? "unavailable")")
            attach(app, named: "Shinigami reader after chapter switch and thumb drag")
            return
        }
        let saved = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Saved to device")
        ).firstMatch
        if !saved.waitForExistence(timeout: 3) {
            let save = element(app, ["Save to device"])
            XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
            save.tap()
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 90), app.debugDescription)
        attach(app, named: "Shinigami chapter saved on device")
        saved.tap()
        let slider = app.sliders["kuchie.reader.page-slider"]
        if !slider.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 12))
        attach(app, named: "Shinigami Local Reader")
    }

    func testInstallMihonRuntimeExtension() throws {
        continueAfterFailure = false
        let configuration = ProcessInfo.processInfo.environment
        guard let port = configuration["KUCHIE_QA_EXTENSION_RUNTIME_PORT"],
              let token = configuration["KUCHIE_QA_EXTENSION_RUNTIME_TOKEN"],
              let extensionName = configuration["KUCHIE_QA_MIHON_EXTENSION"],
              let sourceName = configuration["KUCHIE_QA_MIHON_SOURCE"] else {
            throw XCTSkip("Start the QA extension runtime and set the test source.")
        }
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["KUCHIE_QA_EXTENSION_RUNTIME_PORT"] = port
        app.launchEnvironment["KUCHIE_QA_EXTENSION_RUNTIME_TOKEN"] = token
        app.launch()
        let welcome = element(app, ["How would you like to read?"])
        if welcome.waitForExistence(timeout: 4) {
            try tap(app, ["Local"], includeDetails: true)
            try tap(app, ["Start reading"])
        }
        try tap(app, ["Browse"])
        try tap(app, ["Extensions"])
        let search = app.textFields["Search for extensions"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        if configuration["KUCHIE_QA_MIHON_ADD_REPO"] == "1" {
            try addRepository("https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.json", app: app)
        }
        search.tap()
        search.typeText(extensionName + "\n")
        let package = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH[c] %@", extensionName + "\n"
        )).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 25), app.debugDescription)
        attach(app, named: "Non-Shinigami extension offered in Keiyoushi")
        if !app.buttons["Uninstall"].firstMatch.exists {
            let install = app.buttons.matching(NSPredicate(
                format: "label == %@ AND identifier != %@", "Install", "kuchie.toolbar.install-extension"
            )).firstMatch
            XCTAssertTrue(install.waitForExistence(timeout: 10), app.debugDescription)
            install.tap()
            try tap(app, ["OK", "Ok"])
        }
        XCTAssertTrue(app.buttons["Uninstall"].firstMatch.waitForExistence(timeout: 60), app.debugDescription)
        package.tap()
        XCTAssertTrue(app.staticTexts["Extension info"].firstMatch.waitForExistence(timeout: 12), app.debugDescription)
        attach(app, named: "Installed runtime extension details")
        let sourceLabel = configuration["KUCHIE_QA_MIHON_LANGUAGE"]
            .map { sourceName + "\n" + $0 } ?? sourceName
        let sourceRow = element(app, [sourceLabel], includeDetails: true)
        for _ in 0..<8 where !sourceRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(sourceRow.isHittable, app.debugDescription)
        // The whole accessibility row overlaps the Latest and Disable buttons.
        sourceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5)).tap()
        let sourceSearch = app.buttons["kuchie.toolbar.search-source"].firstMatch
        XCTAssertTrue(sourceSearch.waitForExistence(timeout: 18), app.debugDescription)
        if let manga = configuration["KUCHIE_QA_MIHON_MANGA"] {
            sourceSearch.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
            field.tap()
            field.typeText(manga + "\n")
            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", manga)).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 25), app.debugDescription)
            attach(app, named: "Live manga results from the runtime")
            if configuration["KUCHIE_QA_MIHON_SEARCH_ONLY"] == "1" {
                return
            }
            result.tap()
            let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Saved to device")).firstMatch
            if !saved.waitForExistence(timeout: 2) {
                let saves = app.buttons.matching(NSPredicate(format: "label == %@", "Save to device"))
                XCTAssertTrue(saves.firstMatch.waitForExistence(timeout: 25), app.debugDescription)
                for _ in 0..<4 where !saves.allElementsBoundByIndex.contains(where: \.isHittable) {
                    app.swipeUp()
                }
                let visibleSave = try XCTUnwrap(saves.allElementsBoundByIndex.first(where: \.isHittable))
                visibleSave.tap()
                XCTAssertTrue(saved.waitForExistence(timeout: 150), app.debugDescription)
            }
            attach(app, named: "Runtime chapter saved locally")
            saved.tap()
            let slider = app.sliders["kuchie.reader.page-slider"]
            if !slider.waitForExistence(timeout: 3) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
            }
            XCTAssertTrue(slider.waitForExistence(timeout: 12), app.debugDescription)
            attach(app, named: "Runtime chapter in Local Reader")
        } else {
            attach(app, named: "Installed runtime source")
        }
    }

    private func addRepository(_ url: String, app: XCUIApplication) throws {
        try tap(app, ["kuchie.toolbar.extension-stores", "Extension stores"])
        try tap(app, ["kuchie.toolbar.add-extension-store", "Add extension store"])
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "The repository URL field should open.")
        field.tap()
        field.typeText(url)
        XCTAssertEqual(field.value as? String, url)
        try tap(app, ["Add", "Tambah"])
        XCTAssertTrue(field.waitForNonExistence(timeout: 18), app.debugDescription)
        try tap(app, ["Back", "Kembali"])
    }

    func testReadSavedChapterWithSourceOffline() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        if element(app, ["Collection mode", "Mode koleksi"]).exists {
            try tap(app, ["Collection mode", "Mode koleksi"])
            try tap(app, ["Local", "Lokal"])
        }
        try tap(app, ["History", "Riwayat"])
        XCTAssertTrue(element(app, ["QA Lantern Station"], includeDetails: true)
            .waitForExistence(timeout: 12))
        attach(app, named: "Local History")
        try tap(app, ["QA Lantern Station"], includeDetails: true)
        let slider = app.sliders["kuchie.reader.page-slider"]
        if !slider.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 12), app.debugDescription)
        let before = try XCTUnwrap(slider.value as? String)
        let parts = before.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(parts.last, "18")
        let currentPage = try XCTUnwrap(Int(parts.first ?? ""))
        let progress = CGFloat(currentPage - 1) / 17
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.88 - 0.76 * progress, dy: 0.5))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: currentPage < 9 ? 0.42 : 0.74, dy: 0.5))
        start.press(forDuration: 0.16, thenDragTo: end,
                    withVelocity: XCUIGestureVelocity(rawValue: 140), thenHoldForDuration: 0.12)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: slider)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed)
        attach(app, named: "Offline Reader after thumb drag")

        let readerBack = app.buttons["kuchie.toolbar.reader-back"].firstMatch
        XCTAssertTrue(readerBack.waitForExistence(timeout: 8), app.debugDescription)
        readerBack.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let updates = app.tabBars.buttons["Updates"].firstMatch
        XCTAssertTrue(updates.waitForExistence(timeout: 12), app.debugDescription)
        updates.tap()
        attach(app, named: "Local Updates")
        let more = app.tabBars.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        attach(app, named: "Local More")
        try tap(app, ["Downloads", "Unduhan"])
        try tap(app, ["On device", "Di perangkat"])
        XCTAssertTrue(element(app, ["QA Lantern Station"], includeDetails: true).waitForExistence(timeout: 12))
        attach(app, named: "Local Downloads")
    }

    func testLocalActivityOnHomeScreen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if element(app, ["Collection mode", "Mode koleksi"]).exists {
            try tap(app, ["Collection mode", "Mode koleksi"])
            try tap(app, ["Local", "Lokal"])
        }
        try tap(app, ["Browse", "Jelajahi"])
        try tap(app, ["QA Lantern Source"], includeDetails: true)
        try tap(app, ["QA Night Ferry"], includeDetails: true)
        let nextChapter = element(app, ["Chapter 01"], includeDetails: true)
        XCTAssertTrue(nextChapter.waitForExistence(timeout: 12))
        let save = app.buttons["Save to device"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 12))
        save.tap()
        let progress = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                        "Chapter 01", "/ 18")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 5))
        // SpringBoard is foreground before the application closing animation ends.
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: springboard.icons["Kuchie"].firstMatch
        )
        _ = XCTWaiter.wait(for: [settled], timeout: 3)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.038))
            .press(forDuration: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Local Live Activity on Home Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.activate()
        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                        "Chapter 01", "Saved to device")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 60))
    }

    private func labelPredicate(_ labels: [String], includeDetails: Bool) -> NSPredicate {
        let exact = NSPredicate(format: "label IN %@ OR identifier IN %@", labels, labels)
        guard includeDetails else { return exact }
        return NSCompoundPredicate(orPredicateWithSubpredicates: [exact] + labels.map {
            NSPredicate(format: "label BEGINSWITH %@", $0 + "\n")
        })
    }

    private func element(
        _ app: XCUIApplication, _ labels: [String], includeDetails: Bool = false
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(labelPredicate(labels, includeDetails: includeDetails)).firstMatch
    }

    private func tap(
        _ app: XCUIApplication, _ labels: [String], includeDetails: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let predicate = labelPredicate(labels, includeDetails: includeDetails)
        let match = app.descendants(matching: .any).matching(predicate)
        guard match.firstMatch.waitForExistence(timeout: 12) else {
            XCTFail("Missing action \(labels).\n\(app.debugDescription)", file: file, line: line)
            return
        }

        let candidates = match.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }
        let target = candidates.first(where: { $0.elementType == .button }) ?? candidates.first
        let action = try XCTUnwrap(target, "Action is unavailable: \(labels)", file: file, line: line)
        action.tap()
    }

    private func verifyReader(_ app: XCUIApplication, screenshotName: String) {
        let slider = app.sliders["kuchie.reader.page-slider"]
        if !slider.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).tap()
        }
        XCTAssertTrue(slider.waitForExistence(timeout: 12), "The local reader should use the native page slider.")
        XCTAssertEqual(slider.value as? String, "1 / 18")
        attach(app, named: screenshotName)
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class CollectionModeServerUITests: XCTestCase {
    func testExtensionBrowseInBothModes() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        try tap(app, "Library")
        try tap(app, "Collection mode")
        try tap(app, "Local")
        let browse = app.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 12))
        let localExtensions = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Extensions")).firstMatch
        for _ in 0..<2 {
            browse.tap()
            if localExtensions.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(localExtensions.waitForExistence(timeout: 8), app.debugDescription)
        localExtensions.tap()
        let search = app.textFields["Search for extensions"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["kuchie.toolbar.extension-stores"].exists)
        attach(app, "Local Extensions")

        app.terminate()
        app.launch()
        try tap(app, "Library")
        try tap(app, "Collection mode")
        try tap(app, "Server")
        try tap(app, "Browse")
        let serverExtensions = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@", "Extensions", "Extensions ("
        )).firstMatch
        XCTAssertTrue(serverExtensions.waitForExistence(timeout: 15), app.debugDescription)
        serverExtensions.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["kuchie.toolbar.extension-stores"].exists)
        attach(app, "Server Extensions")

        app.terminate()
        app.launch()
        try tap(app, "Library")
        try tap(app, "Collection mode")
        try tap(app, "Local")
    }

    func testConnectServerAndSwitchWithoutLosingShelf() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let server = ProcessInfo.processInfo.environment["KUCHIE_QA_SERVER_URL"]
            ?? "http://127.0.0.1:14567"
        let series = "QA - Lantern Station"
        let serverMode = app.buttons["Collection mode"]
        app.launch()

        if element(app, "How would you like to read?").waitForExistence(timeout: 5) {
            try tap(app, "Local", includeDetails: true)
            try tap(app, "Start reading")
        } else if serverMode.exists {
            try tap(app, "Collection mode")
            try tap(app, "Local")
        }
        try tap(app, "Collection mode")
        try tap(app, "Server")
        if element(app, "Connect your server").waitForExistence(timeout: 4) {
            let address = app.textFields.firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 8))
            if address.value as? String != server {
                let value = address.value as? String ?? ""
                address.tap()
                if !value.isEmpty && !value.contains("http://192.168.0.10:4567") {
                    address.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
                }
                address.typeText(server)
            }
            XCTAssertEqual(address.value as? String, server)
            try tap(app, "Next")
            try tap(app, "Finish", timeout: 30)
            attach(app, "Server after first setup")
        }
        XCTAssertTrue(element(app, "Collection mode").waitForExistence(timeout: 12))
        attach(app, "Server library before changing mode")

        if !element(app, series, includeDetails: true).waitForExistence(timeout: 12) {
            try tap(app, "Browse")
            try tap(app, "Local source", includeDetails: true)
            try tap(app, series, includeDetails: true)
            if element(app, "Add to library").waitForExistence(timeout: 10) {
                try tap(app, "Add to library")
            }
            XCTAssertTrue(element(app, "In library").waitForExistence(timeout: 12))
            try tap(app, "Back")
            try tap(app, "Back")
            try tap(app, "Library")
            XCTAssertTrue(element(app, series, includeDetails: true).waitForExistence(timeout: 12))
        }
        attach(app, "Server shelf with fixture title")

        try tap(app, "Collection mode")
        try tap(app, "Local")
        XCTAssertTrue(element(app, "Collection mode").waitForExistence(timeout: 12))
        XCTAssertFalse(element(app, series, includeDetails: true).exists)
        attach(app, "Independent Local shelf")
        try tap(app, "More")
        XCTAssertTrue(element(app, "Collection mode", includeDetails: true)
            .waitForExistence(timeout: 12), "Local More should expose the mode switch.")
        try tap(app, "Collection mode", includeDetails: true)
        try tap(app, "Local")
        try tap(app, "Library")
        let localMode = app.buttons["Collection mode"].firstMatch
        XCTAssertTrue(localMode.waitForExistence(timeout: 12),
                      "Local Library should show the mode button.")
        localMode.tap()
        try tap(app, "Server")
        XCTAssertFalse(element(app, "Connect your server").exists)
        XCTAssertTrue(serverMode.waitForExistence(timeout: 12),
                      "Switching from Local Library should return to Server Library.")
        XCTAssertTrue(element(app, series, includeDetails: true).waitForExistence(timeout: 12),
                      "The Server shelf should still contain the seeded title.")
        attach(app, "Server shelf resumed")
    }

    private func matches(
        _ app: XCUIApplication, _ label: String, includeDetails: Bool = false
    ) -> XCUIElementQuery {
        let exact = NSPredicate(format: "label == %@", label)
        let predicate = includeDetails
            ? NSCompoundPredicate(orPredicateWithSubpredicates: [
                exact,
                NSPredicate(format: "label BEGINSWITH[c] %@", label + "\n"),
                NSPredicate(format: "label ==[c] %@", label),
            ])
            : exact
        return app.descendants(matching: .any).matching(predicate)
    }

    private func element(
        _ app: XCUIApplication, _ label: String, includeDetails: Bool = false
    ) -> XCUIElement {
        matches(app, label, includeDetails: includeDetails).firstMatch
    }

    private func tap(
        _ app: XCUIApplication, _ label: String, includeDetails: Bool = false,
        timeout: TimeInterval = 12, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let candidates = matches(app, label, includeDetails: includeDetails)
        guard candidates.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("Missing action \(label).\n\(app.debugDescription)", file: file, line: line)
            return
        }
        let hittable = candidates.allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }
        let target = hittable.first { $0.elementType == .button } ?? hittable.first
        let action = try XCTUnwrap(target, "Action is unavailable: \(label)", file: file, line: line)
        action.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class DownloadIslandAppearanceUITests: XCTestCase {
    func testVariantPersistsAcrossRelaunchAndCanRestoreDefault() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        openPicker(in: app)
        let defaultOption = option("wajah-kiri-ring", in: app)
        let panel = option("panel-manga", in: app)
        XCTAssertTrue(defaultOption.waitForExistence(timeout: 8))
        XCTAssertTrue(option("wajah-kiri-persen", in: app).exists)
        XCTAssertTrue(option("syal-penanda", in: app).exists)
        if !panel.isSelected { panel.tap() }
        assertSelected(panel)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Kuchie Dynamic Island appearance picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        openPicker(in: app)
        assertSelected(panel)
        defaultOption.tap()
        assertSelected(defaultOption)
    }

    private func openPicker(in app: XCUIApplication) {
        let more = app.tabBars.buttons.matching(
            NSPredicate(format: "label IN %@", ["More", "Lainnya"])
        ).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15), "Start with an initialized Local or Server collection.")
        more.tap()

        let appearance = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", ["Appearance", "Tampilan"])
        ).firstMatch
        _ = appearance.waitForExistence(timeout: 3)
        if !appearance.isHittable { app.swipeUp() }
        XCTAssertTrue(appearance.waitForExistence(timeout: 8))
        XCTAssertTrue(appearance.isHittable)
        appearance.tap()

        let settings = app.descendants(matching: .any)
            .matching(identifier: "kuchie.island.settings").firstMatch
        for _ in 0..<3 {
            if settings.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        XCTAssertTrue(settings.isHittable)
        settings.tap()
    }

    private func option(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "kuchie.island.\(id)").firstMatch
    }

    private func assertSelected(_ option: XCUIElement) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: option
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 8), .completed)
    }
}

final class KiriMotionSmokeUITests: XCTestCase {
    func testLocalIslandBrandAndDeepLink() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "app.kuchie.reader")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let browse = app.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 15))
        if app.buttons["Collection mode"].exists {
            app.buttons["Collection mode"].tap()
            app.buttons["Local"].tap()
        }
        browse.tap()
        try row(app, startingWith: "QA Lantern Source").tap()
        try row(app, startingWith: "QA Paper Signal").tap()
        let save = app.buttons["Save to device"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        let progress = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "/ 18")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 8))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: springboard.icons["Kuchie"].firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 6), .completed)
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.038))
        capture("Kiri Home Screen and compact Dynamic Island")
        island.press(forDuration: 0.8)
        capture("Kiri Dynamic Island expanded")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.092)).tap()
        let permission = springboard.buttons["Open"].firstMatch
        if permission.waitForExistence(timeout: 2) { permission.tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        let downloads = app.staticTexts["Downloads"].firstMatch
        XCTAssertTrue(downloads.waitForExistence(timeout: 10), app.debugDescription)
        capture("Local downloads via Dynamic Island")
    }

    private func row(_ app: XCUIApplication, startingWith label: String) throws -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), app.debugDescription)
        return row
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
