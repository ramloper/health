import Foundation

struct FiveThreeOneBBBEngine: ProgressionEngine {
    static let id = "531-bbb"
    var programId: String { Self.id }

    private let dayLifts = ["squat": "squat", "bench": "bench", "dead": "deadlift", "press": "ohp"]
    private let warmup: [(Double, Int)] = [(0.40, 5), (0.50, 5), (0.60, 3)]
    private let weekWork: [Int: [(Double, Int)]] = [
        1: [(0.65, 5), (0.75, 5), (0.85, 5)],
        2: [(0.70, 3), (0.80, 3), (0.90, 3)],
        3: [(0.75, 5), (0.85, 3), (0.95, 1)],
        4: [(0.40, 5), (0.50, 5), (0.60, 5)]
    ]

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        let lift = dayLifts[day.id] ?? day.id
        let tm = state.tm[lift] ?? Kg.trainingMax(fromOneRM: profile.oneRM(forLift: lift))
        let week = ((state.weekIndex - 1) % 4) + 1
        let work = weekWork[week] ?? weekWork[1]!
        let main = day.exercises.first
        let name = main?.name ?? day.name
        let liftKey = main?.variantId ?? lift
        var rows: [PrescribedSet] = []
        var idx = 0
        for (pct, reps) in warmup {
            rows.append(PrescribedSet(
                exerciseId: lift, exerciseName: name, liftKey: liftKey, setIndex: idx,
                kg: Kg.percent(tm, pct), reps: reps, repMax: reps,
                isWorking: false, isWarmup: true, isAMRAP: false, isBBB: false, isOptional: false
            ))
            idx += 1
        }
        for (i, pair) in work.enumerated() {
            let amrap = week <= 3 && i == work.count - 1
            rows.append(PrescribedSet(
                exerciseId: lift, exerciseName: name, liftKey: liftKey, setIndex: idx,
                kg: Kg.percent(tm, pair.0), reps: pair.1, repMax: pair.1,
                isWorking: true, isWarmup: false, isAMRAP: amrap, isBBB: false, isOptional: false
            ))
            idx += 1
        }
        if week != 4 {
            let bbbKg = Kg.percent(tm, 0.50)
            for b in 0..<5 {
                rows.append(PrescribedSet(
                    exerciseId: lift, exerciseName: "BBB \(name)", liftKey: liftKey, setIndex: idx + b,
                    kg: bbbKg, reps: 10, repMax: 10,
                    isWorking: true, isWarmup: false, isAMRAP: false, isBBB: true, isOptional: false
                ))
            }
        }
        return rows
    }

    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance {
        let lift = dayLifts[session.dayId] ?? session.dayId
        let week = ((state.weekIndex - 1) % 4) + 1
        var pending = state.pendingTmBump
        var tm = state.tm
        if week == 3 {
            let target = prescribe(schedule: schedule, profile: profile, state: state)
                .first(where: { $0.isAMRAP })?.reps ?? 1
            if let amrap = session.sets.first(where: { $0.isAMRAP && $0.completed }), amrap.reps >= target {
                let bump = (lift == "squat" || lift == "deadlift") ? 5.0 : 2.5
                pending[lift] = bump
            }
        }
        let days = DayCursor.trainingDays(in: schedule)
        let nextId = DayCursor.nextDayId(after: session.dayId, schedule: schedule)
        // A week is one session per training day, counted by sessions so that
        // picking days out of order can neither skip nor stall the week.
        let completedAfter = state.trainingSessionsCompleted + 1
        let wrapped = !days.isEmpty && completedAfter % days.count == 0
        var nextWeek = week
        if wrapped {
            if week == 4 {
                for (id, bump) in pending {
                    tm[id] = (tm[id] ?? 0) + bump
                }
                pending = [:]
                nextWeek = 1
            } else {
                nextWeek = week + 1
            }
        }
        return EngineAdvance(
            workingKgByExerciseId: state.workingKg,
            tmByLiftId: tm,
            stallCountByExerciseId: state.stall,
            pendingTmBumpByLiftId: pending,
            weekIndex: nextWeek,
            trainingSessionsCompleted: state.trainingSessionsCompleted + 1,
            deloadSessionsRemaining: 0,
            nextDayId: nextId
        )
    }
}
