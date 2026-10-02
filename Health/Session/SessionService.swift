import Foundation
import SwiftData
import os

enum SessionService {
    private static let logger = Logger(subsystem: "com.wooram.health", category: "session")

    static func prescribe(cycle: TrainingCycle, schedule: ProgramSchedule, profile: ProfileInputs) -> [PrescribedSet] {
        EngineRegistry.engine(for: cycle.programId).prescribe(schedule: schedule, profile: profile, state: cycle.state)
    }

    @discardableResult
    static func complete(
        context: ModelContext,
        cycle: TrainingCycle,
        schedule: ProgramSchedule,
        profile: ProfileInputs,
        rows: [PrescribedSet],
        logged: [CompletedSet]
    ) -> WorkoutSession {
        let engine = EngineRegistry.engine(for: cycle.programId)
        let session = WorkoutSession(programId: cycle.programId, dayId: cycle.nextDayId, cycle: cycle)
        // Insert the parent before wiring children: SwiftData relationships on
        // un-inserted models are the classic source of "different contexts" crashes.
        context.insert(session)
        let now = Date.now
        for (order, item) in logged.enumerated() {
            let row = rows.first(where: { $0.exerciseId == item.exerciseId && $0.setIndex == item.setIndex })
            let name = row?.exerciseName ?? item.exerciseId
            // Without its prescribed row the set has no variant id; never key a record by slot id or name.
            let key = row?.liftKey ?? ""
            if row == nil {
                logger.error("prSkippedNoRow(\(item.exerciseId, privacy: .public))")
            }
            let log = SetLog(
                exerciseId: item.exerciseId,
                exerciseName: name,
                setIndex: item.setIndex,
                kg: item.kg,
                reps: item.reps,
                completed: item.completed,
                isWorking: item.isWorking,
                isAMRAP: item.isAMRAP,
                isWarmup: item.isWarmup,
                isBBB: item.isBBB,
                liftKey: key,
                orderIndex: order,
                date: now
            )
            context.insert(log)
            log.session = session
            if !key.isEmpty, item.completed, item.isWorking, !item.isWarmup, item.reps >= 1 {
                updatePR(context: context, liftId: key, kg: item.kg, date: now)
            }
        }
        let completed = CompletedSession(dayId: cycle.nextDayId, sets: logged)
        let advance = engine.advance(schedule: schedule, profile: profile, state: cycle.state, session: completed)
        cycle.apply(advance)
        let pendingSchedule = cycle.pendingSchedule
        clearDraft(cycle: cycle)
        if let pendingSchedule {
            cycle.nextDayId = DayCursor.nextDayId(after: session.dayId, schedule: pendingSchedule)
        }
        return session
    }

    /// Starts `schedule`. If the active cycle already runs this program, it is kept
    /// (working weights, TMs and week survive) unless `restart` is set.
    @discardableResult
    static func startCycle(
        context: ModelContext,
        schedule: ProgramSchedule,
        profile: ProfileInputs,
        startingDayId: String? = nil,
        restart: Bool = false
    ) -> TrainingCycle {
        let existing = (try? context.fetch(FetchDescriptor<TrainingCycle>(predicate: #Predicate { $0.isActive }))) ?? []
        let validStart = startingDayId.flatMap { id in
            schedule.days.contains(where: { $0.id == id && !$0.isRest }) ? id : nil
        }
        if !restart, let current = existing.first(where: { $0.programId == schedule.id }) {
            existing.filter { $0 !== current }.forEach { $0.isActive = false }
            if let startingDayId { selectDay(cycle: current, dayId: startingDayId) }
            return current
        }
        existing.forEach { $0.isActive = false }
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        if let validStart { state.nextDayId = validStart }
        let cycle = TrainingCycle(programId: schedule.id, state: state, schedule: schedule)
        context.insert(cycle)
        return cycle
    }

    /// Recalculate only edited lifts, preserving progression for every other lift.
    static func syncTrainingMaxes(cycle: TrainingCycle?, profile: ProfileInputs, previousProfile: ProfileInputs) {
        guard let cycle, EngineRegistry.usesTrainingMax(cycle.programId) else { return }
        var tm = cycle.state.tm
        for (lift, value) in ProgramCatalog.trainingMaxes(for: profile)
        where profile.oneRM(forLift: lift) != previousProfile.oneRM(forLift: lift) {
            tm[lift] = value
        }
        cycle.setTrainingMaxes(tm)
    }

    static func selectDay(cycle: TrainingCycle, dayId: String) {
        guard !cycle.hasDraft,
              cycle.resolvedSchedule()?.days.contains(where: { $0.id == dayId && !$0.isRest }) == true else { return }
        cycle.nextDayId = dayId
    }

    static func replaceDayExercises(cycle: TrainingCycle, dayId: String, exercises: [ScheduleExercise]) {
        guard var schedule = cycle.pendingSchedule ?? cycle.resolvedSchedule(),
              let index = schedule.days.firstIndex(where: { $0.id == dayId }) else { return }
        schedule.days[index].exercises = exercises
        applyScheduleToCycle(cycle, schedule)
    }

    static func persistCustom(
        context: ModelContext,
        existing: CustomRoutine?,
        schedule: ProgramSchedule,
        cycle: TrainingCycle?
    ) -> CustomRoutine {
        let routine: CustomRoutine
        if let existing {
            existing.apply(schedule)
            routine = existing
        } else {
            routine = CustomRoutine(programId: schedule.id, name: schedule.name, schedule: schedule)
            context.insert(routine)
        }
        if let cycle, cycle.programId == routine.programId {
            applyScheduleToCycle(cycle, schedule)
        }
        return routine
    }

    static func applyScheduleToCycle(_ cycle: TrainingCycle, _ schedule: ProgramSchedule) {
        if cycle.hasDraft {
            cycle.pendingSchedule = schedule
            return
        }
        cycle.saveSchedule(schedule)
        if !schedule.days.contains(where: { $0.id == cycle.nextDayId && !$0.isRest }) {
            cycle.nextDayId = DayCursor.firstTrainingDayId(in: schedule)
        }
        for ex in schedule.days.flatMap(\.exercises) {
            if cycle.state.workingKg[ex.stateKey] == nil {
                cycle.setWorkingKg(ex.stateKey, ex.seedKg ?? 20)
            }
        }
    }

    static func clearDraft(cycle: TrainingCycle) {
        cycle.clearDraft()
        if let schedule = cycle.pendingSchedule {
            cycle.pendingSchedule = nil
            applyScheduleToCycle(cycle, schedule)
        }
    }

    static func syncCustomTemplate(context: ModelContext, cycle: TrainingCycle) {
        guard EngineRegistry.isCustom(cycle.programId),
              let schedule = cycle.pendingSchedule ?? cycle.resolvedSchedule() else { return }
        let pid = cycle.programId
        let found = try? context.fetch(FetchDescriptor<CustomRoutine>(predicate: #Predicate { $0.programId == pid }))
        found?.first?.apply(schedule)
    }

    /// Most recent completed working set for this variant (record key), across programs.
    /// Last completed working set of a variant; with `slotIds`, only sets logged from those slots.
    static func lastHint(context: ModelContext, liftKey: String, slotIds: [String]? = nil) -> (kg: Double, reps: Int)? {
        guard !liftKey.isEmpty else { return nil }
        let predicate: Predicate<SetLog>
        if let slotIds {
            predicate = #Predicate {
                $0.liftKey == liftKey && slotIds.contains($0.exerciseId) && $0.completed && $0.isWorking && !$0.isWarmup
            }
        } else {
            predicate = #Predicate { $0.liftKey == liftKey && $0.completed && $0.isWorking && !$0.isWarmup }
        }
        var descriptor = FetchDescriptor<SetLog>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.kg, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let log = try? context.fetch(descriptor).first else { return nil }
        return (log.kg, log.reps)
    }

    /// Session hints keyed by `PrescribedSet.exerciseId` and scoped by the slot's `stateKey`: a tagged slot
    /// (heavy/light, a/b, t1/t2) reads only sets logged from slots sharing its stateKey, so repeated slots of one
    /// variant don't show each other's numbers. Untagged slots, rows without a slot (TM engines) and tagged slots
    /// with no history yet fall back to the variant's last set.
    static func lastHints(context: ModelContext, rows: [PrescribedSet],
                          schedule: ProgramSchedule) -> [String: (kg: Double, reps: Int)] {
        let slots = schedule.days.flatMap(\.exercises)
        let slotById = Dictionary(slots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var map: [String: (kg: Double, reps: Int)] = [:]
        for row in rows where map[row.exerciseId] == nil {
            var hint: (kg: Double, reps: Int)?
            if let slot = slotById[row.exerciseId], slot.progressionTag != nil {
                let sameState = slots.filter { $0.stateKey == slot.stateKey }.map(\.id)
                hint = lastHint(context: context, liftKey: row.liftKey, slotIds: sameState)
            }
            if let found = hint ?? lastHint(context: context, liftKey: row.liftKey) {
                map[row.exerciseId] = found
            }
        }
        return map
    }

    static func personalRecordKg(context: ModelContext, liftKey: String) -> Double? {
        guard !liftKey.isEmpty else { return nil }
        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.liftId == liftKey },
            sortBy: [SortDescriptor(\.kg, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first?.kg
    }

    private static func updatePR(context: ModelContext, liftId: String, kg: Double, date: Date) {
        let existing = (try? context.fetch(FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.liftId == liftId }))) ?? []
        if let pr = existing.max(by: { $0.kg < $1.kg }) {
            if kg > pr.kg {
                pr.kg = kg
                pr.date = date
            }
        } else {
            context.insert(PersonalRecord(liftId: liftId, kg: kg, date: date))
        }
    }

    // MARK: Export

    struct ExportDocument: Codable {
        struct Profile: Codable { var bench1RM, squat1RM, dead1RM, ohp1RM: Double }
        struct Set: Codable {
            var exercise: String
            /// Variant id (record key).
            var liftId: String
            var setIndex: Int
            var kg: Double
            var reps: Int
            var completed: Bool
            var isWarmup: Bool
            var isAMRAP: Bool
        }
        struct Session: Codable {
            var date: Date
            var programId: String
            var dayId: String
            var sets: [Set]
        }
        /// `lift` is the display name, `liftId` the variant id.
        struct Record: Codable { var lift: String; var liftId: String; var kg: Double; var date: Date }
        var exportedAt: Date
        var profile: Profile?
        var sessions: [Session]
        var personalRecords: [Record]
    }

    static func exportJSON(context: ModelContext) throws -> Data {
        let profile = try context.fetch(FetchDescriptor<AthleteProfile>()).first
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        let prs = try context.fetch(FetchDescriptor<PersonalRecord>(sortBy: [SortDescriptor(\.liftId)]))
        let nicknames = Dictionary(try context.fetch(FetchDescriptor<UserVariant>()).map { ($0.id, $0.nickname) },
                                   uniquingKeysWith: { first, _ in first })
        let doc = ExportDocument(
            exportedAt: .now,
            profile: profile.map { .init(bench1RM: $0.bench1RM, squat1RM: $0.squat1RM, dead1RM: $0.dead1RM, ohp1RM: $0.ohp1RM) },
            sessions: sessions.map { session in
                .init(
                    date: session.date,
                    programId: session.programId,
                    dayId: session.dayId,
                    sets: session.sets.sorted { $0.orderIndex < $1.orderIndex }.map {
                        .init(exercise: $0.exerciseName, liftId: $0.liftKey, setIndex: $0.setIndex, kg: $0.kg, reps: $0.reps,
                              completed: $0.completed, isWarmup: $0.isWarmup, isAMRAP: $0.isAMRAP)
                    }
                )
            },
            personalRecords: prs.map {
                .init(lift: PRGrouping.rowTitle($0.liftId, nicknames: nicknames, library: .shared),
                      liftId: $0.liftId, kg: $0.kg, date: $0.date)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }
}

/// UI-independent today controller used by TodayView and Check 4 tests.
struct TodayController {
    var schedule: ProgramSchedule
    var profile: ProfileInputs
    var state: CycleState

    var engine: ProgressionEngine { EngineRegistry.engine(for: schedule.id) }

    var prescribed: [PrescribedSet] {
        engine.prescribe(schedule: schedule, profile: profile, state: state)
    }

    func completing(_ logged: [CompletedSet]) -> CycleState {
        let session = CompletedSession(dayId: state.nextDayId, sets: logged)
        return engine.advance(schedule: schedule, profile: profile, state: state, session: session).applied(to: state)
    }

    static func grouped(_ rows: [PrescribedSet]) -> [[PrescribedSet]] {
        var result: [[PrescribedSet]] = []
        for row in rows {
            if let last = result.indices.last, result[last].first?.groupId == row.groupId {
                result[last].append(row)
            } else {
                result.append([row])
            }
        }
        return result
    }

    static func loggedMatchingPrescribe(_ rows: [PrescribedSet]) -> [CompletedSet] {
        rows.map {
            CompletedSet(
                exerciseId: $0.exerciseId,
                setIndex: $0.setIndex,
                kg: $0.kg,
                reps: $0.reps,
                isWorking: $0.isWorking,
                isAMRAP: $0.isAMRAP,
                isWarmup: $0.isWarmup,
                isBBB: $0.isBBB,
                completed: true
            )
        }
    }
}
