import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \PersonalRecord.kg, order: .reverse) private var prs: [PersonalRecord]
    @Query(sort: \CustomRoutine.updatedAt, order: .reverse) private var customs: [CustomRoutine]
    @ObservedObject private var theme = ThemeStore.shared
    @State private var selectedSession: WorkoutSession?
    @State private var pendingDeleteSession: WorkoutSession?
    @State private var pendingDeletePR: PersonalRecord?
    @State private var showAllPRs = false
    private let prPreviewCount = 6

    private var visiblePRs: [PersonalRecord] {
        showAllPRs ? prs : Array(prs.prefix(prPreviewCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("기록")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .tracking(-0.4)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("PR")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.text)
                        .padding(.horizontal, 4)
                    GymCard(padding: 0) {
                        if prs.isEmpty {
                            Text("아직 기록이 없어요")
                                .foregroundStyle(Gym.muted)
                                .padding(20)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(visiblePRs) { pr in
                                    HStack {
                                        Text(displayName(pr.liftId))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Gym.text)
                                        Spacer()
                                        (Text(pr.kg.gymKg).font(.system(size: 18, weight: .bold).monospacedDigit())
                                         + Text("kg").font(.system(size: 13, weight: .medium)))
                                            .foregroundStyle(Gym.text)
                                    }
                                    .padding(.vertical, 16)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        Button("이 PR 삭제", role: .destructive) { pendingDeletePR = pr }
                                    }
                                }
                                if prs.count > prPreviewCount {
                                    Button {
                                        withAnimation { showAllPRs.toggle() }
                                    } label: {
                                        Text(showAllPRs ? "접기" : "전체 보기 (\(prs.count))")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Gym.accent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("세션")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.text)
                        .padding(.horizontal, 4)
                    if sessions.isEmpty {
                        Text("완료한 세션이 없어요")
                            .foregroundStyle(Gym.muted)
                            .padding(.horizontal, 4)
                    } else {
                        GymCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(sessions) { session in
                                    Button {
                                        selectedSession = session
                                    } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dayTitle(session))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Gym.text)
                                            .lineLimit(2)
                                        if let summary = exerciseSummary(session) {
                                            Text(summary)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Gym.muted)
                                                .lineLimit(1)
                                        }
                                        Text(session.date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))))
                                            .font(.system(size: 13))
                                            .foregroundStyle(Gym.faint)
                                        Text(setLabel(session))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Gym.accent)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("세션 삭제", role: .destructive) { pendingDeleteSession = session }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Gym.bg.ignoresSafeArea())
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(session: session, title: dayTitle(session))
        }
        .alert("이 세션을 삭제할까요?", isPresented: Binding(
            get: { pendingDeleteSession != nil },
            set: { if !$0 { pendingDeleteSession = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let session = pendingDeleteSession {
                    context.delete(session)
                    try? context.save()
                }
                pendingDeleteSession = nil
            }
            Button("취소", role: .cancel) { pendingDeleteSession = nil }
        } message: {
            Text("세트 기록이 지워져요. 이미 올라간 작업 무게나 PR은 되돌리지 않아요.")
        }
        .alert("이 PR을 삭제할까요?", isPresented: Binding(
            get: { pendingDeletePR != nil },
            set: { if !$0 { pendingDeletePR = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let pr = pendingDeletePR {
                    context.delete(pr)
                    try? context.save()
                }
                pendingDeletePR = nil
            }
            Button("취소", role: .cancel) { pendingDeletePR = nil }
        } message: {
            Text("다음에 그 운동을 완료하면 다시 기록돼요.")
        }
    }

    /// PRs are keyed by guide title now; the first four cover records written by older builds.
    private func displayName(_ id: String) -> String {
        switch id {
        case "bench": return "벤치프레스"
        case "squat": return "스쿼트"
        case "deadlift", "dead": return "데드리프트"
        case "ohp", "press": return "오버헤드 프레스 (OHP)"
        default: return id.isEmpty ? "운동" : id
        }
    }

    private func schedule(for session: WorkoutSession) -> ProgramSchedule? {
        if let schedule = session.cycle?.resolvedSchedule() {
            return schedule
        }
        if let custom = customs.first(where: { $0.programId == session.programId }) {
            return custom.resolvedSchedule()
        }
        return ProgramCatalog.load(session.programId)
    }

    private func dayTitle(_ session: WorkoutSession) -> String {
        let schedule = schedule(for: session)
        let dayName = schedule?.days.first(where: { $0.id == session.dayId })?.name
        if let program = schedule?.name, let dayName {
            return "\(program) · \(dayName)"
        }
        if let dayName { return dayName }
        if let program = schedule?.name { return program }
        return "운동"
    }

    private func exerciseSummary(_ session: WorkoutSession) -> String? {
        var names: [String] = []
        for set in session.sets.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if !set.exerciseName.isEmpty, !names.contains(set.exerciseName) {
                names.append(set.exerciseName)
            }
        }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " · ")
    }

    private func setLabel(_ session: WorkoutSession) -> String {
        let done = session.sets.filter(\.completed).count
        let total = session.sets.count
        if done > 0 { return "\(done)세트 완료" }
        if total > 0 { return "\(total)세트 기록" }
        return "세트 기록 없음"
    }
}

struct SessionDetailSheet: View {
    var session: WorkoutSession
    var title: String
    @Environment(\.dismiss) private var dismiss

    private var groups: [(name: String, sets: [SetLog])] {
        var result: [(name: String, sets: [SetLog])] = []
        for set in session.sets.sorted(by: { $0.orderIndex < $1.orderIndex }) {
            if let last = result.indices.last, result[last].name == set.exerciseName {
                result[last].sets.append(set)
            } else {
                result.append((set.exerciseName, [set]))
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ko_KR"))))
                        .font(.system(size: 13))
                        .foregroundStyle(Gym.faint)
                        .padding(.horizontal, 4)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        GymCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Gym.text)
                                ForEach(group.sets) { set in
                                    HStack {
                                        Text(setLabel(set))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Gym.muted)
                                            .frame(width: 44, alignment: .leading)
                                        Text("\(set.kg.gymKg)kg × \(set.reps)회")
                                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(set.completed ? Gym.text : Gym.faint)
                                        Spacer()
                                        Text(set.completed ? "완료" : "미완료")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(set.completed ? Gym.accent : Gym.faint)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Gym.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Gym.muted)
                }
            }
        }
        .presentationBackground(Gym.bg)
    }

    private func setLabel(_ set: SetLog) -> String {
        if set.isWarmup { return "WU" }
        if set.isBBB { return "BBB" }
        if set.isAMRAP { return "+" }
        return "\(set.setIndex + 1)세트"
    }
}
