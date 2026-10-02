import XCTest

final class ShopUITests: XCTestCase {
    func testShopTabWithLocalFeed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.useShopFeed(preferDocs: false)
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["쇼핑"].tap()

        let banner = app.staticTexts["shop-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertEqual(banner.label, shopBannerText)
        XCTAssertTrue(banner.isHittable)
        XCTAssertTrue(app.buttons["shop-chip-all"].waitForExistence(timeout: 5))

        func card(_ id: String) -> XCUIElement { app.buttons["shop-card-\(id)"] }
        func chip(_ id: String) -> XCUIElement { app.buttons["shop-chip-\(id)"] }

        XCTAssertTrue(card("strap-001").waitForExistence(timeout: 5))
        snap("shop-all", app: app)

        chip("gear").tap()
        XCTAssertTrue(card("strap-001").waitForExistence(timeout: 5))
        XCTAssertTrue(card("belt-001").exists)
        XCTAssertTrue(card("chalk-001").exists)
        XCTAssertFalse(card("whey-001").exists)

        let chalkLabel = card("chalk-001").label
        XCTAssertTrue(chalkLabel.contains("액상 초크"), chalkLabel)
        XCTAssertTrue(chalkLabel.contains("쿠팡에서 보기"), chalkLabel)
        XCTAssertFalse(chalkLabel.contains("원"), chalkLabel)

        chip("supplement").tap()
        XCTAssertTrue(card("whey-001").waitForExistence(timeout: 5))
        XCTAssertFalse(card("strap-001").exists)
        XCTAssertFalse(card("belt-001").exists)
        XCTAssertFalse(card("chalk-001").exists)

        chip("apparel").tap()
        XCTAssertTrue(app.descendants(matching: .any)["shop-empty"].waitForExistence(timeout: 5))

        chip("all").tap()
        XCTAssertTrue(card("strap-001").waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shop-card-'")).count, 4)

        let lastOpened = app.descendants(matching: .any)["shop-last-opened"]
        tapUntil(card("strap-001"), app: app) {
            lastOpened.exists && lastOpened.label == "https://example.com/shop/strap-001"
        }
    }
}
