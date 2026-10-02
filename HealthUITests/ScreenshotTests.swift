import XCTest

/// Captures App Store screenshots against the `--demo` in-memory dataset.
/// Run: scripts/screenshots.sh (exports the attachments to build/screenshots).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.useShopFeed(preferDocs: true)
        app.launch()
    }

    func testCaptureStoreScreenshots() {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))

        // 1. Today lobby
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        sleep(1)
        snap("01-today", app: app)

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
        snap("02-guide", app: app)
        app.buttons["guide-close"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        // 3. Session in progress: tick two sets, dismiss the rest sheet, then shoot
        start.tap()
        let tick = app.buttons["세트 완료로 표시"]
        let done = app.buttons.matching(identifier: "세트 완료됨")
        let skip = app.buttons["휴식 건너뛰기"]
        XCTAssertTrue(tick.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        tapUntil(tick.firstMatch, app: app) { done.count >= 1 }
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()
        sleep(1)
        tapUntil(tick.firstMatch, app: app) { done.count >= 2 }
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        sleep(1)
        snap("03-rest", app: app)
        skip.tap()
        sleep(1)
        snap("04-session", app: app)

        // 4. Routines
        tabs.buttons["루틴"].tap()
        XCTAssertTrue(app.staticTexts["프로그램"].waitForExistence(timeout: 5))
        snap("05-routines", app: app)

        // 5. History
        tabs.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["PR"].waitForExistence(timeout: 5))
        snap("06-history", app: app)

        // 6. Profile
        tabs.buttons["프로필"].tap()
        XCTAssertTrue(app.staticTexts["1RM"].waitForExistence(timeout: 5))
        snap("07-profile", app: app)

        // 7. Shop
        tabs.buttons["쇼핑"].tap()
        let firstCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop-card-'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        sleep(1)
        snap("08-shop", app: app)
    }

    func testFiveThreeOneCompletesMainAndBBBSets() {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["루틴"].tap()
        let program = app.staticTexts["5/3/1 BBB"]
        XCTAssertTrue(program.waitForExistence(timeout: 5))
        program.press(forDuration: 1)
        app.buttons["바로 시작"].tap()
        let benchDay = app.buttons.containing(.staticText, identifier: "벤치").firstMatch
        XCTAssertTrue(benchDay.waitForExistence(timeout: 5))
        benchDay.tap()
        tabs.buttons["오늘"].tap()
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let mainSets = app.buttons["6세트 완료"]
        XCTAssertTrue(mainSets.waitForExistence(timeout: 5))
        mainSets.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            let allow = permission.buttons["Allow"]
            if allow.exists { allow.tap() }
            else if permission.buttons["허용"].exists { permission.buttons["허용"].tap() }
        }
        let skip = app.buttons["휴식 건너뛰기"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["다음 운동 ›"].tap()

        let bbbSets = app.buttons["5세트 완료"]
        XCTAssertTrue(bbbSets.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "세트 완료로 표시").count, 5)
        bbbSets.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        let finish = app.buttons["세션 완료"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        tabs.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["11세트 완료"].waitForExistence(timeout: 5))
    }
}
