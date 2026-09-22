import Foundation

struct ProgramSchedule: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var days: [ProgramDay]

    var isCustom: Bool { EngineRegistry.isCustom(id) }

    static func makeCustom(name: String = "내 루틴") -> ProgramSchedule {
        ProgramSchedule(
            id: "custom-\(UUID().uuidString)",
            name: name,
            days: [ProgramDay.blank(named: "1일차")]
        )
    }

    static func copiedAsCustom(from schedule: ProgramSchedule) -> ProgramSchedule {
        let days = DayCursor.trainingDays(in: schedule).enumerated().map { index, day in
            ProgramDay(
                id: "day-\(UUID().uuidString)",
                name: day.name.isEmpty ? "\(index + 1)일차" : day.name,
                isRest: false,
                exercises: day.exercises.map { $0.copiedAsCustom() }
            )
        }
        return ProgramSchedule(
            id: "custom-\(UUID().uuidString)",
            name: "\(schedule.name) (내 루틴)",
            days: days.isEmpty ? [ProgramDay.blank(named: "1일차")] : days
        )
    }
}

struct ProgramDay: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var isRest: Bool
    var exercises: [ScheduleExercise]

    static func blank(named name: String) -> ProgramDay {
        ProgramDay(id: "day-\(UUID().uuidString)", name: name, isRest: false, exercises: [])
    }
}

struct ScheduleExercise: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var sets: Int
    var repMin: Int
    var repMax: Int
    var isWorking: Bool
    var isOptional: Bool
    var plane: String
    var seedKg: Double?
    var substituteId: String?
    var isCompound: Bool?

    /// "5~8회" for ranges, "8회" when min == max.
    var repLabel: String {
        let lo = max(1, repMin), hi = max(1, repMax)
        return lo < hi ? "\(lo)~\(hi)회" : "\(hi)회"
    }

    var targetReps: Int {
        get { max(1, repMax) }
        set {
            let value = max(1, newValue)
            repMin = value
            repMax = value
        }
    }

    static func makeCustom(name: String, sets: Int = 3, reps: Int = 10, seedKg: Double = 20) -> ScheduleExercise {
        ScheduleExercise(
            id: "ex-\(UUID().uuidString)",
            name: name,
            sets: sets,
            repMin: reps,
            repMax: reps,
            isWorking: true,
            isOptional: false,
            plane: ExerciseGuide.defaultPlane(for: name),
            seedKg: seedKg
        )
    }

    func copiedAsCustom() -> ScheduleExercise {
        var copy = self
        copy.id = "ex-\(UUID().uuidString)"
        return copy
    }
}

struct ProfileInputs: Equatable {
    var bench1RM: Double
    var squat1RM: Double
    var dead1RM: Double
    var ohp1RM: Double

    static let documentDefaults = ProfileInputs(bench1RM: 75, squat1RM: 110, dead1RM: 120, ohp1RM: 60)

    func oneRM(forLift liftId: String) -> Double {
        switch liftId {
        case "bench", "cap": return bench1RM
        case "squat": return squat1RM
        case "deadlift", "dead": return dead1RM
        case "ohp", "press": return ohp1RM
        default: return bench1RM
        }
    }
}

struct CycleState: Equatable {
    var programId: String
    var nextDayId: String
    var weekIndex: Int
    var trainingSessionsCompleted: Int
    var deloadSessionsRemaining: Int
    var workingKg: [String: Double]
    var tm: [String: Double]
    var stall: [String: Int]
    var pendingTmBump: [String: Double]
}

struct PrescribedSet: Equatable, Identifiable {
    var id: String { "\(exerciseId)-\(setIndex)" }
    var exerciseId: String
    var exerciseName: String
    var setIndex: Int
    var kg: Double
    var reps: Int
    var repMax: Int?
    var isWorking: Bool
    var isWarmup: Bool
    var isAMRAP: Bool
    var isBBB: Bool
    var isOptional: Bool
    var repMin: Int? = nil
}

struct CompletedSet: Equatable, Codable {
    var exerciseId: String
    var setIndex: Int
    var kg: Double
    var reps: Int
    var isWorking: Bool
    var isAMRAP: Bool
    var isWarmup: Bool
    var isBBB: Bool
    var completed: Bool
}

struct CompletedSession: Equatable {
    var dayId: String
    var sets: [CompletedSet]
}

struct EngineAdvance: Equatable {
    var workingKgByExerciseId: [String: Double]
    var tmByLiftId: [String: Double]
    var stallCountByExerciseId: [String: Int]
    var pendingTmBumpByLiftId: [String: Double]
    var weekIndex: Int
    var trainingSessionsCompleted: Int
    var deloadSessionsRemaining: Int
    var nextDayId: String

    func applied(to state: CycleState) -> CycleState {
        var next = state
        next.workingKg = workingKgByExerciseId
        next.tm = tmByLiftId
        next.stall = stallCountByExerciseId
        next.pendingTmBump = pendingTmBumpByLiftId
        next.weekIndex = weekIndex
        next.trainingSessionsCompleted = trainingSessionsCompleted
        next.deloadSessionsRemaining = deloadSessionsRemaining
        next.nextDayId = nextDayId
        return next
    }
}

protocol ProgressionEngine {
    var programId: String { get }
    func prescribe(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState) -> [PrescribedSet]
    func advance(schedule: ProgramSchedule, profile: ProfileInputs, state: CycleState, session: CompletedSession) -> EngineAdvance
}

enum EngineRegistry {
    static func isCustom(_ programId: String) -> Bool {
        programId.hasPrefix("custom-")
    }

    /// 5/3/1 and nSuns derive every set from a training max; the day's exercise list is only used for names.
    static func usesTrainingMax(_ programId: String) -> Bool {
        programId == FiveThreeOneBBBEngine.id || programId == NSuns5DayEngine.id
    }

    static func engine(for programId: String) -> ProgressionEngine {
        switch programId {
        case Hypertrophy6DayEngine.id: return Hypertrophy6DayEngine()
        case FiveThreeOneBBBEngine.id: return FiveThreeOneBBBEngine()
        case NSuns5DayEngine.id: return NSuns5DayEngine()
        case StartingStrengthEngine.id: return StartingStrengthEngine()
        case ClassBEngine.pplId: return ClassBEngine(programId: ClassBEngine.pplId)
        case ClassBEngine.phulId: return ClassBEngine(programId: ClassBEngine.phulId)
        case ClassBEngine.ulId: return ClassBEngine(programId: ClassBEngine.ulId)
        default:
            if isCustom(programId) {
                return ClassBEngine(programId: programId)
            }
            return Hypertrophy6DayEngine()
        }
    }
}

enum DayCursor {
    static func trainingDays(in schedule: ProgramSchedule) -> [ProgramDay] {
        schedule.days.filter { !$0.isRest }
    }

    static func nextDayId(after dayId: String, schedule: ProgramSchedule) -> String {
        let days = trainingDays(in: schedule)
        guard let idx = days.firstIndex(where: { $0.id == dayId }) else {
            return days.first?.id ?? dayId
        }
        return days[(idx + 1) % days.count].id
    }

    static func firstTrainingDayId(in schedule: ProgramSchedule) -> String {
        trainingDays(in: schedule).first?.id ?? schedule.days.first?.id ?? ""
    }
}
