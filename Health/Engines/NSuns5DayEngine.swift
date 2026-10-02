import Foundation

struct NSuns5DayEngine: ProgressionEngine {
    static let id = "nsuns-5day"
    var programId: String { Self.id }

    private let t1: [(Double, Int)] = [
        (0.40, 5), (0.50, 5), (0.60, 3), (0.75, 5), (0.85, 3), (0.95, 1)
    ]
    private let t2: [(Double, Int)] = [
        (0.50, 6), (0.60, 5), (0.70, 3), (0.75, 5), (0.80, 3), (0.85, 1)
    ]
    private let dayLift = ["cap": "cap", "ohp": "ohp", "dead": "deadlift", "bench": "bench", "squat": "squat"]

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        let lift = dayLift[day.id] ?? day.id
        let tmKey = lift == "cap" ? "bench" : lift
        let tm = state.tm[tmKey] ?? state.tm[lift] ?? 100
        let name = day.exercises.first?.name ?? day.name
        let liftKey = day.exercises.first?.variantId ?? lift
        var rows: [PrescribedSet] = []
        for (i, pair) in t1.enumerated() {
            let amrap = i == t1.count - 1
            rows.append(PrescribedSet(
                exerciseId: lift, exerciseName: name, liftKey: liftKey, setIndex: i,
                kg: Kg.percent(tm, pair.0), reps: pair.1, repMax: pair.1,
                isWorking: true, isWarmup: i < 3, isAMRAP: amrap, isBBB: false, isOptional: false
            ))
        }
        let t2Name = day.exercises.dropFirst().first?.name ?? "T2"
        let t2Id = day.exercises.dropFirst().first?.id ?? "\(lift)-t2"
        let t2LiftKey = day.exercises.dropFirst().first?.variantId ?? liftKey
        for (i, pair) in t2.enumerated() {
            rows.append(PrescribedSet(
                exerciseId: t2Id, exerciseName: t2Name, liftKey: t2LiftKey, setIndex: t1.count + i,
                kg: Kg.percent(tm, pair.0), reps: pair.1, repMax: pair.1,
                isWorking: true, isWarmup: false, isAMRAP: i == t2.count - 1, isBBB: false, isOptional: false
            ))
        }
        return rows
    }

    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance {
        var tm = state.tm
        let lift = dayLift[session.dayId] ?? session.dayId
        let tmKey = lift == "cap" ? "bench" : lift
        if let t1Amrap = session.sets.first(where: { $0.exerciseId == lift && $0.isAMRAP && $0.completed }) {
            let extra = t1Amrap.reps - 1
            let bump: Double
            if extra <= 1 { bump = 0 }
            else if extra <= 4 { bump = 2.5 }
            else { bump = 5 }
            if bump > 0 {
                tm[tmKey] = (tm[tmKey] ?? 0) + bump
            }
        }
        return EngineAdvance(
            workingKgByExerciseId: state.workingKg,
            tmByLiftId: tm,
            stallCountByExerciseId: state.stall,
            pendingTmBumpByLiftId: state.pendingTmBump,
            weekIndex: state.weekIndex,
            trainingSessionsCompleted: state.trainingSessionsCompleted + 1,
            deloadSessionsRemaining: 0,
            nextDayId: DayCursor.nextDayId(after: session.dayId, schedule: schedule)
        )
    }
}
