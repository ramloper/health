import Foundation
import SwiftData
import os

/// Opens the 1.1 store (`soejil-v2.store`). Before any container exists it removes the 1.0 store
/// (records were re-keyed, no migration) and, if the v2 store can't be opened, moves it aside
/// as `<name>.corrupt-<timestamp>` (never deletes it) and retries once.
struct StoreBootstrap {
    struct Result: Equatable {
        var legacyRemoved = false
        var corruptMoved = false
        var retried = false
    }

    /// UserDefaults key read by `RootView` to show a one-time notice.
    static let noticeKey = "store.notice"
    static let noticeReset = "reset"
    static let noticeCorrupt = "corrupt"

    /// 1.0 store location. Computed from a configuration only; no container is opened.
    static var defaultLegacyURL: URL { ModelConfiguration().url }

    static var defaultV2URL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("soejil-v2.store")
    }

    private static let logger = Logger(subsystem: "com.wooram.health", category: "store")

    static func makeContainer(
        legacyURL: URL = defaultLegacyURL,
        v2URL: URL = defaultV2URL,
        isDemo: Bool,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        now: Date = .init()
    ) throws -> (ModelContainer, Result) {
        let schema = Schema(versionedSchema: SchemaV2.self)
        var result = Result()

        if isDemo {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return (container, result)
        }

        // (1) 1.0 store: delete store + sidecars.
        let legacyFiles = storeFiles(legacyURL).filter { fileManager.fileExists(atPath: $0.path) }
        if !legacyFiles.isEmpty {
            for file in legacyFiles {
                try? fileManager.removeItem(at: file)
            }
            result.legacyRemoved = true
            logger.notice("bootstrap(legacyRemoved)")
        }

        // (2) Parent directory may not exist on a fresh install.
        try fileManager.createDirectory(at: v2URL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // (3) Open, or move aside and retry once.
        let configuration = ModelConfiguration(url: v2URL)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            moveAside(v2URL, fileManager: fileManager, now: now)
            result.corruptMoved = true
            result.retried = true
            logger.error("bootstrap(corruptMoved) \(String(describing: error), privacy: .private)")
            do {
                container = try ModelContainer(for: schema, configurations: configuration)
            } catch {
                logger.fault("bootstrap(retryFailed) \(String(describing: error), privacy: .private)")
                throw error
            }
        }

        if result.legacyRemoved {
            defaults.set(noticeReset, forKey: noticeKey)
        } else if result.corruptMoved {
            defaults.set(noticeCorrupt, forKey: noticeKey)
        }
        return (container, result)
    }

    /// The SQLite store and its `-shm` / `-wal` siblings.
    static func storeFiles(_ url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        return [url, directory.appendingPathComponent(name + "-shm"), directory.appendingPathComponent(name + "-wal")]
    }

    /// `X`, `X-shm`, `X-wal` → `X.corrupt-<ts>`, `X.corrupt-<ts>-shm`, `X.corrupt-<ts>-wal`.
    private static func moveAside(_ url: URL, fileManager: FileManager, now: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now)

        var base = url.appendingPathExtension("corrupt-\(stamp)")
        var suffix = 1
        while storeFiles(base).contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            base = url.appendingPathExtension("corrupt-\(stamp)-\(suffix)")
            suffix += 1
        }
        for (source, destination) in zip(storeFiles(url), storeFiles(base))
        where fileManager.fileExists(atPath: source.path) {
            try? fileManager.moveItem(at: source, to: destination)
        }
    }
}
