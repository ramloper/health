import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [AthleteProfile]
    @State private var bench = 75.0
    @State private var squat = 110.0
    @State private var dead = 120.0
    @State private var ohp = 60.0
    @State private var pad: Pad?

    private struct Pad: Identifiable {
        var id: String { name }
        var name: String
        var value: Double
        var apply: (Double) -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("쇠질")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .tracking(-0.6)
                Text("로그인 없이 이 폰에만 저장해요.\n1RM만 넣고 바로 오늘 운동을 고르세요.")
                    .foregroundStyle(Gym.muted)
            }
            GymCard(padding: 0) {
                VStack(spacing: 0) {
                    liftRow("벤치", value: $bench)
                    liftRow("스쿼트", value: $squat)
                    liftRow("데드", value: $dead)
                    liftRow("OHP", value: $ohp)
                }
                .padding(.horizontal, 20)
            }
            Spacer()
            GymCTA(title: "시작하기", action: start)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Gym.bg.ignoresSafeArea())
        .sheet(item: $pad) { item in
            NumberPadSheet(title: "\(item.name) 1RM", unit: "kg", allowsDecimal: true, initial: item.value) { value in
                item.apply(max(20, min(400, value)))
            }
        }
    }

    private func liftRow(_ title: String, value: Binding<Double>) -> some View {
        Button {
            pad = Pad(name: title, value: value.wrappedValue) { value.wrappedValue = $0 }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Gym.text)
                Spacer()
                (Text(value.wrappedValue.gymKg).font(.system(size: 18, weight: .bold).monospacedDigit())
                 + Text("kg").font(.system(size: 13, weight: .medium)))
                    .foregroundStyle(Gym.text)
                Text("›")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Gym.tabIdle)
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private func start() {
        let profile = profiles.first ?? AthleteProfile()
        if profiles.isEmpty { context.insert(profile) }
        profile.bench1RM = bench
        profile.squat1RM = squat
        profile.dead1RM = dead
        profile.ohp1RM = ohp
        profile.hasCompletedOnboarding = true
        profile.preferredProgramId = Hypertrophy6DayEngine.id
        if let schedule = ProgramCatalog.load(Hypertrophy6DayEngine.id) {
            _ = SessionService.startCycle(context: context, schedule: schedule, profile: profile.inputs)
        }
        try? context.save()
    }
}
