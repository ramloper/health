import XCTest

/// Exercise library flows (AC15, AC16, AC22): two-step picker, long-press generic add, user variants.
final class LibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.useShopFeed(preferDocs: false)
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private var pickerClose: XCUIElement { app.buttons["picker-close"] }

    /// Profile → "우리 헬스장 브랜드": clears the demo selection, then selects `brandIds`.
    private func setGymBrands(_ brandIds: [String]) {
        let tabs = app.tabBars.firstMatch
        tabs.buttons["프로필"].tap()
        let row = any("gym-brands-row")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let done = app.buttons["gym-brands-done"]
        tapUntil(row, app: app) { done.exists }
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gym-brand-' AND selected == true"))
        while selected.count > 0 {
            let brand = selected.firstMatch
            let before = selected.count
            tapUntil(brand, app: app) { selected.count < before }
        }
        for id in brandIds {
            let brand = app.buttons["gym-brand-\(id)"]
            XCTAssertTrue(brand.waitForExistence(timeout: 5))
            tapUntil(brand, app: app) { brand.isSelected }
        }
        tapUntil(done, app: app) { !done.exists }
        XCTAssertEqual(row.value as? String, "\(brandIds.count)개")
    }

    /// Today tab → "수정" (day editor sheet) → "운동 추가" (picker).
    private func openTodayEditor() {
        app.tabBars.firstMatch.buttons["오늘"].tap()
        let edit = app.buttons["수정"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        let add = app.buttons["운동 추가"]
        tapUntil(edit, app: app) { add.exists }
    }

    private func openPicker() {
        let add = app.buttons["운동 추가"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        tapUntil(add, app: app) { pickerClose.exists }
    }

    private func pushVariants(_ exerciseId: String) {
        let row = any("ex-row-\(exerciseId)")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let new = any("variant-new")
        tapUntil(row, app: app) { new.exists }
    }

    private func cardCount(containing text: String) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).count
    }

    func testPickerTwoStageAddsGymVariant() {
        setGymBrands(["hammer"])
        openTodayEditor()
        let display = "해머스트렝스 선택형 체스트 프레스"
        XCTAssertEqual(cardCount(containing: display), 0)
        openPicker()

        let chest = app.buttons["group-chip-chest"]
        tapUntil(chest, app: app) { chest.isSelected }
        let machine = app.buttons["equip-chip-machine"]
        tapUntil(machine, app: app) { machine.isSelected }
        XCTAssertFalse(any("ex-row-bench").exists)
        pushVariants("machine-chest-press")

        XCTAssertTrue(any("gym-section").waitForExistence(timeout: 5))
        let variant = any("variant-row-machine-chest-press/hammer-selectorized")
        XCTAssertTrue(variant.exists)
        snap("picker-gym-section", app: app)
        tapUntil(variant, app: app) { !pickerClose.exists }

        let card = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "해머스트렝스")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, display)

        let save = app.buttons["저장"]
        tapUntil(save, app: app) { !save.exists }
        XCTAssertTrue(app.buttons["start-workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[display].waitForExistence(timeout: 5))
        snap("today-gym-variant", app: app)
    }

    func testLongPressAddsGeneric() {
        openTodayEditor()
        let before = cardCount(containing: "벤치프레스")
        openPicker()
        let bench = any("ex-row-bench")
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.press(forDuration: 0.6)
        if pickerClose.waitForExistence(timeout: 0) {
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: pickerClose)
            waitForExpectations(timeout: 5)
        }
        XCTAssertFalse(any("variant-new").exists, "long press must not push the variant sheet")
        XCTAssertEqual(cardCount(containing: "벤치프레스"), before + 1)
    }

    func testEmptyGymShowsMyVariants() {
        setGymBrands([])
        openTodayEditor()
        openPicker()
        pushVariants("bench")
        XCTAssertFalse(any("gym-section").exists)

        let new = any("variant-new")
        let nickname = app.textFields["variant-form-nickname"]
        tapUntil(new, app: app) { nickname.exists }
        nickname.tap()
        nickname.typeText("우리 헬스장 벤치")
        let custom = app.buttons["variant-form-brand-custom"]
        let brandName = app.textFields["variant-form-brand-name"]
        tapUntil(custom, app: app) { brandName.exists }
        brandName.tap()
        brandName.typeText("동네짐")
        let save = any("variant-form-save")
        tapUntil(save, app: app) { !pickerClose.exists && !save.exists }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "우리 헬스장 벤치"))
            .firstMatch.waitForExistence(timeout: 5))

        openPicker()
        pushVariants("bench")
        XCTAssertTrue(any("my-variants-section").waitForExistence(timeout: 5))
        XCTAssertFalse(any("gym-section").exists)
        let mine = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'variant-row-bench/u-'"))
        XCTAssertGreaterThanOrEqual(mine.count, 1)
        snap("picker-my-variants", app: app)
    }
}
