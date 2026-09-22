import SwiftUI
import SwiftData

struct CatalogView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @Bindable var profile: AthleteProfile
    var cycle: TrainingCycle?

    @Query(sort: \CustomRoutine.updatedAt, order: .reverse) private var customs: [CustomRoutine]

    @State private var pending: ProgramSchedule?
    @State private var builder: BuilderLaunch?
    @State private var pendingDelete: CustomRoutine?
    @State private var pendingRestart: ProgramSchedule?
    @State private var startAfterBuilder: ProgramSchedule?

    private struct BuilderLaunch: Identifiable {
        let id = UUID()
        var existing: CustomRoutine?
        var seed: ProgramSchedule
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("루틴")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .tracking(-0.4)
                    .padding(.top, 8)

                Button(action: openCreate) {
                    HStack(spacing: 14) {
                        Text("+")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Gym.accent)
                            .frame(width: 44, height: 44)
                            .background(Gym.accentSoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("새 루틴 만들기")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Gym.text)
                            Text("요일과 운동을 직접 넣어요")
                                .font(.system(size: 13))
                                .foregroundStyle(Gym.faint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Gym.card)
                    .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
                }
                .buttonStyle(.plain)

                if !customs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("내 루틴")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Gym.text)
                            .padding(.horizontal, 4)
                        VStack(spacing: 10) {
                            ForEach(customs) { routine in
                                if let schedule = routine.resolvedSchedule() {
                                    customRow(routine, schedule: schedule)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("프로그램")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Gym.text)
                        Spacer()
                        Text("탭해서 내 루틴으로 복사")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Gym.faint)
                    }
                    .padding(.horizontal, 4)

                    GymCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(ProgramCatalog.loadAll(), id: \.id) { schedule in
                                programRow(schedule)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(Gym.bg.ignoresSafeArea())
        .sheet(item: $pending) { schedule in
            DayPickerSheet(
                schedule: schedule,
                selectedId: cycle?.programId == schedule.id ? (cycle?.nextDayId ?? "") : ""
            ) { day in
                start(schedule, day: day.id)
            }
        }
        .sheet(item: $builder, onDismiss: presentDayPickerIfNeeded) { launch in
            RoutineBuilderView(
                existing: launch.existing,
                seed: launch.seed,
                cycle: cycle
            ) { schedule, startNow in
                if startNow { startAfterBuilder = schedule }
                builder = nil
            }
        }
        .alert("이 루틴을 삭제할까요?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let pendingDelete {
                    context.delete(pendingDelete)
                    try? context.save()
                }
                pendingDelete = nil
            }
            Button("취소", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("오늘 진행 중인 운동은 그대로 두고, 저장된 루틴만 지워요.")
        }
        .alert("처음부터 다시 시작할까요?", isPresented: Binding(
            get: { pendingRestart != nil },
            set: { if !$0 { pendingRestart = nil } }
        )) {
            Button("다시 시작", role: .destructive) {
                if let schedule = pendingRestart {
                    SessionService.startCycle(context: context, schedule: schedule, profile: profile.inputs, restart: true)
                    try? context.save()
                }
                pendingRestart = nil
            }
            Button("취소", role: .cancel) { pendingRestart = nil }
        } message: {
            Text("작업 무게와 TM, 주차가 시작값으로 돌아가요. 완료한 세션 기록은 남아요.")
        }
    }

    private func customRow(_ routine: CustomRoutine, schedule: ProgramSchedule) -> some View {
        let days = DayCursor.trainingDays(in: schedule).count
        let inUse = cycle?.programId == schedule.id
        return Button {
            openEdit(routine)
        } label: {
            HStack(spacing: 14) {
                Text("\(days)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .frame(width: 40, height: 40)
                    .background(Gym.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Gym.text)
                    Text("주 \(days)일 · \(schedule.kindLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Gym.faint)
                }
                Spacer(minLength: 4)
            }
            .padding(16)
            .background(Gym.card)
            .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Gym.radius, style: .continuous)
                    .stroke(inUse ? Gym.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if inUse {
                Button("처음부터 다시 시작", role: .destructive) { pendingRestart = schedule }
            }
            Button("삭제", role: .destructive) { pendingDelete = routine }
        }
    }

    private func programRow(_ schedule: ProgramSchedule) -> some View {
        let days = DayCursor.trainingDays(in: schedule).count
        return Button {
            openCopy(schedule)
        } label: {
            HStack(spacing: 14) {
                Text("\(days)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Gym.text)
                    .frame(width: 40, height: 40)
                    .background(Gym.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Gym.text)
                    Text("주 \(days)일 · \(schedule.kindLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Gym.faint)
                }
                Spacer()
                if cycle?.programId == schedule.id {
                    inUseBadge
                } else {
                    Text("›")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Gym.tabIdle)
                }
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(cycle?.programId == schedule.id ? "요일 고르기" : "바로 시작") {
                pending = schedule
            }
            Button("내 루틴으로 복사") { openCopy(schedule) }
            if cycle?.programId == schedule.id {
                Button("처음부터 다시 시작", role: .destructive) { pendingRestart = schedule }
            }
        }
    }

    private var inUseBadge: some View {
        Text("사용 중")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Gym.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Gym.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openCreate() {
        builder = BuilderLaunch(existing: nil, seed: .makeCustom())
    }

    private func openEdit(_ routine: CustomRoutine) {
        builder = BuilderLaunch(
            existing: routine,
            seed: routine.resolvedSchedule() ?? .makeCustom()
        )
    }

    private func openCopy(_ schedule: ProgramSchedule) {
        builder = BuilderLaunch(existing: nil, seed: .copiedAsCustom(from: schedule))
    }

    private func presentDayPickerIfNeeded() {
        guard let next = startAfterBuilder else { return }
        startAfterBuilder = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            pending = next
        }
    }

    /// Same program as the active cycle: keeps progress and just moves the day.
    private func start(_ schedule: ProgramSchedule, day: String) {
        profile.preferredProgramId = schedule.id
        SessionService.startCycle(
            context: context,
            schedule: schedule,
            profile: profile.inputs,
            startingDayId: day
        )
        try? context.save()
        pending = nil
    }
}
