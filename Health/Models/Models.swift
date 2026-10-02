import Foundation
import SwiftData

@Model
final class AthleteProfile {
    var bench1RM: Double
    var squat1RM: Double
    var dead1RM: Double
    var ohp1RM: Double
    var preferredProgramId: String
    var hasCompletedOnboarding: Bool
    /// Brands available at the user's gym; shown first in the variant picker.
    var gymBrandIds: [String] = []

    init(
        bench1RM: Double = 75,
        squat1RM: Double = 110,
        dead1RM: Double = 120,
        ohp1RM: Double = 60,
        preferredProgramId: String = Hypertrophy6DayEngine.id,
        hasCompletedOnboarding: Bool = false
    ) {
        self.bench1RM = bench1RM
        self.squat1RM = squat1RM
        self.dead1RM = dead1RM
        self.ohp1RM = ohp1RM
        self.preferredProgramId = preferredProgramId
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    var inputs: ProfileInputs {
        ProfileInputs(bench1RM: bench1RM, squat1RM: squat1RM, dead1RM: dead1RM, ohp1RM: ohp1RM)
    }
}

@Model
final class TrainingCycle {
    var programId: String
    var startedAt: Date
    var isActive: Bool
    var nextDayId: String
    var weekIndex: Int
    var trainingSessionsCompleted: Int
    var deloadSessionsRemaining: Int
    var workingKgJSON: String
    var tmJSON: String
    var stallJSON: String
    var pendingTmJSON: String
    var scheduleJSON: String = ""
    /// Edits made during a workout take effect after its draft is finished or discarded.
    var pendingScheduleJSON: String = ""
    /// In-progress workout (sets ticked so far). Empty when no session is running.
    var draftJSON: String = ""
    var draftDayId: String = ""
    var draftStartedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSession.cycle)
    var sessions: [WorkoutSession]

    init(programId: String, state: CycleState, schedule: ProgramSchedule? = nil, startedAt: Date = .now) {
        self.programId = programId
        self.startedAt = startedAt
        self.isActive = true
        self.nextDayId = state.nextDayId
        self.weekIndex = state.weekIndex
        self.trainingSessionsCompleted = state.trainingSessionsCompleted
        self.deloadSessionsRemaining = state.deloadSessionsRemaining
        self.workingKgJSON = Self.encode(state.workingKg)
        self.tmJSON = Self.encode(state.tm)
        self.stallJSON = Self.encodeInt(state.stall)
        self.pendingTmJSON = Self.encode(state.pendingTmBump)
        self.scheduleJSON = schedule.flatMap { Self.encodeSchedule($0) } ?? ""
        self.sessions = []
    }

    var state: CycleState {
        CycleState(
            programId: programId,
            nextDayId: nextDayId,
            weekIndex: weekIndex,
            trainingSessionsCompleted: trainingSessionsCompleted,
            deloadSessionsRemaining: deloadSessionsRemaining,
            workingKg: Self.decode(workingKgJSON),
            tm: Self.decode(tmJSON),
            stall: Self.decodeInt(stallJSON),
            pendingTmBump: Self.decode(pendingTmJSON)
        )
    }

    func resolvedSchedule() -> ProgramSchedule? {
        if !scheduleJSON.isEmpty,
           let data = scheduleJSON.data(using: .utf8),
           let schedule = try? JSONDecoder().decode(ProgramSchedule.self, from: data) {
            return schedule
        }
        return ProgramCatalog.load(programId)
    }

    func saveSchedule(_ schedule: ProgramSchedule) {
        scheduleJSON = Self.encodeSchedule(schedule) ?? scheduleJSON
    }

    var pendingSchedule: ProgramSchedule? {
        get {
            try? JSONDecoder().decode(ProgramSchedule.self, from: Data(pendingScheduleJSON.utf8))
        }
        set {
            pendingScheduleJSON = newValue.flatMap { Self.encodeSchedule($0) } ?? ""
        }
    }

    func apply(_ advance: EngineAdvance) {
        let next = advance.applied(to: state)
        nextDayId = next.nextDayId
        weekIndex = next.weekIndex
        trainingSessionsCompleted = next.trainingSessionsCompleted
        deloadSessionsRemaining = next.deloadSessionsRemaining
        workingKgJSON = Self.encode(next.workingKg)
        tmJSON = Self.encode(next.tm)
        stallJSON = Self.encodeInt(next.stall)
        pendingTmJSON = Self.encode(next.pendingTmBump)
    }

    private static func encode(_ dict: [String: Double]) -> String {
        let data = (try? JSONEncoder().encode(dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func encodeInt(_ dict: [String: Int]) -> String {
        let data = (try? JSONEncoder().encode(dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func decode(_ json: String) -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: Data(json.utf8))) ?? [:]
    }

    private static func decodeInt(_ json: String) -> [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: Data(json.utf8))) ?? [:]
    }

    static func encodeSchedule(_ schedule: ProgramSchedule) -> String? {
        guard let data = try? JSONEncoder().encode(schedule) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setWorkingKg(_ id: String, _ kg: Double) {
        var map = Self.decode(workingKgJSON)
        map[id] = kg
        workingKgJSON = Self.encode(map)
    }

    func setTrainingMaxes(_ tm: [String: Double]) {
        tmJSON = Self.encode(tm)
    }

    // MARK: In-progress draft

    var hasDraft: Bool { !draftJSON.isEmpty }

    func saveDraft(_ sets: [CompletedSet], dayId: String) {
        if let data = try? JSONEncoder().encode(sets), let text = String(data: data, encoding: .utf8) {
            draftJSON = text
            draftDayId = dayId
            if draftStartedAt == nil { draftStartedAt = .now }
        }
    }

    func loadDraft() -> [CompletedSet]? {
        guard !draftJSON.isEmpty,
              let sets = try? JSONDecoder().decode([CompletedSet].self, from: Data(draftJSON.utf8)) else { return nil }
        return sets
    }

    func clearDraft() {
        draftJSON = ""
        draftDayId = ""
        draftStartedAt = nil
    }
}

@Model
final class WorkoutSession {
    var date: Date
    var programId: String
    var dayId: String
    var cycle: TrainingCycle?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var sets: [SetLog]

    init(date: Date = .now, programId: String, dayId: String, cycle: TrainingCycle?) {
        self.date = date
        self.programId = programId
        self.dayId = dayId
        self.cycle = cycle
        self.sets = []
    }
}

@Model
final class SetLog {
    var exerciseId: String
    var exerciseName: String
    var setIndex: Int
    var kg: Double
    var reps: Int
    var completed: Bool
    var isWorking: Bool
    var isAMRAP: Bool
    var isWarmup: Bool
    var isBBB: Bool
    /// Program-independent key (guide title) so history and PRs merge across programs.
    var liftKey: String = ""
    /// Position within the session, since to-many relationships are unordered.
    var orderIndex: Int = 0
    var date: Date = Date()
    var session: WorkoutSession?

    init(
        exerciseId: String,
        exerciseName: String,
        setIndex: Int,
        kg: Double,
        reps: Int,
        completed: Bool,
        isWorking: Bool,
        isAMRAP: Bool,
        isWarmup: Bool,
        isBBB: Bool,
        liftKey: String = "",
        orderIndex: Int = 0,
        date: Date = .now
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.kg = kg
        self.reps = reps
        self.completed = completed
        self.isWorking = isWorking
        self.isAMRAP = isAMRAP
        self.isWarmup = isWarmup
        self.isBBB = isBBB
        self.liftKey = liftKey
        self.orderIndex = orderIndex
        self.date = date
    }
}

@Model
final class PersonalRecord {
    var liftId: String
    var kg: Double
    var date: Date

    init(liftId: String, kg: Double, date: Date = .now) {
        self.liftId = liftId
        self.kg = kg
        self.date = date
    }
}

@Model
final class CustomRoutine {
    @Attribute(.unique) var programId: String
    var name: String
    var scheduleJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(programId: String, name: String, schedule: ProgramSchedule, createdAt: Date = .now) {
        self.programId = programId
        self.name = name
        self.scheduleJSON = TrainingCycle.encodeSchedule(schedule) ?? ""
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    func resolvedSchedule() -> ProgramSchedule? {
        guard let data = scheduleJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProgramSchedule.self, from: data)
    }

    func apply(_ schedule: ProgramSchedule) {
        name = schedule.name
        scheduleJSON = TrainingCycle.encodeSchedule(schedule) ?? scheduleJSON
        updatedAt = .now
    }
}

/// A user-made variant of a library exercise (brand + nickname). `other` variants carry no brand.
@Model
final class UserVariant {
    @Attribute(.unique) var id: String
    var exerciseId: String
    var brandId: String?
    var brandName: String?
    var nickname: String
    var plane: String
    var isHidden: Bool
    var createdAt: Date

    init(
        id: String,
        exerciseId: String,
        brandId: String? = nil,
        brandName: String? = nil,
        nickname: String,
        plane: String,
        isHidden: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.brandId = brandId
        self.brandName = brandName
        self.nickname = nickname
        self.plane = plane
        self.isHidden = isHidden
        self.createdAt = createdAt
    }
}
