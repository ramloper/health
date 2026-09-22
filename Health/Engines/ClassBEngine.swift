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
            let kg = state.workingKg[ex.id] ?? ex.seedKg ?? 20
            for i in 0..<ex.sets {
                rows.append(PrescribedSet(
                    exerciseId: ex.id, exerciseName: ex.name, setIndex: i,
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
        let grouped = Dictionary(grouping: session.sets.filter { $0.isWorking }) { $0.exerciseId }
        for (id, sets) in grouped {
            guard let ex = schedule.days.flatMap(\.exercises).first(where: { $0.id == id }) else { continue }
            let completed = sets.filter(\.completed)
            let hitTop = !completed.isEmpty && completed.count == sets.count && completed.allSatisfy { $0.reps >= ex.repMax }
            if hitTop {
                let delta = ex.plane == "lower" ? 5.0 : 2.5
                working[id] = (working[id] ?? ex.seedKg ?? 20) + delta
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
