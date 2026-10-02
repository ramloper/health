import SwiftUI
import SwiftData

@main
struct HealthApp: App {
    /// `--demo` (screenshot runs) uses a throwaway in-memory store seeded with sample data.
    static let isDemo = CommandLine.arguments.contains("--demo")

    private let container: ModelContainer

    init() {
        Gym.applyChrome()
        do {
            container = try StoreBootstrap.makeContainer(isDemo: Self.isDemo).0
        } catch {
            fatalError("ModelContainer: \(error)")
        }
        #if DEBUG
        if Self.isDemo {
            UserDefaults.standard.set(0, forKey: "app.selectedTab")
            DemoSeed.seed(container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ThemeStore.shared)
        }
        .modelContainer(container)
    }
}
