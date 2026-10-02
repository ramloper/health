import XCTest
import Combine
import ImageIO
import UIKit
@testable import Health

// MARK: - Fixtures

private enum ShopJSON {
    static func product(
        _ id: String,
        category: String = "gear",
        price: String? = "12,900원",
        imageURL: String? = nil,
        coupangURL: String? = nil
    ) -> [String: Any] {
        var p: [String: Any] = [
            "id": id, "categoryId": category, "name": "상품 \(id)", "summary": "요약 \(id)",
            "coupangURL": coupangURL ?? "https://link.coupang.com/a/\(id)",
        ]
        if let price { p["price"] = price }
        if let imageURL { p["imageURL"] = imageURL }
        return p
    }

    static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func feed(categories: [[String: Any]]? = [["id": "gear", "name": "장비"]],
                     products: [[String: Any]]) -> Data {
        var root: [String: Any] = ["version": 1, "updatedAt": "2026-10-02", "products": products]
        if let categories { root["categories"] = categories }
        return data(root)
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    static func jpeg(side: CGFloat = 8) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

// MARK: - Decoding

final class ShopFeedDecoderTests: XCTestCase {
    func testDecodesSpecExample() throws {
        let json = """
        {
          "version": 1,
          "updatedAt": "2026-10-02",
          "categories": [{ "id": "gear", "name": "장비" }],
          "products": [{
            "id": "strap-001",
            "categoryId": "gear",
            "name": "리프팅 스트랩",
            "summary": "데드리프트 그립 보조",
            "price": "12,900원",
            "imageURL": "https://ramloper.github.io/health/shop/images/strap-001.jpg",
            "coupangURL": "https://link.coupang.com/a/XXXX"
          }]
        }
        """
        let feed = try ShopFeedDecoder.decode(Data(json.utf8))
        XCTAssertEqual(feed.version, 1)
        XCTAssertEqual(feed.updatedAt, "2026-10-02")
        XCTAssertEqual(feed.categories, [ShopCategory(id: "gear", name: "장비")])
        XCTAssertEqual(feed.droppedCount, 0)
        let product = try XCTUnwrap(feed.products.first)
        XCTAssertEqual(product.id, "strap-001")
        XCTAssertEqual(product.categoryId, "gear")
        XCTAssertEqual(product.name, "리프팅 스트랩")
        XCTAssertEqual(product.summary, "데드리프트 그립 보조")
        XCTAssertEqual(product.price, "12,900원")
        XCTAssertEqual(product.imageURL?.absoluteString, "https://ramloper.github.io/health/shop/images/strap-001.jpg")
        XCTAssertEqual(product.coupangURL.absoluteString, "https://link.coupang.com/a/XXXX")
    }

    func testUnknownFieldsIgnored() throws {
        var p = ShopJSON.product("a")
        p["rating"] = 4.5
        p["tags"] = ["x"]
        let data = ShopJSON.data([
            "schema": "v9", "products": [p],
            "categories": [["id": "gear", "name": "장비", "icon": "bag"]],
        ])
        let feed = try ShopFeedDecoder.decode(data)
        XCTAssertEqual(feed.products.map(\.id), ["a"])
        XCTAssertEqual(feed.categories.map(\.id), ["gear"])
    }

    func testProductMissingRequiredFieldIsDropped() throws {
        var products: [[String: Any]] = []
        for key in ["id", "categoryId", "name", "summary", "coupangURL"] {
            var p = ShopJSON.product("missing-\(key)")
            p.removeValue(forKey: key)
            products.append(p)
        }
        var wrongType = ShopJSON.product("wrong-type")
        wrongType["name"] = 42
        products.append(wrongType)
        products.append(ShopJSON.product("ok"))
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(products: products + [["junk": true]]))
        XCTAssertEqual(feed.products.map(\.id), ["ok"])
        XCTAssertEqual(feed.droppedCount, 7)
    }

    func testMissingProductsKeyThrows() {
        XCTAssertThrowsError(try ShopFeedDecoder.decode(ShopJSON.data(["categories": []])))
        XCTAssertThrowsError(try ShopFeedDecoder.decode(Data("not json".utf8)))
    }

    func testVersionAndUpdatedAtOptional() throws {
        let feed = try ShopFeedDecoder.decode(ShopJSON.data(["products": [ShopJSON.product("a")]]))
        XCTAssertNil(feed.version)
        XCTAssertNil(feed.updatedAt)
        XCTAssertEqual(feed.products.count, 1)
    }

    func testMissingCategoriesShowsOnlyAll() throws {
        let missing = try ShopFeedDecoder.decode(ShopJSON.feed(categories: nil, products: [ShopJSON.product("a")]))
        XCTAssertTrue(missing.categories.isEmpty)
        XCTAssertEqual(missing.products(in: nil).map(\.id), ["a"])
        let empty = try ShopFeedDecoder.decode(ShopJSON.feed(categories: [], products: [ShopJSON.product("a")]))
        XCTAssertTrue(empty.categories.isEmpty)
        XCTAssertEqual(empty.products.count, 1)
    }

    func testDuplicateIdsKeepFirst() throws {
        let data = ShopJSON.feed(
            categories: [["id": "gear", "name": "장비"], ["id": "gear", "name": "중복"], ["id": "x", "name": "엑스"]],
            products: [ShopJSON.product("a", price: "1원"), ShopJSON.product("b"), ShopJSON.product("a", price: "2원")]
        )
        let feed = try ShopFeedDecoder.decode(data)
        XCTAssertEqual(feed.categories.map(\.name), ["장비", "엑스"])
        XCTAssertEqual(feed.products.map(\.id), ["a", "b"])
        XCTAssertEqual(feed.products.first?.price, "1원")
        XCTAssertEqual(feed.droppedCount, 1)
    }

    func testNonHttpsCoupangURLExcluded() throws {
        let bad = ["http://link.coupang.com/a/1", "javascript:alert(1)", "", "https://", "https:///path", "coupang.com/a/1"]
        var products = bad.enumerated().map { ShopJSON.product("bad-\($0.offset)", coupangURL: $0.element) }
        products.append(ShopJSON.product("ok", coupangURL: "HTTPS://link.coupang.com/a/ok"))
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(products: products))
        XCTAssertEqual(feed.products.map(\.id), ["ok"])
        XCTAssertEqual(feed.droppedCount, bad.count)
    }

    func testNonHttpsImageKeepsProductWithNilImage() throws {
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(products: [
            ShopJSON.product("http", imageURL: "http://example.com/a.jpg"),
            ShopJSON.product("file", imageURL: "file:///tmp/a.jpg"),
            ShopJSON.product("none"),
            ShopJSON.product("ok", imageURL: "https://example.com/a.jpg"),
        ]))
        XCTAssertEqual(feed.products.map(\.id), ["http", "file", "none", "ok"])
        XCTAssertEqual(feed.products.map { $0.imageURL?.absoluteString }, [nil, nil, nil, "https://example.com/a.jpg"])
    }

    func testPriceIsOptional() throws {
        var numericPrice = ShopJSON.product("numeric")
        numericPrice["price"] = 12900
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(products: [
            ShopJSON.product("none", price: nil), numericPrice, ShopJSON.product("ok"),
        ]))
        XCTAssertEqual(feed.products.map(\.price), [nil, nil, "12,900원"])
    }

    func testChipOrderFollowsCategories() throws {
        let data = ShopJSON.feed(
            categories: [["id": "z", "name": "제트"], ["id": "a", "name": "에이"], ["id": "m", "name": "엠"]],
            products: [ShopJSON.product("1", category: "a")]
        )
        XCTAssertEqual(try ShopFeedDecoder.decode(data).categories.map(\.id), ["z", "a", "m"])
    }

    func testFilterByCategory() throws {
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(
            categories: [["id": "gear", "name": "장비"], ["id": "food", "name": "식품"]],
            products: [
                ShopJSON.product("g1", category: "gear"),
                ShopJSON.product("f1", category: "food"),
                ShopJSON.product("g2", category: "gear"),
            ]
        ))
        XCTAssertEqual(feed.products(in: nil).map(\.id), ["g1", "f1", "g2"])
        XCTAssertEqual(feed.products(in: "gear").map(\.id), ["g1", "g2"])
        XCTAssertEqual(feed.products(in: "food").map(\.id), ["f1"])
    }

    func testOrphanProductOnlyInAll() throws {
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(products: [
            ShopJSON.product("g1", category: "gear"),
            ShopJSON.product("orphan", category: "unknown"),
        ]))
        XCTAssertEqual(feed.products(in: nil).map(\.id), ["g1", "orphan"])
        for category in feed.categories {
            XCTAssertFalse(feed.products(in: category.id).contains { $0.id == "orphan" })
        }
    }

    func testEmptyCategoryProducesEmptyState() throws {
        let feed = try ShopFeedDecoder.decode(ShopJSON.feed(
            categories: [["id": "gear", "name": "장비"], ["id": "apparel", "name": "의류"]],
            products: [ShopJSON.product("g1", category: "gear")]
        ))
        XCTAssertEqual(feed.categories.map(\.id), ["gear", "apparel"])
        XCTAssertTrue(feed.products(in: "apparel").isEmpty)
        XCTAssertFalse(feed.products(in: nil).isEmpty)
    }
}

// MARK: - Service

private actor FetchStub {
    private var results: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var calls = 0

    init(_ results: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func next() async throws -> Data {
        calls += 1
        if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

final class ShopServiceTests: XCTestCase {
    private let feedA = ShopJSON.feed(products: [ShopJSON.product("a")])
    private let feedB = ShopJSON.feed(products: [ShopJSON.product("b")])

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shop-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func environment(
        _ stub: FetchStub,
        directory: URL?,
        transform: @escaping (URL) -> URL = { $0 }
    ) -> ShopEnvironment {
        ShopEnvironment(
            feedURL: URL(string: "https://example.invalid/shop.json")!,
            cacheDirectory: directory,
            fetch: { _ in try await stub.next() },
            imageURLTransform: transform,
            interceptsOpenURL: true,
            allowsRemoteImages: false
        )
    }

    private func productIds(_ state: ShopService.State) -> [String]? {
        if case .loaded(let feed) = state { return feed.products.map(\.id) }
        return nil
    }

    @MainActor
    func testSuccessWritesCacheAndPublishesLoaded() async throws {
        let dir = try makeTempDirectory()
        let service = ShopService(environment: environment(FetchStub([.success(feedA)]), directory: dir))
        XCTAssertEqual(service.state, .loading)
        await service.refresh()
        XCTAssertEqual(productIds(service.state), ["a"])

        let cached = try Data(contentsOf: dir.appendingPathComponent(ShopService.cacheFileName))
        XCTAssertEqual(cached, feedA)
        let metaData = try Data(contentsOf: dir.appendingPathComponent(ShopService.metaFileName))
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(with: metaData) as? [String: String])
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(meta["fetchedAt"])))

        let restored = ShopService(environment: environment(FetchStub([.failure(URLError(.timedOut))]), directory: dir))
        XCTAssertEqual(productIds(restored.state), ["a"])
    }

    @MainActor
    func testRefreshCallsFetchEveryTime() async throws {
        let stub = FetchStub([.success(feedA), .success(feedB)])
        let service = ShopService(environment: environment(stub, directory: nil))
        await service.refresh()
        await service.refresh()
        let calls = await stub.calls
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(productIds(service.state), ["b"])
    }

    @MainActor
    func testConcurrentRefreshSharesOneFetch() async throws {
        let stub = FetchStub([.success(feedA)], delayNanoseconds: 200_000_000)
        let service = ShopService(environment: environment(stub, directory: nil))
        async let first: Void = service.refresh()
        async let second: Void = service.refresh()
        _ = await (first, second)
        let calls = await stub.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(productIds(service.state), ["a"])
    }

    @MainActor
    func testCancellationIsNotFailure() async throws {
        let stub = FetchStub([.failure(CancellationError()), .failure(URLError(.cancelled)), .success(feedA),
                              .failure(URLError(.cancelled))])
        let service = ShopService(environment: environment(stub, directory: nil))
        await service.refresh()
        XCTAssertEqual(service.state, .loading)
        await service.refresh()
        XCTAssertEqual(service.state, .loading)
        await service.refresh()
        await service.refresh()
        XCTAssertEqual(productIds(service.state), ["a"])
    }

    @MainActor
    func testLoadedDoesNotRegressToLoading() async throws {
        let stub = FetchStub([.success(feedA), .success(feedB), .failure(URLError(.notConnectedToInternet))])
        let service = ShopService(environment: environment(stub, directory: nil))
        await service.refresh()
        var states: [ShopService.State] = []
        let cancellable = service.$state.dropFirst().sink { states.append($0) }
        await service.refresh()
        await service.refresh()
        cancellable.cancel()
        XCTAssertFalse(states.contains(.loading))
        XCTAssertFalse(states.contains(.failed))
        XCTAssertEqual(productIds(service.state), ["b"])
    }

    @MainActor
    func testZeroProductFeedIsNotCached() async throws {
        let dir = try makeTempDirectory()
        let empty = ShopJSON.feed(products: [])
        let service = ShopService(environment: environment(FetchStub([.success(feedA), .success(empty)]), directory: dir))
        await service.refresh()
        await service.refresh()
        XCTAssertEqual(productIds(service.state), [])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(ShopService.cacheFileName)), feedA)

        let freshDir = try makeTempDirectory()
        let fresh = ShopService(environment: environment(FetchStub([.success(empty)]), directory: freshDir))
        await fresh.refresh()
        XCTAssertFalse(FileManager.default.fileExists(atPath: freshDir.appendingPathComponent(ShopService.cacheFileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: freshDir.appendingPathComponent(ShopService.metaFileName).path))
    }

    @MainActor
    func testFailureWithCacheShowsCache() async throws {
        let dir = try makeTempDirectory()
        try feedA.write(to: dir.appendingPathComponent(ShopService.cacheFileName))
        let service = ShopService(environment: environment(FetchStub([.failure(URLError(.notConnectedToInternet))]), directory: dir))
        XCTAssertEqual(productIds(service.state), ["a"])
        await service.refresh()
        XCTAssertEqual(productIds(service.state), ["a"])
    }

    @MainActor
    func testFailureWithoutCacheIsFailedAndRetryRefetches() async throws {
        let dir = try makeTempDirectory()
        let stub = FetchStub([.failure(URLError(.notConnectedToInternet)), .success(feedA)])
        let service = ShopService(environment: environment(stub, directory: dir))
        var states: [ShopService.State] = []
        let cancellable = service.$state.sink { states.append($0) }
        await service.refresh()
        XCTAssertEqual(service.state, .failed)
        await service.refresh()
        cancellable.cancel()
        XCTAssertEqual(states.map(productIds), [nil, nil, nil, ["a"]])
        XCTAssertEqual(Array(states.prefix(3)), [.loading, .failed, .loading])
        let calls = await stub.calls
        XCTAssertEqual(calls, 2)
    }

    @MainActor
    func testFailedDecodeWithoutCacheIsFailed() async throws {
        let service = ShopService(environment: environment(FetchStub([.success(Data("<html>".utf8))]), directory: nil))
        await service.refresh()
        XCTAssertEqual(service.state, .failed)
    }

    @MainActor
    func testCorruptCacheIsDeletedAndIgnored() async throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent(ShopService.cacheFileName)
        try Data("{ broken".utf8).write(to: file)
        let service = ShopService(environment: environment(FetchStub([.failure(URLError(.timedOut))]), directory: dir))
        XCTAssertEqual(service.state, .loading)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        await service.refresh()
        XCTAssertEqual(service.state, .failed)
    }

    @MainActor
    func testImageURLTransformAppliedToNetworkAndCache() async throws {
        let dir = try makeTempDirectory()
        let data = ShopJSON.feed(products: [ShopJSON.product("a", imageURL: "https://example.com/a.jpg")])
        let transform: (URL) -> URL = { URL(fileURLWithPath: "/fixtures/\($0.lastPathComponent)") }
        let service = ShopService(environment: environment(FetchStub([.success(data)]), directory: dir, transform: transform))
        await service.refresh()
        guard case .loaded(let feed) = service.state else { return XCTFail("not loaded") }
        XCTAssertEqual(feed.products.first?.imageURL, URL(fileURLWithPath: "/fixtures/a.jpg"))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(ShopService.cacheFileName)), data)

        let restored = ShopService(environment: environment(FetchStub([.failure(URLError(.timedOut))]), directory: dir, transform: transform))
        guard case .loaded(let cachedFeed) = restored.state else { return XCTFail("cache not restored") }
        XCTAssertEqual(cachedFeed.products.first?.imageURL, URL(fileURLWithPath: "/fixtures/a.jpg"))
    }
}

// MARK: - Environment

final class ShopEnvironmentTests: XCTestCase {
    func testValidateRejectsNon2xxAndNonHTTP() throws {
        let url = URL(string: "https://example.invalid/shop.json")!
        let data = Data("{}".utf8)
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertEqual(try ShopEnvironment.validate(data: data, response: ok), data)
        let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try ShopEnvironment.validate(data: data, response: notFound))
        let plain = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        XCTAssertThrowsError(try ShopEnvironment.validate(data: data, response: plain))
    }

    func testCurrentEnvironmentIsOfflineInTestHost() async {
        let environment = ShopEnvironment.current
        XCTAssertFalse(environment.allowsRemoteImages)
        XCTAssertNil(environment.cacheDirectory)
        do {
            _ = try await environment.fetch(environment.feedURL)
            XCTFail("test host must not fetch")
        } catch {}
    }

    func testUITestEnvironmentMapsProductionImagesToFixtureFolder() {
        let feedPath = ShopJSON.repoRoot.appendingPathComponent("HealthUITests/Fixtures/shop.json").path
        let environment = ShopEnvironment.uiTest(feedPath: feedPath)
        let remote = URL(string: "https://ramloper.github.io/health/shop/images/strap-001.jpg")!
        let mapped = environment.imageURLTransform(remote)
        XCTAssertTrue(mapped.isFileURL)
        XCTAssertEqual(mapped.path, ShopJSON.repoRoot.appendingPathComponent("HealthUITests/Fixtures/shop/images/strap-001.jpg").path)
        let other = URL(string: "https://example.com/a.jpg")!
        XCTAssertEqual(environment.imageURLTransform(other), other)
        XCTAssertNil(environment.cacheDirectory)
        XCTAssertTrue(environment.interceptsOpenURL)
        XCTAssertFalse(environment.allowsRemoteImages)
    }
}

// MARK: - Image loader

final class ShopImageLoaderTests: XCTestCase {
    private func store(_ body: Data, for url: URL, in cache: URLCache, mimeType: String) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mimeType, "Cache-Control": "max-age=600"])!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: body), for: URLRequest(url: url))
    }

    func testImageLoaderUsesCachedDataWhenOffline() async {
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let url = URL(string: "https://example.invalid/a.jpg")!
        store(ShopJSON.jpeg(), for: url, in: cache, mimeType: "image/jpeg")
        let loader = ShopImageLoader(cache: cache, allowsRemote: true, cachePolicy: .returnCacheDataDontLoad)
        let image = await loader.image(for: url)
        XCTAssertNotNil(image)
    }

    func testImageLoaderLoadsFileURL() async {
        let url = ShopJSON.repoRoot.appendingPathComponent("HealthUITests/Fixtures/shop/images/strap-001.jpg")
        let loader = ShopImageLoader(cache: URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil), allowsRemote: false)
        let image = await loader.image(for: url)
        XCTAssertNotNil(image)
    }

    func testImageLoaderRejectsNonImageBody() async {
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let url = URL(string: "https://example.invalid/missing.jpg")!
        store(Data("<html>404</html>".utf8), for: url, in: cache, mimeType: "text/html")
        XCTAssertNotNil(cache.cachedResponse(for: URLRequest(url: url)))
        let loader = ShopImageLoader(cache: cache, allowsRemote: true, cachePolicy: .returnCacheDataDontLoad)
        let image = await loader.image(for: url)
        XCTAssertNil(image)
        XCTAssertNil(cache.cachedResponse(for: URLRequest(url: url)))
    }

    func testImageLoaderSkipsRemoteWhenNotAllowed() async {
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let url = URL(string: "https://example.invalid/a.jpg")!
        store(ShopJSON.jpeg(), for: url, in: cache, mimeType: "image/jpeg")
        let loader = ShopImageLoader(cache: cache, allowsRemote: false, cachePolicy: .returnCacheDataDontLoad)
        let image = await loader.image(for: url)
        XCTAssertNil(image)
    }
}

// MARK: - Published feeds

final class ShopPublishedFeedTests: XCTestCase {
    private static let remoteBase = ShopEnvironment.productionFeedURL.deletingLastPathComponent().absoluteString

    /// 피드 디코딩 손실 없음 + categoryId 무결성 + 이미지 용량·크기 검사.
    private func assertFeedValid(_ feedURL: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try Data(contentsOf: feedURL)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
        let rawProducts = try XCTUnwrap(raw["products"] as? [Any], file: file, line: line)
        let feed = try ShopFeedDecoder.decode(data)
        XCTAssertFalse(feed.products.isEmpty, file: file, line: line)
        XCTAssertEqual(feed.products.count, rawProducts.count, "dropped products", file: file, line: line)
        let categoryIds = Set(feed.categories.map(\.id))
        for product in feed.products {
            XCTAssertTrue(categoryIds.contains(product.categoryId), "\(product.id) has unknown categoryId", file: file, line: line)
        }

        let baseDir = feedURL.deletingLastPathComponent()
        for product in feed.products {
            guard let image = product.imageURL?.absoluteString, image.hasPrefix(Self.remoteBase) else { continue }
            let local = baseDir.appendingPathComponent(String(image.dropFirst(Self.remoteBase.count)))
            XCTAssertTrue(FileManager.default.fileExists(atPath: local.path), "missing \(local.lastPathComponent)", file: file, line: line)
        }

        let imagesDir = baseDir.appendingPathComponent("shop/images")
        let images = (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)) ?? []
        for url in images where url.pathExtension.lowercased() == "jpg" {
            let bytes = try Data(contentsOf: url)
            XCTAssertLessThanOrEqual(bytes.count, 150 * 1024, "\(url.lastPathComponent) too large", file: file, line: line)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil), file: file, line: line)
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], file: file, line: line)
            let width = props[kCGImagePropertyPixelWidth] as? Int ?? .max
            let height = props[kCGImagePropertyPixelHeight] as? Int ?? .max
            XCTAssertLessThanOrEqual(width, 600, url.lastPathComponent, file: file, line: line)
            XCTAssertLessThanOrEqual(height, 600, url.lastPathComponent, file: file, line: line)
        }
    }

    func testUITestFixtureFeedIsValid() throws {
        let feedURL = ShopJSON.repoRoot.appendingPathComponent("HealthUITests/Fixtures/shop.json")
        try assertFeedValid(feedURL)
        let feed = try ShopFeedDecoder.decode(Data(contentsOf: feedURL))
        XCTAssertEqual(feed.categories.map(\.id), ["gear", "supplement", "apparel"])
        XCTAssertEqual(feed.products.map(\.id), ["strap-001", "belt-001", "chalk-001", "whey-001"])
        XCTAssertTrue(feed.products(in: "apparel").isEmpty)
        XCTAssertNil(feed.products.first { $0.id == "chalk-001" }?.price)
    }

    func testDocsShopJsonDecodes() throws {
        let feedURL = ShopJSON.repoRoot.appendingPathComponent("docs/shop.json")
        guard FileManager.default.fileExists(atPath: feedURL.path) else {
            throw XCTSkip("docs/shop.json not committed yet (Stage 4-B)")
        }
        try assertFeedValid(feedURL)
    }
}
