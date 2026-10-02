import SwiftUI
import SwiftData
import UserNotifications

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var metronome = GymMetronome.shared
    @Bindable var profile: AthleteProfile
    var cycle: TrainingCycle?

    @State private var isWorkingOut = false
    @State private var draft: [CompletedSet] = []
    @State private var hints: [String: (kg: Double, reps: Int)] = [:]
    @State private var restEndsAt: Date?
    @State private var restTick = Date()
    @State private var timer: Timer?
    @State private var showDayPicker = false
    @State private var dayEditor: DayEditor?
    @State private var guideTarget: GuideTarget?
    @State private var pad: PadTarget?
    @State private var focusGroupId: String?
    @State private var showMetronome = false
    @State private var showRest = false
    @State private var showExitDialog = false
    @State private var showEmptyFinishAlert = false

    private struct DayEditor: Identifiable {
        var id: String
        var dayName: String
        var exercises: [ScheduleExercise]
    }

    private struct GuideTarget: Identifiable {
        var id: String { name + idKey }
        var name: String
        var idKey: String
    }

    private struct PadTarget: Identifiable {
        var id: String { "\(kind)-\(exerciseId)-\(setIndex)" }
        var kind: Kind
        var exerciseId: String
        var setIndex: Int
        var current: Double
        enum Kind { case kg, reps }
    }

    /// Seconds left in the rest period, derived from a wall-clock deadline so
    /// locking the phone or switching apps does not pause the countdown.
    private var timerRemaining: Int {
        _ = restTick
        guard let restEndsAt else { return 0 }
        return max(0, Int(ceil(restEndsAt.timeIntervalSinceNow)))
    }

    var body: some View {
        Group {
            if let cycle, let schedule = cycle.resolvedSchedule() {
                if isWorkingOut {
                    sessionScroll(cycle: cycle, schedule: schedule)
                } else {
                    lobby(cycle: cycle, schedule: schedule)
                }
            } else {
                emptyState
            }
        }
        .background(Gym.bg.ignoresSafeArea())
        .onAppear { restoreDraftIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { tickRest() }
        }
        .onChange(of: draft) { _, sets in
            guard isWorkingOut, let cycle else { return }
            cycle.saveDraft(sets, dayId: cycle.nextDayId)
            try? context.save()
        }
        .onDisappear {
            metronome.isOn = false
        }
        .sheet(isPresented: $showMetronome) {
            MetronomeSettingsSheet(metronome: metronome)
        }
        .sheet(isPresented: $showRest) {
            RestCountdownSheet(remaining: timerRemaining, onAdjust: adjustRest) {
                skipRest()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(Gym.accent)
            Text("루틴을 먼저 고르세요")
                .font(.headline)
                .foregroundStyle(Gym.text)
            Text("루틴 탭에서 프로그램을 고르거나 내 루틴을 만들면 오늘 운동이 열려요.")
                .font(.subheadline)
                .foregroundStyle(Gym.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Gym.bg)
    }

    // MARK: Lobby

    private func lobby(cycle: TrainingCycle, schedule: ProgramSchedule) -> some View {
        let day = schedule.days.first(where: { $0.id == cycle.nextDayId })
        let dayName = day?.name ?? "운동"
        let exercises = day?.exercises ?? []
        let setCount = exercises.reduce(0) { $0 + $1.sets }
        let canEdit = !EngineRegistry.usesTrainingMax(cycle.programId)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        (Text("오늘은 ") + Text(dayName).foregroundColor(Gym.accent) + Text(" 하는 날이에요"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Gym.text)
                            .tracking(-0.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Button { showDayPicker = true } label: {
                            HStack(spacing: 4) {
                                Text("다른 요일로 바꾸기")
                                Text("›").foregroundStyle(Gym.tabIdle)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Gym.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Gym.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(.top, 8)

                    GymCard(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("운동 \(exercises.count)개 · \(setCount)세트")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Gym.text)
                                Spacer()
                                if canEdit {
                                    Button("수정") {
                                        dayEditor = DayEditor(id: cycle.nextDayId, dayName: dayName, exercises: exercises)
                                    }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Gym.accent)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 6)

                            if !canEdit {
                                Text("이 프로그램은 1RM 기반 TM으로 세트가 정해져요. 프로필에서 1RM을 바꾸면 반영돼요.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Gym.faint)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 6)
                            }
                            if exercises.isEmpty {
                                Text("운동이 없어요. 수정에서 추가하세요.")
                                    .font(.subheadline)
                                    .foregroundStyle(Gym.muted)
                                    .padding(20)
                            }
                            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, ex in
                                Button {
                                    guideTarget = GuideTarget(name: ex.name, idKey: ex.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        GymIndexBadge(text: "\(index + 1)")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ex.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Gym.text)
                                            Text("\(ex.sets)세트 \(ex.repLabel)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Gym.faint)
                                        }
                                        Spacer()
                                        if let kg = workingKg(cycle: cycle, ex: ex) {
                                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                                Text(kg.gymKg)
                                                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                                                    .foregroundStyle(Gym.text)
                                                Text("kg")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(Gym.faint)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("lobby-exercise-\(index)")
                            }
                            Color.clear.frame(height: 6)
                        }
                    }

                    GymCard(padding: 20) {
                        MetronomeSettingsView(metronome: metronome)
                    }
                    .environment(\.colorScheme, theme.isDark ? .dark : .light)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            GymCTA(title: "운동 시작하기", enabled: !exercises.isEmpty) {
                startWorkout(cycle: cycle, schedule: schedule)
            }
            .accessibilityIdentifier("start-workout")
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Gym.bg)
        .sheet(isPresented: $showDayPicker) {
            DayPickerSheet(schedule: schedule, selectedId: cycle.nextDayId) { day in
                SessionService.selectDay(cycle: cycle, dayId: day.id)
                try? context.save()
            }
        }
        .sheet(item: $dayEditor) { editor in
            ExerciseEditorView(dayName: editor.dayName, exercises: editor.exercises) { updated in
                SessionService.replaceDayExercises(cycle: cycle, dayId: editor.id, exercises: updated)
                SessionService.syncCustomTemplate(context: context, cycle: cycle)
                try? context.save()
            }
        }
        .sheet(item: $guideTarget) { target in
            guideSheet(target)
        }
    }

    // MARK: Session

    private func sessionScroll(cycle: TrainingCycle, schedule: ProgramSchedule) -> some View {
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile.inputs)
        let groups = TodayController.grouped(rows)
        let dayName = schedule.days.first(where: { $0.id == cycle.nextDayId })?.name ?? "운동"
        let doneCount = draft.filter(\.completed).count
        let focusId = focusGroupId ?? groups.first?.first?.groupId
        let focusIndex = groups.firstIndex(where: { $0.first?.groupId == focusId }) ?? 0
        let current = groups.indices.contains(focusIndex) ? groups[focusIndex] : []
        let next = groups.indices.contains(focusIndex + 1) ? groups[focusIndex + 1] : nil
        let unticked = current.filter { !isDone($0) }
        let primary = primaryAction(unticked: unticked.count, hasNext: next != nil)
        return VStack(spacing: 0) {
            HStack {
                Button {
                    requestExit(cycle: cycle)
                } label: {
                    Text("‹ 나가기")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Gym.muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Gym.accent).frame(width: 8, height: 8)
                    Text("\(dayName) · \(doneCount)/\(rows.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Gym.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Gym.card)
                .clipShape(Capsule())
                Spacer()
                Button {
                    showMetronome = true
                } label: {
                    Text("♩ \(metronome.bpm)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(metronome.isOn ? Gym.accent : Gym.faint)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 16) {
                    if !current.isEmpty {
                        sessionExerciseCard(current)
                    }
                    if let next, let first = next.first {
                        Button {
                            focusGroupId = first.groupId
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(first.exerciseName)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Gym.text)
                                    Text("\(next.count)세트 \(repRange(next))")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Gym.faint)
                                }
                                Spacer()
                                Text("다음 ›")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Gym.faint)
                            }
                            .padding(20)
                            .background(Gym.card)
                            .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
                            .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("휴식")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Gym.faint)
                    Text(timerRemaining > 0 ? clock(timerRemaining) : clock(theme.restSeconds))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(Gym.text)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Gym.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    if timerRemaining > 0 {
                        showRest = true
                    }
                }

                Button {
                    switch primary {
                    case .completeSets:
                        for set in unticked { markDone(set) }
                        startRest()
                    case .nextExercise:
                        focusGroupId = next?.first?.groupId
                    case .finish:
                        requestFinish(cycle: cycle, schedule: schedule, rows: rows)
                    }
                } label: {
                    Text(primary.title(unticked: unticked.count))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Gym.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Gym.bg)
        .onAppear {
            if focusGroupId == nil { focusGroupId = rows.first?.groupId }
        }
        .onChange(of: cycle.nextDayId) { _, _ in
            let nextRows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile.inputs)
            seedDraft(nextRows)
            focusGroupId = nextRows.first?.groupId
        }
        .sheet(item: $guideTarget) { target in
            guideSheet(target)
        }
        .sheet(item: $pad) { target in
            NumberPadSheet(
                title: target.kind == .kg ? "무게" : "횟수",
                unit: target.kind == .kg ? "kg" : "회",
                allowsDecimal: target.kind == .kg,
                initial: target.current
            ) { value in
                if let idx = draft.firstIndex(where: { $0.exerciseId == target.exerciseId && $0.setIndex == target.setIndex }) {
                    if target.kind == .kg {
                        draft[idx].kg = min(500, value)
                    } else {
                        draft[idx].reps = min(50, Int(value.rounded()))
                    }
                }
            }
        }
        .confirmationDialog("운동을 나갈까요?", isPresented: $showExitDialog, titleVisibility: .visible) {
            Button("지금까지 기록 저장하고 끝내기") {
                finish(cycle: cycle, schedule: schedule, rows: rows)
            }
            Button("기록 버리고 나가기", role: .destructive) {
                discard(cycle: cycle)
            }
            Button("계속하기", role: .cancel) {}
        } message: {
            Text("완료한 \(doneCount)세트가 있어요.")
        }
        .alert("완료한 세트가 없어요", isPresented: $showEmptyFinishAlert) {
            Button("기록 없이 나가기", role: .destructive) { discard(cycle: cycle) }
            Button("취소", role: .cancel) {}
        } message: {
            Text("세트 오른쪽 동그라미를 눌러야 완료로 기록돼요. 지금 나가면 진행 상황은 바뀌지 않아요.")
        }
    }

    private enum PrimaryAction {
        case completeSets, nextExercise, finish

        func title(unticked: Int) -> String {
            switch self {
            case .completeSets: return "\(unticked)세트 완료"
            case .nextExercise: return "다음 운동 ›"
            case .finish: return "세션 완료"
            }
        }
    }

    private func primaryAction(unticked: Int, hasNext: Bool) -> PrimaryAction {
        if unticked > 0 { return .completeSets }
        return hasNext ? .nextExercise : .finish
    }

    private func guideSheet(_ target: GuideTarget) -> some View {
        ExerciseGuideSheet(
            name: target.name,
            id: target.idKey,
            last: SessionService.lastHint(context: context, exerciseId: target.idKey, exerciseName: target.name),
            prKg: SessionService.personalRecordKg(context: context, exerciseId: target.idKey, exerciseName: target.name),
            e1rm: mappedOneRM(name: target.name)
        )
    }

    private func sessionExerciseCard(_ group: [PrescribedSet]) -> some View {
        let first = group[0]
        let hint = hints[first.exerciseId]
        return GymCard(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(first.exerciseName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Gym.text)
                        Text("목표 \(repRange(group))")
                            .font(.system(size: 13))
                            .foregroundStyle(Gym.faint)
                    }
                    Spacer()
                    Button {
                        guideTarget = GuideTarget(name: first.exerciseName, idKey: first.exerciseId)
                    } label: {
                        Text("i")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Gym.faint)
                            .frame(width: 28, height: 28)
                            .background(Gym.elevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 8) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { offset, row in
                        setRow(row, displayIndex: offset)
                    }
                }
                .padding(.top, 16)
                Text(hintText(hint))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0x6B7684))
                    .padding(.top, 12)
            }
        }
    }

    private func setRow(_ row: PrescribedSet, displayIndex: Int) -> some View {
        let idx = draft.firstIndex(where: { $0.exerciseId == row.exerciseId && $0.setIndex == row.setIndex })
        let done = idx.flatMap { draft[$0].completed } ?? false
        let kg = idx.map { draft[$0].kg } ?? row.kg
        let reps = idx.map { draft[$0].reps } ?? row.reps
        let chipBg = done ? Gym.card : Gym.elevated
        let chipFg = done ? Gym.faint : Gym.text
        return HStack(spacing: 8) {
            Text(label(row, displayIndex: displayIndex))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? Gym.faint : Gym.muted)
                .frame(width: 44, alignment: .leading)
            Button {
                if let idx {
                    pad = PadTarget(kind: .kg, exerciseId: row.exerciseId, setIndex: row.setIndex, current: draft[idx].kg)
                }
            } label: {
                (Text(kg.gymKg).font(.system(size: 18, weight: .bold).monospacedDigit())
                 + Text(" kg").font(.system(size: 12, weight: .medium)))
                    .foregroundStyle(chipFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("무게 \(kg.gymKg)kg")
            Button {
                if let idx {
                    pad = PadTarget(kind: .reps, exerciseId: row.exerciseId, setIndex: row.setIndex, current: Double(draft[idx].reps))
                }
            } label: {
                (Text("\(reps)").font(.system(size: 18, weight: .bold).monospacedDigit())
                 + Text(" 회").font(.system(size: 12, weight: .medium)))
                    .foregroundStyle(chipFg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(chipBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("횟수 \(reps)회")
            Button {
                if let idx {
                    draft[idx].completed.toggle()
                    if draft[idx].completed { startRest() }
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Gym.accent, lineWidth: 2)
                        .background(Circle().fill(done ? Gym.accent : Color.clear))
                    if done {
                        Text("✓")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 30, height: 30)
                .padding(6)
                // A stroked circle is only hittable on its 2pt ring; make the whole disc (plus margin) tappable.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "세트 완료됨" : "세트 완료로 표시")
        }
        .opacity(row.isWarmup && !done ? 0.75 : 1)
    }

    // MARK: Helpers

    private func isDone(_ row: PrescribedSet) -> Bool {
        draft.first(where: { $0.exerciseId == row.exerciseId && $0.setIndex == row.setIndex })?.completed == true
    }

    private func markDone(_ row: PrescribedSet) {
        if let idx = draft.firstIndex(where: { $0.exerciseId == row.exerciseId && $0.setIndex == row.setIndex }) {
            draft[idx].completed = true
        }
    }

    private func workingKg(cycle: TrainingCycle, ex: ScheduleExercise) -> Double? {
        cycle.state.workingKg[ex.id] ?? ex.seedKg
    }

    private func repRange(_ group: [PrescribedSet]) -> String {
        guard let first = group.first else { return "0회" }
        let reps = Set(group.map(\.reps))
        if reps.count > 1, let lo = reps.min(), let hi = reps.max() {
            return "\(lo)~\(hi)회"
        }
        if let lo = first.repMin, lo < first.reps {
            return "\(lo)~\(first.reps)회"
        }
        return "\(first.reps)회"
    }

    private func hintText(_ hint: (kg: Double, reps: Int)?) -> String {
        if let hint {
            return "숫자를 누르면 키패드가 올라와요 · 지난 세션 \(hint.kg.gymKg)kg × \(hint.reps)회"
        }
        return "숫자를 누르면 키패드가 올라와요"
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func mappedOneRM(name: String) -> Double? {
        let n = name
        if n.contains("벤치") { return profile.bench1RM }
        if n.contains("스쿼트") { return profile.squat1RM }
        if n.contains("데드") { return profile.dead1RM }
        if n.contains("오버헤드") || n.contains("OHP") { return profile.ohp1RM }
        return nil
    }

    private func label(_ row: PrescribedSet, displayIndex: Int) -> String {
        if row.isWarmup { return "WU" }
        if row.isBBB { return "BBB" }
        if row.isAMRAP { return "+" }
        return "\(displayIndex + 1)세트"
    }

    private func seedDraft(_ rows: [PrescribedSet]) {
        draft = TodayController.loggedMatchingPrescribe(rows).map {
            var copy = $0
            copy.completed = false
            return copy
        }
    }

    private func loadHints(_ rows: [PrescribedSet]) {
        var map: [String: (kg: Double, reps: Int)] = [:]
        for row in rows where map[row.exerciseId] == nil {
            if let hint = SessionService.lastHint(context: context, exerciseId: row.exerciseId, exerciseName: row.exerciseName) {
                map[row.exerciseId] = hint
            }
        }
        hints = map
    }

    // MARK: Workout lifecycle

    private func startWorkout(cycle: TrainingCycle, schedule: ProgramSchedule) {
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile.inputs)
        loadHints(rows)
        seedDraft(rows)
        focusGroupId = rows.first?.groupId
        isWorkingOut = true
        cycle.saveDraft(draft, dayId: cycle.nextDayId)
        try? context.save()
    }

    /// The app was killed or the tab was left mid-workout: pick the ticked sets back up.
    private func restoreDraftIfNeeded() {
        guard !isWorkingOut, let cycle, cycle.hasDraft else { return }
        guard cycle.draftDayId == cycle.nextDayId,
              let schedule = cycle.resolvedSchedule(),
              let saved = cycle.loadDraft() else {
            SessionService.clearDraft(cycle: cycle)
            return
        }
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile.inputs)
        guard !rows.isEmpty else { SessionService.clearDraft(cycle: cycle); return }
        seedDraft(rows)
        for set in saved {
            if let idx = draft.firstIndex(where: { $0.exerciseId == set.exerciseId && $0.setIndex == set.setIndex }) {
                draft[idx].kg = set.kg
                draft[idx].reps = set.reps
                draft[idx].completed = set.completed
            }
        }
        loadHints(rows)
        let firstOpen = rows.first(where: { !isDone($0) }) ?? rows.first
        focusGroupId = firstOpen?.groupId
        isWorkingOut = true
    }

    private func requestExit(cycle: TrainingCycle) {
        if draft.contains(where: \.completed) {
            showExitDialog = true
        } else {
            discard(cycle: cycle)
        }
    }

    private func requestFinish(cycle: TrainingCycle, schedule: ProgramSchedule, rows: [PrescribedSet]) {
        if draft.contains(where: \.completed) {
            finish(cycle: cycle, schedule: schedule, rows: rows)
        } else {
            showEmptyFinishAlert = true
        }
    }

    private func discard(cycle: TrainingCycle) {
        skipRest()
        metronome.isOn = false
        isWorkingOut = false
        draft = []
        focusGroupId = nil
        SessionService.clearDraft(cycle: cycle)
        try? context.save()
    }

    private func finish(cycle: TrainingCycle, schedule: ProgramSchedule, rows: [PrescribedSet]) {
        skipRest()
        metronome.isOn = false
        let logged = draft
        isWorkingOut = false
        draft = []
        focusGroupId = nil
        SessionService.complete(
            context: context,
            cycle: cycle,
            schedule: schedule,
            profile: profile.inputs,
            rows: rows,
            logged: logged
        )
        try? context.save()
    }

    // MARK: Rest timer

    private func startRest() {
        restEndsAt = Date().addingTimeInterval(TimeInterval(theme.restSeconds))
        showRest = true
        RestNotifier.schedule(after: theme.restSeconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async { tickRest() }
        }
        tickRest()
    }

    private func tickRest() {
        restTick = Date()
        guard restEndsAt != nil else { return }
        if timerRemaining <= 0 {
            timer?.invalidate()
            timer = nil
            restEndsAt = nil
            showRest = false
            RestNotifier.cancel()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func adjustRest(by delta: Int) {
        guard let current = restEndsAt else { return }
        let remaining = max(0, Int(ceil(current.timeIntervalSinceNow)))
        let target = min(600, max(0, remaining + delta))
        restEndsAt = Date().addingTimeInterval(TimeInterval(target))
        RestNotifier.schedule(after: target)
        tickRest()
    }

    private func skipRest() {
        timer?.invalidate()
        timer = nil
        restEndsAt = nil
        showRest = false
        RestNotifier.cancel()
    }
}

/// Local notification so the rest timer still "rings" when the phone is locked.
enum RestNotifier {
    private static let id = "gym.rest.done"
    private static var asked = false

    static func schedule(after seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard seconds > 0 else { return }
        let request = { () -> Void in
            let content = UNMutableNotificationContent()
            content.title = "휴식 끝"
            content.body = "다음 세트 갈 시간이에요."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        if asked {
            request()
        } else {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { request() }
            }
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
