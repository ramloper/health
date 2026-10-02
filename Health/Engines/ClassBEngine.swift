import Foundation

/// Schedule-native double progression without the 우람 6-day 30-session deload.
struct ClassBEngine: ProgressionEngine {
    static let pplId = "ppl-metallicadpa"
    static let phulId = "phul"
    static let ulId = "upper-lower-4day"

    var programId: String

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        var rows: [PrescribedSet] = []
        for ex in day.exercises {
            let kg = state.workingKg[ex.stateKey] ?? ex.seedKg ?? 20
            for i in 0..<ex.sets {
                rows.append(PrescribedSet(
                    exerciseId: ex.id, exerciseName: ex.displayName, liftKey: ex.liftKey, setIndex: i,
                    kg: kg, reps: ex.repMax, repMax: ex.repMax,
                    isWorking: ex.isWorking, isWarmup: false, isAMRAP: false, isBBB: false, isOptional: ex.isOptional,
                    repMin: ex.repMin
                ))
            }
        }
        return rows
    }

    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance {
        var working = state.workingKg
        let day = schedule.days.first(where: { $0.id == session.dayId })
        for group in ProgressionGroup.grouped(day: day, sets: session.sets.filter { $0.isWorking }) {
            guard let performedKg = group.sets.filter(\.completed).map(\.kg).min() else { continue }
            let hitTop = group.entries.allSatisfy { $0.set.completed && $0.set.reps >= $0.slot.repMax }
            working[group.stateKey] = performedKg
            if hitTop {
                let delta = group.lead.plane == "lower" ? 5.0 : 2.5
                working[group.stateKey] = performedKg + delta
            }
        }
        return EngineAdvance(
            workingKgByExerciseId: working,
            tmByLiftId: state.tm,
            stallCountByExerciseId: state.stall,
            pendingTmBumpByLiftId: state.pendingTmBump,
            weekIndex: state.weekIndex,
            trainingSessionsCompleted: state.trainingSessionsCompleted + 1,
            deloadSessionsRemaining: 0,
            nextDayId: DayCursor.nextDayId(after: session.dayId, schedule: schedule)
        )
    }
}
