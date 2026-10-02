import SwiftUI
import SwiftData
import UIKit

struct ProfileView: View {
    @Bindable var profile: AthleteProfile
    var cycle: TrainingCycle?
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var metronome = GymMetronome.shared
    @State private var editingLift: LiftPad?
    @State private var showMetronome = false
    @State private var showRest = false
    @State private var showGymBrands = false
    @State private var exportURL: ExportFile?
    @State private var exportError: String?

    private struct LiftPad: Identifiable {
        var id: String { name }
        var name: String
        var value: Double
        var apply: (Double) -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("내 정보")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .tracking(-0.4)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("1RM")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Gym.text)
                        Spacer()
                        Text("눌러서 바꾸기")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Gym.faint)
                    }
                    .padding(.horizontal, 4)

                    GymCard(padding: 0) {
                        VStack(spacing: 0) {
                            liftRow("벤치", kg: profile.bench1RM) { editingLift = LiftPad(name: "벤치", value: profile.bench1RM, apply: setLift { $0.bench1RM = $1 }) }
                            liftRow("스쿼트", kg: profile.squat1RM) { editingLift = LiftPad(name: "스쿼트", value: profile.squat1RM, apply: setLift { $0.squat1RM = $1 }) }
                            liftRow("데드", kg: profile.dead1RM) { editingLift = LiftPad(name: "데드", value: profile.dead1RM, apply: setLift { $0.dead1RM = $1 }) }
                            liftRow("OHP", kg: profile.ohp1RM) { editingLift = LiftPad(name: "OHP", value: profile.ohp1RM, apply: setLift { $0.ohp1RM = $1 }) }
                        }
                        .padding(.horizontal, 20)
                    }

                    Text("1RM을 바꾸면 5/3/1·nSuns에서 해당 운동의 TM만 다시 계산돼요. 6일 근비대처럼 세트 무게로 진행하는 프로그램은 그대로예요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Gym.tabIdle)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("설정")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.text)
                        .padding(.horizontal, 4)

                    GymCard(padding: 0) {
                        VStack(spacing: 0) {
                            settingRow("화면", value: theme.isDark ? "다크 ›" : "라이트 ›") {
                                theme.isDark.toggle()
                                Gym.applyChrome(isDark: theme.isDark)
                            }
                            settingRow("기본 휴식 시간", value: restLabel + " ›") {
                                showRest = true
                            }
                            settingRow("메트로놈 BPM", value: "\(metronome.bpm) ›") {
                                showMetronome = true
                            }
                            settingRow("우리 헬스장 브랜드", value: "\(profile.gymBrandIds.count)개 ›") {
                                showGymBrands = true
                            }
                            .accessibilityValue("\(profile.gymBrandIds.count)개")
                            .accessibilityIdentifier("gym-brands-row")
                        }
                        .padding(.horizontal, 20)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("데이터")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.text)
                        .padding(.horizontal, 4)
                    GymCard(padding: 0) {
                        VStack(spacing: 0) {
                            settingRow("기록 내보내기 (JSON)", value: "›", action: exportData)
                        }
                        .padding(.horizontal, 20)
                    }
                    Text("모든 기록은 이 폰에만 저장돼요. 기기를 바꾸기 전에 내보내 두세요.")
                        .font(.system(size: 12))
                        .foregroundStyle(Gym.tabIdle)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Gym.bg.ignoresSafeArea())
        .sheet(item: $editingLift) { lift in
            NumberPadSheet(title: "\(lift.name) 1RM", unit: "kg", allowsDecimal: true, initial: lift.value) { value in
                lift.apply(max(20, min(400, value)))
            }
        }
        .sheet(isPresented: $showMetronome) {
            MetronomeSettingsSheet(metronome: metronome, stopsOnDismiss: true)
        }
        .sheet(isPresented: $showRest) {
            RestDurationSheet()
        }
        .sheet(isPresented: $showGymBrands) {
            GymBrandsSheet(profile: profile)
        }
        .sheet(item: $exportURL) { file in
            ShareSheet(items: [file.url])
        }
        .alert("내보내기 실패", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("확인", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func setLift(_ mutate: @escaping (AthleteProfile, Double) -> Void) -> (Double) -> Void {
        // Returned closure runs from the number pad; sync TMs once the profile changed.
        { value in
            let previousProfile = profile.inputs
            mutate(profile, value)
            SessionService.syncTrainingMaxes(cycle: cycle, profile: profile.inputs, previousProfile: previousProfile)
            try? context.save()
        }
    }

    private func exportData() {
        do {
            let data = try SessionService.exportJSON(context: context)
            let stamp = Date.now.formatted(.iso8601.year().month().day())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-log-\(stamp).json")
            try data.write(to: url, options: .atomic)
            exportURL = ExportFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var restLabel: String {
        let s = theme.restSeconds
        let m = s / 60
        let r = s % 60
        if r == 0 { return "\(m)분" }
        return "\(m)분 \(r)초"
    }

    private func liftRow(_ title: String, kg: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Gym.text)
                Spacer()
                HStack(spacing: 8) {
                    (Text(kg.gymKg).font(.system(size: 18, weight: .bold).monospacedDigit())
                     + Text("kg").font(.system(size: 13, weight: .medium)))
                        .foregroundStyle(Gym.text)
                    Text("›")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Gym.tabIdle)
                }
            }
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private func settingRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Gym.text)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Gym.faint)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ExportFile: Identifiable {
    var url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
