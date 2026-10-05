import XCTest

/// Today-only session changes: reorder exercises, jump to one, add an exercise for this session only.
final class SessionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.useShopFeed(preferDocs: false)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    private var planRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan-row-'"))
    }

    /// "<name>, <done>/<count>세트 · …" → name
    private func name(ofRow index: Int) -> String {
        let label = app.buttons["plan-row-\(index)"].label
        return label.components(separatedBy: ", ").first ?? label
    }

    private func openPlan() {
        let open = app.buttons["session-plan-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let close = app.buttons["plan-close"]
        tapUntil(open, app: app) { close.exists }
    }

    private func closePlan() {
        let close = app.buttons["plan-close"]
        tapUntil(close, app: app) { !close.exists }
    }

    private func allowNotificationsIfAsked() {
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            let allow = permission.buttons["Allow"]
            if allow.exists { allow.tap() }
            else if permission.buttons["허용"].exists { permission.buttons["허용"].tap() }
        }
    }

    func testReorderJumpAndAddTodayOnlyExercise() {
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()

        // Reorder: the first exercise moves down, the second takes its place.
        openPlan()
        let count = planRows.count
        XCTAssertGreaterThanOrEqual(count, 3)
        let first = name(ofRow: 0), second = name(ofRow: 1)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(app.buttons["plan-row-0"].label.contains("진행 중"))
        XCTAssertFalse(app.buttons["plan-up-0"].isEnabled)
        let down = app.buttons["plan-down-0"]
        tapUntil(down, app: app) { self.name(ofRow: 0) == second }
        XCTAssertEqual(name(ofRow: 1), first)
        XCTAssertTrue(app.buttons["plan-row-1"].label.contains("진행 중"), "the exercise in progress stays in focus")

        // Jump: tapping a row makes it the current exercise.
        let close = app.buttons["plan-close"]
        tapUntil(app.buttons["plan-row-0"], app: app) { !close.exists }
        openPlan()
        XCTAssertTrue(app.buttons["plan-row-0"].label.contains("진행 중"))
        XCTAssertEqual(name(ofRow: 0), second)
        closePlan()

        // Add a today-only exercise (long press adds the generic variant).
        let add = app.buttons["session-add-extra"]
        let pickerClose = app.buttons["picker-close"]
        tapUntil(add, app: app) { pickerClose.exists }
        let search = app.textFields["picker-search"]
        search.tap()
        search.typeText("크런치")
        let crunch = app.descendants(matching: .any)["ex-row-crunch"]
        XCTAssertTrue(crunch.waitForExistence(timeout: 5))
        crunch.press(forDuration: 0.6)
        if pickerClose.waitForExistence(timeout: 0) {
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pickerClose)
            waitForExpectations(timeout: 5)
        }

        openPlan()
        XCTAssertEqual(planRows.count, count + 1)
        let last = app.buttons["plan-row-\(count)"]
        XCTAssertTrue(last.label.contains("오늘만"), last.label)
        XCTAssertTrue(last.label.contains("0/3세트"), last.label)
        XCTAssertEqual(name(ofRow: 0), second, "adding keeps the chosen order")
        XCTAssertTrue(app.buttons["plan-remove-\(count)"].exists)

        // Do the added exercise and finish: its sets are recorded.
        tapUntil(last, app: app) { !close.exists }
        let complete = app.buttons["3세트 완료"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        allowNotificationsIfAsked()
        let skip = app.buttons["휴식 건너뛰기"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        openPlan()
        XCTAssertTrue(app.buttons["plan-row-\(count)"].label.contains("3/3세트"))
        XCTAssertFalse(app.buttons["plan-remove-\(count)"].exists, "an exercise with done sets cannot be removed")
        closePlan()

        app.buttons["‹ 나가기"].tap()
        let save = app.buttons["지금까지 기록 저장하고 끝내기"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))

        app.tabBars.firstMatch.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["3세트 완료"].waitForExistence(timeout: 5))
    }

    /// The rest alarm must ring while the app is on screen (iOS drops foreground notifications without a delegate),
    /// and must not ring after "휴식 건너뛰기".
    func testRestAlarmRingsWhileAppIsOnScreen() {
        app.terminate()
        app.launchArguments = ["--demo", "-gym.restSeconds", "10"]
        app.launch()
        let start = app.buttons["start-workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "휴식 끝")).firstMatch
        let tick = app.buttons["세트 완료로 표시"].firstMatch
        let done = app.buttons.matching(identifier: "세트 완료됨")
        let skip = app.buttons["휴식 건너뛰기"]

        // Natural end: leave the rest sheet alone until the timer runs out.
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        tapUntil(tick, app: app) { done.count >= 1 }
        allowNotificationsIfAsked()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "no rest alarm while the app is on screen")
        XCTAssertEqual(app.state, .runningForeground)
        snap("ui-rest-banner", app: app)
        XCTAssertFalse(skip.exists, "the rest sheet closes when the timer ends")

        // Skipped rest: no alarm afterwards.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: banner)
        waitForExpectations(timeout: 15)
        tapUntil(tick, app: app) { done.count >= 2 }
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 14), "a skipped rest must not ring")
    }
}
