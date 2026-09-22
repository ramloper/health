import Foundation

enum ProgramCatalog {
    static let defaultProgramId = Hypertrophy6DayEngine.id

    static let allIds = [
        Hypertrophy6DayEngine.id,
        FiveThreeOneBBBEngine.id,
        NSuns5DayEngine.id,
        ClassBEngine.pplId,
        ClassBEngine.phulId,
        ClassBEngine.ulId,
        StartingStrengthEngine.id
    ]

    static func loadAll() -> [ProgramSchedule] {
        allIds.compactMap { load($0) }
    }

    /// Programs are copied into the bundle as a folder reference, so they live under `Programs/`.
    static func load(_ id: String) -> ProgramSchedule? {
        guard let url = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "Programs"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProgramSchedule.self, from: data)
    }

    static func decode(_ data: Data) throws -> ProgramSchedule {
        try JSONDecoder().decode(ProgramSchedule.self, from: data)
    }

    static func trainingMaxes(for profile: ProfileInputs) -> [String: Double] {
        [
            "bench": Kg.trainingMax(fromOneRM: profile.bench1RM),
            "squat": Kg.trainingMax(fromOneRM: profile.squat1RM),
            "deadlift": Kg.trainingMax(fromOneRM: profile.dead1RM),
            "ohp": Kg.trainingMax(fromOneRM: profile.ohp1RM),
            "press": Kg.trainingMax(fromOneRM: profile.ohp1RM),
            "cap": Kg.trainingMax(fromOneRM: profile.bench1RM)
        ]
    }

    static func seededState(schedule: ProgramSchedule, profile: ProfileInputs) -> CycleState {
        var working: [String: Double] = [:]
        for day in schedule.days {
            for ex in day.exercises {
                if let seed = ex.seedKg {
                    working[ex.id] = seed
                }
            }
        }
        let tm = trainingMaxes(for: profile)
        return CycleState(
            programId: schedule.id,
            nextDayId: DayCursor.firstTrainingDayId(in: schedule),
            weekIndex: 1,
            trainingSessionsCompleted: 0,
            deloadSessionsRemaining: 0,
            workingKg: working,
            tm: tm,
            stall: [:],
            pendingTmBump: [:]
        )
    }
}
