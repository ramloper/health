import Foundation

struct StartingStrengthEngine: ProgressionEngine {
    static let id = "ss-novice-lp"
    var programId: String { Self.id }

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        var rows: [PrescribedSet] = []
        for ex in day.exercises {
            let kg = state.workingKg[ex.id] ?? ex.seedKg ?? 40
            for i in 0..<ex.sets {
                rows.append(PrescribedSet(
                    exerciseId: ex.id, exerciseName: ex.name, setIndex: i,
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
        let grouped = Dictionary(grouping: session.sets.filter { $0.isWorking }) { $0.exerciseId }
        for (id, sets) in grouped {
            guard let ex = schedule.days.flatMap(\.exercises).first(where: { $0.id == id }) else { continue }
            // Skipped entirely (nothing ticked) is not a failed attempt: leave weight and stall count alone.
            guard sets.contains(where: \.completed) else { continue }
            let allHit = sets.allSatisfy { $0.completed && $0.reps >= ex.repMax }
            let current = working[id] ?? ex.seedKg ?? 40
            if allHit {
                stall[id] = 0
                let lower = id == "squat" || id == "deadlift"
                working[id] = current + (lower ? 5 : 2.5)
            } else {
                let fails = (stall[id] ?? 0) + 1
                stall[id] = fails
                if fails >= 3 {
                    working[id] = Kg.nearest(current * 0.9)
                    stall[id] = 0
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
