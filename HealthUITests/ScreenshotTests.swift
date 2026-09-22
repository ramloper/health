import XCTest

/// Captures App Store screenshots against the `--demo` in-memory dataset.
/// Run: scripts/screenshots.sh (exports the attachments to build/screenshots).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
    }

    func testCaptureStoreScreenshots() {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))

        // 1. Today lobby
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        sleep(1)
        snap("01-today")

        // 2. Exercise guide
        let guideCue = app.staticTexts["이렇게"]
        let row = app.buttons["lobby-exercise-0"]
        row.tap()
        if !guideCue.waitForExistence(timeout: 3) {
            // Plain-style buttons occasionally swallow the first synthesized tap; retry by coordinate.
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        }
        XCTAssertTrue(guideCue.waitForExistence(timeout: 5))
        sleep(1)
        snap("02-guide")
        app.buttons["guide-close"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        // 3. Session in progress: tick two sets, dismiss the rest sheet, then shoot
        start.tap()
        let tick = app.buttons["세트 완료로 표시"]
        let done = app.buttons.matching(identifier: "세트 완료됨")
        let skip = app.buttons["휴식 건너뛰기"]
        XCTAssertTrue(tick.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        tapUntil(tick.firstMatch) { done.count >= 1 }
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()
        sleep(1)
        tapUntil(tick.firstMatch) { done.count >= 2 }
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        sleep(1)
        snap("03-rest")
        skip.tap()
        sleep(1)
        snap("04-session")

        // 4. Routines
        tabs.buttons["루틴"].tap()
        XCTAssertTrue(app.staticTexts["프로그램"].waitForExistence(timeout: 5))
        snap("05-routines")

        // 5. History
        tabs.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["PR"].waitForExistence(timeout: 5))
        snap("06-history")

        // 6. Profile
        tabs.buttons["프로필"].tap()
        XCTAssertTrue(app.staticTexts["1RM"].waitForExistence(timeout: 5))
        snap("07-profile")
    }

    /// Plain-style SwiftUI buttons sometimes ignore the first synthesized tap; retry by coordinate.
    private func tapUntil(_ element: XCUIElement, attempts: Int = 3, _ condition: () -> Bool) {
        for i in 0..<attempts {
            if i == 0 { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if condition() { return }
                usleep(200_000)
            }
        }
        let dump = XCTAttachment(string: app.debugDescription)
        dump.name = "hierarchy-at-failure"
        dump.lifetime = .keepAlways
        add(dump)
        snap("99-failure")
        XCTFail("tap did not take effect: \(element)")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
