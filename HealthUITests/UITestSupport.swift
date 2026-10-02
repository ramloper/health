import XCTest

// 스펙 AC2 원문. 앱 쪽 상수 변경 시 동기화
let shopBannerText = "이 앱은 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다. 가격은 변동될 수 있어요."

extension XCTestCase {
    /// Plain-style SwiftUI buttons sometimes ignore the first synthesized tap; retry by coordinate.
    func tapUntil(_ element: XCUIElement, app: XCUIApplication, attempts: Int = 3, _ condition: () -> Bool) {
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
        snap("99-failure", app: app)
        XCTFail("tap did not take effect: \(element)")
    }

    func snap(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension XCUIApplication {
    /// 네트워크 없이 쇼핑 피드를 로컬 파일로 주입한다. 값은 스킴 없는 절대 경로.
    func useShopFeed(preferDocs: Bool) {
        // 이 파일: <root>/HealthUITests/UITestSupport.swift
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let docs = root.appendingPathComponent("docs/shop.json")
        let fixture = root.appendingPathComponent("HealthUITests/Fixtures/shop.json")
        let url = (preferDocs && FileManager.default.fileExists(atPath: docs.path)) ? docs : fixture
        launchEnvironment["SHOP_FEED_PATH"] = url.path
    }
}
