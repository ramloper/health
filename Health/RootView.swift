import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @Query private var profiles: [AthleteProfile]
    @Query(filter: #Predicate<TrainingCycle> { $0.isActive }) private var cycles: [TrainingCycle]
    @AppStorage(StoreBootstrap.noticeKey) private var storeNotice = ""

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
        .alert(storeNoticeText ?? "", isPresented: storeNoticeShown) {
            Button("확인", role: .cancel) { storeNotice = "" }
        }
        .onChange(of: theme.isDark) { _, isDark in
            Gym.applyChrome(isDark: isDark)
        }
    }

    private var storeNoticeText: String? {
        switch storeNotice {
        case StoreBootstrap.noticeReset: "기록 구조가 바뀌어 이전 기록은 초기화됐어요."
        case StoreBootstrap.noticeCorrupt: "저장소를 열 수 없어 새로 만들었어요. 이전 파일은 기기에 보관했어요."
        default: nil
        }
    }

    /// One-time store notice; dismissing clears the key. Never shown in `--demo`.
    private var storeNoticeShown: Binding<Bool> {
        Binding(
            get: { !HealthApp.isDemo && storeNoticeText != nil },
            set: { if !$0 { storeNotice = "" } }
        )
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
                    Tab("쇼핑", systemImage: "bag.fill", value: 4) {
                        ShopView()
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
                    ShopView()
                        .tabItem { Label("쇼핑", systemImage: "bag.fill") }
                        .tag(4)
                }
            }
        }
        .tint(Gym.text)
    }
}
