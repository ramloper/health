import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @Query private var profiles: [AthleteProfile]
    @Query(filter: #Predicate<TrainingCycle> { $0.isActive }) private var cycles: [TrainingCycle]

    var body: some View {
        Group {
            if let profile = profiles.first, profile.hasCompletedOnboarding {
                MainTabs(profile: profile, cycle: cycles.first)
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(Gym.accent)
        .task { seedIfNeeded() }
        .onChange(of: theme.isDark) { _, isDark in
            Gym.applyChrome(isDark: isDark)
        }
    }

    private func seedIfNeeded() {
        if profiles.isEmpty {
            context.insert(AthleteProfile())
        }
    }
}

struct MainTabs: View {
    @Bindable var profile: AthleteProfile
    var cycle: TrainingCycle?
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage("app.selectedTab") private var selectedTab = 0

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TabView(selection: $selectedTab) {
                    Tab("오늘", systemImage: "square.fill", value: 0) {
                        TodayView(profile: profile, cycle: cycle)
                            .id(cycle?.persistentModelID)
                    }
                    Tab("루틴", systemImage: "square.grid.2x2.fill", value: 1) {
                        CatalogView(profile: profile, cycle: cycle)
                    }
                    Tab("기록", systemImage: "chart.bar.fill", value: 2) {
                        HistoryView()
                    }
                    Tab("프로필", systemImage: "person.fill", value: 3) {
                        ProfileView(profile: profile, cycle: cycle)
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    TodayView(profile: profile, cycle: cycle)
                        .id(cycle?.persistentModelID)
                        .tabItem { Label("오늘", systemImage: "square.fill") }
                        .tag(0)
                    CatalogView(profile: profile, cycle: cycle)
                        .tabItem { Label("루틴", systemImage: "square.grid.2x2.fill") }
                        .tag(1)
                    HistoryView()
                        .tabItem { Label("기록", systemImage: "chart.bar.fill") }
                        .tag(2)
                    ProfileView(profile: profile, cycle: cycle)
                        .tabItem { Label("프로필", systemImage: "person.fill") }
                        .tag(3)
                }
            }
        }
        .tint(Gym.text)
    }
}
