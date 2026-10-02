import Foundation
import UIKit
import os

// 개인정보 매니페스트(PrivacyInfo.xcprivacy)를 바꾸지 않기 위해 이 파일에서는
// 파일 수정일·생성일 API와 디스크 용량 API를 쓰지 않아요. 받은 시각은 메타 파일 본문에만 기록.

private let shopLogger = Logger(subsystem: "com.wooram.health", category: "shop")

struct ShopEnvironment {
    var feedURL: URL
    /// `nil`이면 디스크 캐시 없이 메모리 상태만 사용.
    var cacheDirectory: URL?
    var fetch: @Sendable (URL) async throws -> Data
    var imageURLTransform: (URL) -> URL
    /// `true`면 카드 액션이 `openURL` 대신 기록만 해요(UI 테스트).
    var interceptsOpenURL: Bool
    var allowsRemoteImages: Bool

    static let productionFeedURL = URL(string: "https://ramloper.github.io/health/shop.json")!

    static func live() -> ShopEnvironment {
        ShopEnvironment(
            feedURL: productionFeedURL,
            cacheDirectory: liveCacheDirectory(),
            fetch: { url in
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                let (data, response) = try await URLSession.shared.data(for: request)
                return try validate(data: data, response: response)
            },
            imageURLTransform: { $0 },
            interceptsOpenURL: false,
            allowsRemoteImages: true
        )
    }

    /// HTTP 2xx만 통과. HTTP가 아닌 응답은 에러.
    static func validate(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func liveCacheDirectory() -> URL? {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            var directory = support.appendingPathComponent("shop", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 원자적 쓰기의 rename이 파일 속성을 지우므로 디렉터리에 설정.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            return directory
        } catch {
            shopLogger.error("cache directory unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    #if DEBUG
    /// UI 테스트: 호스트의 픽스처 피드를 읽고, 운영 이미지 URL을 픽스처 폴더의 파일로 바꿔요.
    static func uiTest(feedPath: String) -> ShopEnvironment {
        let feedURL = URL(fileURLWithPath: feedPath)
        let remoteBase = productionFeedURL.deletingLastPathComponent().absoluteString
        let localBase = feedURL.deletingLastPathComponent()
        return ShopEnvironment(
            feedURL: feedURL,
            cacheDirectory: nil,
            fetch: { url in try Data(contentsOf: url) },
            imageURLTransform: { url in
                let string = url.absoluteString
                guard string.hasPrefix(remoteBase) else { return url }
                return localBase.appendingPathComponent(String(string.dropFirst(remoteBase.count)))
            },
            interceptsOpenURL: true,
            allowsRemoteImages: false
        )
    }

    /// 유닛 테스트 호스트: 네트워크·디스크를 건드리지 않아요.
    static func offlineTestHost() -> ShopEnvironment {
        ShopEnvironment(
            feedURL: productionFeedURL,
            cacheDirectory: nil,
            fetch: { _ in throw URLError(.notConnectedToInternet) },
            imageURLTransform: { $0 },
            interceptsOpenURL: true,
            allowsRemoteImages: false
        )
    }
    #endif

    static var current: ShopEnvironment {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["SHOP_FEED_PATH"], !path.isEmpty {
            return uiTest(feedPath: path)
        }
        if environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return offlineTestHost()
        }
        #endif
        return live()
    }
}

@MainActor
final class ShopService: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(ShopFeed)
        case failed
    }

    static let cacheFileName = "feed-cache.json"
    static let metaFileName = "feed-cache.meta.json"

    @Published private(set) var state: State = .loading
    let environment: ShopEnvironment
    private var refreshTask: Task<Void, Never>?

    init(environment: ShopEnvironment = .current) {
        self.environment = environment
        restoreCache()
    }

    /// 진행 중인 요청이 있으면 그 요청을 기다려요(`.refreshable` 취소가 요청을 끊지 않도록 서비스가 Task를 소유).
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        if state == .failed { state = .loading }
        let task = Task { [weak self] in
            await self?.load()
            self?.refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func load() async {
        let data: Data
        do {
            data = try await environment.fetch(environment.feedURL)
        } catch {
            if Self.isCancellation(error) { return }
            shopLogger.error("feed fetch failed: \(error.localizedDescription)")
            markFailed()
            return
        }
        guard let feed = decode(data) else {
            markFailed()
            return
        }
        if !feed.products.isEmpty { writeCache(data) }
        state = .loaded(feed)
    }

    private func markFailed() {
        if case .loaded = state { return }
        state = .failed
    }

    /// 네트워크·캐시 공통 디코딩 경로. 이미지 URL 변환까지 적용.
    private func decode(_ data: Data) -> ShopFeed? {
        do {
            var feed = try ShopFeedDecoder.decode(data)
            if feed.droppedCount > 0 {
                shopLogger.notice("feed dropped \(feed.droppedCount) products")
            }
            for index in feed.products.indices {
                feed.products[index].imageURL = feed.products[index].imageURL.map(environment.imageURLTransform)
            }
            return feed
        } catch {
            shopLogger.error("feed decode failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func restoreCache() {
        guard let directory = environment.cacheDirectory else { return }
        let file = directory.appendingPathComponent(Self.cacheFileName)
        guard let data = try? Data(contentsOf: file) else { return }
        if let feed = decode(data), !feed.products.isEmpty {
            state = .loaded(feed)
        } else {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.metaFileName))
        }
    }

    private func writeCache(_ data: Data) {
        guard let directory = environment.cacheDirectory else { return }
        do {
            try data.write(to: directory.appendingPathComponent(Self.cacheFileName), options: .atomic)
            let meta = ["fetchedAt": ISO8601DateFormatter().string(from: Date())]
            try JSONEncoder().encode(meta)
                .write(to: directory.appendingPathComponent(Self.metaFileName), options: .atomic)
        } catch {
            shopLogger.error("cache write failed: \(error.localizedDescription)")
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// 상품 이미지 로더. 전용 URLCache + 단일 요청(`.returnCacheDataElseLoad`)으로
/// 한 번 본 사진은 오프라인에서도 보여요. 이미지 파일명은 불변 규칙(교체 시 새 파일명).
final class ShopImageLoader: @unchecked Sendable {
    static let shared = ShopImageLoader(
        cache: URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024,
            directory: URL.cachesDirectory.appendingPathComponent("shop-images", isDirectory: true)
        ),
        allowsRemote: ShopEnvironment.current.allowsRemoteImages
    )

    /// 다운샘플 한 변: 176pt × 최대 화면 배율 3.
    private static let thumbnailSide: CGFloat = 176 * 3

    private let cache: URLCache
    private let session: URLSession
    private let allowsRemote: Bool
    private let cachePolicy: URLRequest.CachePolicy
    private let memory = NSCache<NSURL, UIImage>()

    init(cache: URLCache, allowsRemote: Bool, cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad) {
        self.cache = cache
        self.allowsRemote = allowsRemote
        self.cachePolicy = cachePolicy
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = cachePolicy
        session = URLSession(configuration: configuration)
    }

    func image(for url: URL) async -> UIImage? {
        if !allowsRemote && !url.isFileURL { return nil }
        if let cached = memory.object(forKey: url as NSURL) { return cached }

        let request = URLRequest(url: url, cachePolicy: cachePolicy)
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            cache.removeCachedResponse(for: request)
            return nil
        }
        guard let decoded = UIImage(data: data) else {
            // 깨진 본문(404 HTML 등)이 캐시에 영구 보존되지 않게.
            cache.removeCachedResponse(for: request)
            return nil
        }
        let side = Self.thumbnailSide
        let image = decoded.preparingThumbnail(of: CGSize(width: side, height: side)) ?? decoded
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}
