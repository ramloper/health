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
            let kg = state.workingKg[ex.stateKey] ?? ex.seedKg ?? 20
            for i in 0..<setCount {
                rows.append(PrescribedSet(
                    exerciseId: ex.id,
                    exerciseName: ex.displayName,
                    liftKey: ex.liftKey,
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
            let day = schedule.days.first(where: { $0.id == session.dayId })
            for group in ProgressionGroup.grouped(day: day, sets: session.sets.filter { $0.isWorking && !$0.isWarmup }) {
                guard let performedKg = group.sets.filter(\.completed).map(\.kg).min() else { continue }
                let hitTop = group.entries.allSatisfy { $0.set.completed && $0.set.reps >= $0.slot.repMax }
                working[group.stateKey] = performedKg
                if hitTop {
                    let delta = group.lead.plane == "lower" ? 5.0 : 2.5
                    working[group.stateKey] = performedKg + delta
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
