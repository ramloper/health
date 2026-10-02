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

    /// Copies keep each slot's progression separate. Tags are preserved; when the source is a bundled program,
    /// variants that repeat across untagged slots (Starting Strength's shared squat) get the original day id as tag,
    /// assigned before day ids are rewritten — 1.0 copies achieved the same by giving every slot its own id.
    static func copiedAsCustom(from schedule: ProgramSchedule) -> ProgramSchedule {
        let trainingDays = DayCursor.trainingDays(in: schedule)
        var autoTagged = Set<String>()
        if !schedule.isCustom {
            let untagged = trainingDays.flatMap(\.exercises).filter { $0.progressionTag == nil }
            autoTagged = Set(Dictionary(grouping: untagged, by: \.variantId).filter { $0.value.count >= 2 }.keys)
        }
        let days = trainingDays.enumerated().map { index, day in
            ProgramDay(
                id: "day-\(UUID().uuidString)",
                name: day.name.isEmpty ? "\(index + 1)일차" : day.name,
                isRest: false,
                exercises: day.exercises.map { ex in
                    var copy = ex.copiedAsCustom()
                    if copy.progressionTag == nil, autoTagged.contains(ex.variantId) {
                        copy.progressionTag = day.id
                    }
                    return copy
                }
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
    /// Slot id: identifies the row within a schedule and session. Not a record key.
    var id: String
    /// Name stored with the slot; display falls back to it when the library has no name for `variantId`.
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
    /// Library base exercise id (`other` for free-text user variants).
    var exerciseId: String
    /// Library or user variant id. Generic variant id == `exerciseId`.
    var variantId: String
    /// Separates repeated slots of one variant within a program (`a`/`b`, `heavy`/`light`, `t1`/`t2`).
    var progressionTag: String? = nil
    /// Short prefix for display ("T2", "라이트").
    var label: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, sets, repMin, repMax, isWorking, isOptional, plane, seedKg, substituteId, isCompound
        case exerciseId, variantId, progressionTag, label
    }

    /// Record key for `SetLog.liftKey` and `PersonalRecord.liftId`.
    var liftKey: String { variantId }

    /// Progression key for `CycleState.workingKg` and `stall`.
    var stateKey: String {
        progressionTag.map { "\(variantId)|\($0)" } ?? variantId
    }

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

    /// Library display name (with `label` prefix), falling back to the stored `name` for user variants.
    var displayName: String {
        // User variants (`<exerciseId>/u-…`) are not in the library; their stored name is the nickname.
        let isUserVariant = variantId.contains("/u-")
        let base = isUserVariant ? name : (ExerciseLibrary.shared.displayName(variantId: variantId) ?? name)
        guard let label, !label.isEmpty else { return base }
        return "\(label) \(base)"
    }

    /// A new user-added slot: no progression tag. `name` defaults to the library display name; `plane` defaults to
    /// the library exercise's plane, or a name guess for `other` (pass `UserVariant.plane` for those).
    static func makeCustom(
        exerciseId: String,
        variantId: String? = nil,
        name: String? = nil,
        plane: String? = nil,
        sets: Int = 3,
        reps: Int = 10,
        seedKg: Double = 20
    ) -> ScheduleExercise {
        let library = ExerciseLibrary.shared
        let base = library.exercise(id: exerciseId)
        let variant = variantId ?? exerciseId
        let title = name ?? library.displayName(variantId: variant) ?? variant
        return ScheduleExercise(
            id: "ex-\(UUID().uuidString)",
            name: title,
            sets: sets,
            repMin: reps,
            repMax: reps,
            isWorking: true,
            isOptional: false,
            plane: plane ?? base?.plane ?? PlaneGuess.guess(title),
            seedKg: seedKg,
            isCompound: base?.isCompound ?? false,
            exerciseId: exerciseId,
            variantId: variant
        )
    }

    /// New slot id; variant, tag and label are preserved.
    func copiedAsCustom() -> ScheduleExercise {
        var copy = self
        copy.id = "ex-\(UUID().uuidString)"
        return copy
    }

    /// "운동 바꾸기": swaps the machine but keeps the slot, sets, reps, seed and progression tag.
    func replacingVariant(_ variantId: String, name: String, exerciseId: String, plane: String) -> ScheduleExercise {
        var copy = self
        copy.variantId = variantId
        copy.name = name
        copy.exerciseId = exerciseId
        copy.plane = plane
        return copy
    }
}

extension ScheduleExercise {
    /// `exerciseId` is required (1.0 schedules without it fail to decode); `variantId` defaults to `exerciseId`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sets = try c.decode(Int.self, forKey: .sets)
        repMin = try c.decode(Int.self, forKey: .repMin)
        repMax = try c.decode(Int.self, forKey: .repMax)
        isWorking = try c.decode(Bool.self, forKey: .isWorking)
        isOptional = try c.decode(Bool.self, forKey: .isOptional)
        plane = try c.decode(String.self, forKey: .plane)
        seedKg = try c.decodeIfPresent(Double.self, forKey: .seedKg)
        substituteId = try c.decodeIfPresent(String.self, forKey: .substituteId)
        isCompound = try c.decodeIfPresent(Bool.self, forKey: .isCompound)
        exerciseId = try c.decode(String.self, forKey: .exerciseId)
        variantId = try c.decodeIfPresent(String.self, forKey: .variantId) ?? exerciseId
        progressionTag = try c.decodeIfPresent(String.self, forKey: .progressionTag)
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

/// Completed sets of one day grouped by `stateKey`, in `day.exercises` order. Slots that share a stateKey on the
/// same day form one group; each set keeps its own slot so rep targets stay per slot.
struct ProgressionGroup {
    var stateKey: String
    /// First slot of the group in day order; decides plane and seed.
    var lead: ScheduleExercise
    var entries: [(set: CompletedSet, slot: ScheduleExercise)]

    var sets: [CompletedSet] { entries.map(\.set) }

    static func grouped(day: ProgramDay?, sets: [CompletedSet]) -> [ProgressionGroup] {
        guard let day else { return [] }
        var groups: [ProgressionGroup] = []
        var seenSlots = Set<String>()
        for slot in day.exercises where seenSlots.insert(slot.id).inserted {
            let mine = sets.filter { $0.exerciseId == slot.id }
            guard !mine.isEmpty else { continue }
            let entries = mine.map { (set: $0, slot: slot) }
            if let i = groups.firstIndex(where: { $0.stateKey == slot.stateKey }) {
                groups[i].entries += entries
            } else {
                groups.append(ProgressionGroup(stateKey: slot.stateKey, lead: slot, entries: entries))
            }
        }
        return groups
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

/// Which profile 1RM the guide sheet shows for an exercise. Display only; prescriptions never use it.
enum OneRMMap {
    private static let table: [String: String] = [
        "bench": "bench", "close-grip-bench": "bench", "incline-bench": "bench",
        "db-bench-press": "bench", "smith-bench-press": "bench",
        "squat": "squat", "front-squat": "squat", "smith-squat": "squat",
        "deadlift": "dead",
        "ohp": "ohp"
    ]

    /// `bench`/`squat`/`dead`/`ohp` (keys of `ProfileInputs.oneRM(forLift:)`), or nil.
    static func lift(forExerciseId exerciseId: String) -> String? {
        table[exerciseId]
    }

    static var mappedExerciseIds: [String] { table.keys.sorted() }
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
    var groupId: String { "\(exerciseId)-\(isBBB ? "bbb" : "main")" }
    var exerciseId: String
    var exerciseName: String
    /// Record key (variant id) of the slot this row was prescribed from.
    var liftKey: String
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
