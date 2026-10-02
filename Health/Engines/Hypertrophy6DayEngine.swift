import Foundation

struct Hypertrophy6DayEngine: ProgressionEngine {
    static let id = "hypertrophy-6day"
    var programId: String { Self.id }

    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet] {
        guard let day = schedule.days.first(where: { $0.id == state.nextDayId }) else { return [] }
        let deload = state.deloadSessionsRemaining > 0
        var rows: [PrescribedSet] = []
        for ex in day.exercises {
            let setCount = deload ? Int(ceil(Double(ex.sets) / 2.0)) : ex.sets
            let kg = state.workingKg[ex.id] ?? ex.seedKg ?? 20
            for i in 0..<setCount {
                rows.append(PrescribedSet(
                    exerciseId: ex.id,
                    exerciseName: ex.name,
                    setIndex: i,
                    kg: kg,
                    reps: ex.repMax,
                    repMax: ex.repMax,
                    isWorking: ex.isWorking,
                    isWarmup: false,
                    isAMRAP: false,
                    isBBB: false,
                    isOptional: ex.isOptional,
                    repMin: ex.repMin
                ))
            }
        }
        return rows
    }

    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance {
        var working = state.workingKg
        var deloadLeft = state.deloadSessionsRemaining
        let inDeload = deloadLeft > 0

        if !inDeload {
            let grouped = Dictionary(grouping: session.sets.filter { $0.isWorking && !$0.isWarmup }) { $0.exerciseId }
            for (exerciseId, sets) in grouped {
                let completed = sets.filter(\.completed)
                guard let performedKg = completed.map(\.kg).min(),
                      let ex = schedule.days.first(where: { $0.id == session.dayId })?.exercises.first(where: { $0.id == exerciseId }) else { continue }
                let hitTop = completed.count == sets.count && completed.allSatisfy { $0.reps >= ex.repMax }
                working[exerciseId] = performedKg
                if hitTop {
                    let delta = ex.plane == "lower" ? 5.0 : 2.5
                    working[exerciseId] = performedKg + delta
                }
            }
        }

        let completedAfter = state.trainingSessionsCompleted + 1
        var sessions = completedAfter
        if inDeload {
            deloadLeft = state.deloadSessionsRemaining - 1
        } else if completedAfter == 30 {
            deloadLeft = 6
        } else {
            deloadLeft = 0
        }
        if deloadLeft == 0, inDeload {
            sessions = 0
        }

        return EngineAdvance(
            workingKgByExerciseId: working,
            tmByLiftId: state.tm,
            stallCountByExerciseId: state.stall,
            pendingTmBumpByLiftId: state.pendingTmBump,
            weekIndex: max(1, (min(sessions, 30) - 1) / 6 + 1),
            trainingSessionsCompleted: sessions,
            deloadSessionsRemaining: deloadLeft,
            nextDayId: DayCursor.nextDayId(after: session.dayId, schedule: schedule)
        )
    }
}
