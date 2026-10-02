import Foundation

struct StartingStrengthEngine: ProgressionEngine {
    static let id = "ss-novice-lp"
    var programId: String { Self.id }

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        var rows: [PrescribedSet] = []
        for ex in day.exercises {
            let kg = state.workingKg[ex.stateKey] ?? ex.seedKg ?? 40
            for i in 0..<ex.sets {
                rows.append(PrescribedSet(
                    exerciseId: ex.id, exerciseName: ex.name, liftKey: ex.liftKey, setIndex: i,
                    kg: kg, reps: ex.repMax, repMax: ex.repMax,
                    isWorking: true, isWarmup: false, isAMRAP: false, isBBB: false, isOptional: false,
                    repMin: ex.repMin
                ))
            }
        }
        return rows
    }

    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance {
        var working = state.workingKg
        var stall = state.stall
        let day = schedule.days.first(where: { $0.id == session.dayId })
        for group in ProgressionGroup.grouped(day: day, sets: session.sets.filter { $0.isWorking }) {
            let key = group.stateKey
            let ex = group.lead
            // Skipped entirely (nothing ticked) is not a failed attempt: leave weight and stall count alone.
            guard let current = group.sets.filter(\.completed).map(\.kg).min() else { continue }
            let allHit = group.entries.allSatisfy { $0.set.completed && $0.set.reps >= $0.slot.repMax }
            if current != (working[key] ?? ex.seedKg ?? 40) { stall[key] = 0 }
            working[key] = current
            if allHit {
                stall[key] = 0
                let lower = ex.exerciseId == "squat" || ex.exerciseId == "deadlift"
                working[key] = current + (lower ? 5 : 2.5)
            } else {
                let fails = (stall[key] ?? 0) + 1
                stall[key] = fails
                if fails >= 3 {
                    working[key] = Kg.nearest(current * 0.9)
                    stall[key] = 0
                }
            }
        }
        return EngineAdvance(
            workingKgByExerciseId: working,
            tmByLiftId: state.tm,
            stallCountByExerciseId: stall,
            pendingTmBumpByLiftId: state.pendingTmBump,
            weekIndex: state.weekIndex,
            trainingSessionsCompleted: state.trainingSessionsCompleted + 1,
            deloadSessionsRemaining: 0,
            nextDayId: DayCursor.nextDayId(after: session.dayId, schedule: schedule)
        )
    }
}
