import SwiftUI
import SwiftData

@main
struct HealthApp: App {
    private static let schema = Schema([
        AthleteProfile.self,
        TrainingCycle.self,
        WorkoutSession.self,
        SetLog.self,
        PersonalRecord.self,
        CustomRoutine.self
    ])

    /// `--demo` (screenshot runs) uses a throwaway in-memory store seeded with sample data.
    private static let isDemo = CommandLine.arguments.contains("--demo")

    private let container: ModelContainer

    init() {
        Gym.applyChrome()
        let config = ModelConfiguration(isStoredInMemoryOnly: Self.isDemo)
        do {
            container = try ModelContainer(for: Self.schema, configurations: config)
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
