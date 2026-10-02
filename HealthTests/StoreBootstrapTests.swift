import XCTest
import SwiftData
@testable import Health

/// AC20. Temp URLs only, never the real Application Support.
final class StoreBootstrapTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private var legacyURL: URL { root.appendingPathComponent("legacy/default.store") }
    private var v2URL: URL { root.appendingPathComponent("v2/soejil-v2.store") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("StoreBootstrapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "StoreBootstrapTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func bootstrap(isDemo: Bool = false, now: Date = .init()) throws -> (ModelContainer, StoreBootstrap.Result) {
        try StoreBootstrap.makeContainer(legacyURL: legacyURL, v2URL: v2URL, isDemo: isDemo, defaults: defaults, now: now)
    }

    private func writeLegacyFiles() throws {
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for file in StoreBootstrap.storeFiles(legacyURL) {
            try Data("legacy".utf8).write(to: file)
        }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testLegacyStoreIsRemovedAndNoticeSetOnce() throws {
        try writeLegacyFiles()
        let (_, result) = try bootstrap()
        XCTAssertTrue(result.legacyRemoved)
        XCTAssertFalse(result.corruptMoved)
        for file in StoreBootstrap.storeFiles(legacyURL) {
            XCTAssertFalse(exists(file), file.lastPathComponent)
        }
        XCTAssertEqual(defaults.string(forKey: StoreBootstrap.noticeKey), StoreBootstrap.noticeReset)

        // Notice is one-time: once RootView clears it, a later launch doesn't set it again.
        defaults.removeObject(forKey: StoreBootstrap.noticeKey)
        let (_, second) = try bootstrap()
        XCTAssertFalse(second.legacyRemoved)
        XCTAssertNil(defaults.string(forKey: StoreBootstrap.noticeKey))
    }

    func testCorruptV2StoreIsPreservedAndRecreated() throws {
        try FileManager.default.createDirectory(at: v2URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try garbage.write(to: v2URL)
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let (container, result) = try bootstrap(now: now)
        XCTAssertTrue(result.corruptMoved)
        XCTAssertTrue(result.retried)
        XCTAssertFalse(result.legacyRemoved)
        XCTAssertEqual(defaults.string(forKey: StoreBootstrap.noticeKey), StoreBootstrap.noticeCorrupt)

        let directory = v2URL.deletingLastPathComponent()
        let moved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("soejil-v2.store.corrupt-") && !$0.hasSuffix("-shm") && !$0.hasSuffix("-wal") }
        XCTAssertEqual(moved.count, 1, "\(moved)")
        let movedURL = directory.appendingPathComponent(try XCTUnwrap(moved.first))
        XCTAssertEqual(try Data(contentsOf: movedURL), garbage)
        XCTAssertNotNil(movedURL.lastPathComponent.range(of: #"\.corrupt-\d{8}-\d{6}$"#, options: .regularExpression))

        let context = ModelContext(container)
        context.insert(AthleteProfile())
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AthleteProfile>()), 1)
    }

    /// L5: only corruption-like errors move the store aside; transient ones (disk full, permission) are retried in place.
    func testTransientErrorIsNotTreatedAsCorruption() {
        XCTAssertFalse(StoreBootstrap.isCorruption(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        XCTAssertFalse(StoreBootstrap.isCorruption(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)))
        XCTAssertTrue(StoreBootstrap.isCorruption(NSError(domain: NSCocoaErrorDomain, code: 259)))
        XCTAssertTrue(StoreBootstrap.isCorruption(NSError(domain: "NSSQLiteErrorDomain", code: 26)))
        XCTAssertTrue(StoreBootstrap.isCorruption(SwiftDataError.loadIssueModelContainer))
        let wrapped = NSError(domain: "Outer", code: 1,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: 134110)])
        XCTAssertTrue(StoreBootstrap.isCorruption(wrapped))
    }

    func testHealthyV2StoreIsKept() throws {
        try autoreleasepool {
            let (container, result) = try bootstrap()
            XCTAssertEqual(result, StoreBootstrap.Result())
            let context = ModelContext(container)
            let profile = AthleteProfile(bench1RM: 101)
            profile.gymBrandIds = ["hammer-strength", "life-fitness"]
            context.insert(profile)
            try context.save()
        }
        let (reopened, result) = try bootstrap()
        XCTAssertFalse(result.corruptMoved)
        XCTAssertFalse(result.legacyRemoved)
        let profile = try XCTUnwrap(ModelContext(reopened).fetch(FetchDescriptor<AthleteProfile>()).first)
        XCTAssertEqual(profile.bench1RM, 101)
        XCTAssertEqual(profile.gymBrandIds, ["hammer-strength", "life-fitness"])
        XCTAssertNil(defaults.string(forKey: StoreBootstrap.noticeKey))
    }

    func testMissingParentDirectoryIsCreated() throws {
        XCTAssertFalse(exists(v2URL.deletingLastPathComponent()))
        let (container, result) = try bootstrap()
        XCTAssertEqual(result, StoreBootstrap.Result())
        XCTAssertTrue(exists(v2URL.deletingLastPathComponent()))
        let context = ModelContext(container)
        context.insert(AthleteProfile())
        try context.save()
        XCTAssertTrue(exists(v2URL))
    }

    func testDemoSkipsLegacyRemoval() throws {
        try writeLegacyFiles()
        let (container, result) = try bootstrap(isDemo: true)
        XCTAssertEqual(result, StoreBootstrap.Result())
        for file in StoreBootstrap.storeFiles(legacyURL) {
            XCTAssertTrue(exists(file), file.lastPathComponent)
        }
        XCTAssertFalse(exists(v2URL))
        XCTAssertNil(defaults.string(forKey: StoreBootstrap.noticeKey))
        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }

    func testUserVariantSurvivesReopen() throws {
        try autoreleasepool {
            let context = ModelContext(try bootstrap().0)
            context.insert(UserVariant(id: "uv-1", exerciseId: "chest-press", brandId: "hammer-strength",
                                       brandName: "해머스트렝스", nickname: "2층 머신", plane: "upper"))
            context.insert(UserVariant(id: "uv-2", exerciseId: "other", nickname: "자유 입력", plane: "lower", isHidden: true))
            try context.save()
        }
        let context = ModelContext(try bootstrap().0)
        var descriptor = FetchDescriptor<UserVariant>(predicate: #Predicate { $0.id == "uv-1" })
        descriptor.fetchLimit = 1
        let variant = try XCTUnwrap(context.fetch(descriptor).first)
        XCTAssertEqual(variant.exerciseId, "chest-press")
        XCTAssertEqual(variant.brandId, "hammer-strength")
        XCTAssertEqual(variant.brandName, "해머스트렝스")
        XCTAssertEqual(variant.nickname, "2층 머신")
        XCTAssertEqual(variant.plane, "upper")
        XCTAssertFalse(variant.isHidden)
        let other = try XCTUnwrap(context.fetch(FetchDescriptor<UserVariant>(predicate: #Predicate { $0.id == "uv-2" })).first)
        XCTAssertNil(other.brandId)
        XCTAssertTrue(other.isHidden)
    }
}
