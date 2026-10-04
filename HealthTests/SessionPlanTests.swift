import XCTest
import SwiftData
import UserNotifications
@testable import Health

/// Today-only session changes: extra exercises and order. They must never change the routine or its progression.
final class SessionPlanTests: XCTestCase {
    private let profile = ProfileInputs.documentDefaults

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func groupIds(_ rows: [PrescribedSet]) -> [String] {
        TodayController.grouped(rows).compactMap { $0.first?.groupId }
    }

    private func pplRows() throws -> (ProgramSchedule, CycleState, [PrescribedSet]) {
        let schedule = try CatalogTests.schedule(ClassBEngine.pplId)
        let state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let rows = ClassBEngine(programId: schedule.id).prescribe(schedule: schedule, profile: profile, state: state)
        return (schedule, state, rows)
    }

    // MARK: Rows

    func testEmptyPlanKeepsPrescribedRows() throws {
        let (_, _, rows) = try pplRows()
        XCTAssertEqual(SessionPlan().rows(prescribed: rows), rows)
        XCTAssertTrue(SessionPlan().isEmpty)
    }

    func testExtraRowsUseVariantRecordKeyAndComeLast() throws {
        let (_, _, rows) = try pplRows()
        var plan = SessionPlan()
        let extra = ScheduleExercise.makeCustom(exerciseId: "machine-chest-press",
                                                variantId: "machine-chest-press/hammer-plate-loaded",
                                                sets: 4, reps: 12, seedKg: 35)
        plan.add(extra)
        let all = plan.rows(prescribed: rows)
        XCTAssertEqual(Array(all.prefix(rows.count)), rows)
        let added = Array(all.suffix(4))
        XCTAssertEqual(added.map(\.exerciseId), Array(repeating: extra.id, count: 4))
        XCTAssertEqual(added.map(\.setIndex), [0, 1, 2, 3])
        XCTAssertTrue(added.allSatisfy { $0.liftKey == "machine-chest-press/hammer-plate-loaded" })
        XCTAssertTrue(added.allSatisfy { $0.kg == 35 && $0.reps == 12 && $0.isWorking && !$0.isWarmup && !$0.isAMRAP })
        XCTAssertEqual(groupIds(all).last, SessionPlan.groupId(for: extra))
        XCTAssertTrue(plan.isExtra(slotId: extra.id))
        XCTAssertFalse(rows.contains { $0.exerciseId == extra.id }, "fresh slot id")
    }

    func testMoveReordersGroupsAndKeepsSetsTogether() throws {
        let (_, _, rows) = try pplRows()
        let ids = groupIds(rows)
        XCTAssertGreaterThanOrEqual(ids.count, 3)
        var plan = SessionPlan()
        plan.move(groupIds: ids, index: 0, by: 1)
        let moved = plan.rows(prescribed: rows)
        XCTAssertEqual(groupIds(moved), [ids[1], ids[0]] + ids.dropFirst(2))
        XCTAssertEqual(Set(moved.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(moved.count, rows.count)
        for group in TodayController.grouped(moved) {
            XCTAssertEqual(group.map(\.setIndex), group.map(\.setIndex).sorted(), "sets stay in order inside a group")
        }
        // Out-of-range moves are ignored.
        var untouched = SessionPlan()
        untouched.move(groupIds: ids, index: 0, by: -1)
        untouched.move(groupIds: ids, index: ids.count - 1, by: 1)
        XCTAssertTrue(untouched.isEmpty)
    }

    func testGroupsMissingFromOrderGoLastInPrescribedOrder() throws {
        let (_, _, rows) = try pplRows()
        let ids = groupIds(rows)
        var plan = SessionPlan()
        plan.order = [ids[2], "gone-main"]
        XCTAssertEqual(groupIds(plan.rows(prescribed: rows)), [ids[2]] + ids.filter { $0 != ids[2] })
    }

    func testAddAfterReorderAppendsAndRemoveRestores() throws {
        let (_, _, rows) = try pplRows()
        let ids = groupIds(rows)
        var plan = SessionPlan()
        plan.move(groupIds: ids, index: 0, by: 1)
        let extra = ScheduleExercise.makeCustom(exerciseId: "crunch", sets: 2, reps: 15, seedKg: 0)
        plan.add(extra)
        XCTAssertEqual(groupIds(plan.rows(prescribed: rows)).last, SessionPlan.groupId(for: extra))
        plan.setExtraSets(slotId: extra.id, sets: 5)
        XCTAssertEqual(plan.rows(prescribed: rows).filter { $0.exerciseId == extra.id }.count, 5)
        plan.setExtraSets(slotId: extra.id, sets: 0)
        XCTAssertEqual(plan.rows(prescribed: rows).filter { $0.exerciseId == extra.id }.count, 1)
        plan.setExtraSets(slotId: extra.id, sets: 99)
        XCTAssertEqual(plan.rows(prescribed: rows).filter { $0.exerciseId == extra.id }.count, 10)
        plan.removeExtra(slotId: extra.id)
        XCTAssertTrue(plan.extras.isEmpty)
        XCTAssertEqual(groupIds(plan.rows(prescribed: rows)), [ids[1], ids[0]] + ids.dropFirst(2))
    }

    // MARK: Draft

    func testSyncedDraftKeepsEntriesAndFollowsRowOrder() throws {
        let (_, _, rows) = try pplRows()
        var draft = SessionPlan.syncedDraft([], rows: rows)
        XCTAssertEqual(draft.count, rows.count)
        XCTAssertTrue(draft.allSatisfy { !$0.completed })
        draft[0].completed = true
        draft[0].kg = 77.5
        var plan = SessionPlan()
        plan.move(groupIds: groupIds(rows), index: 0, by: 1)
        let extra = ScheduleExercise.makeCustom(exerciseId: "crunch", sets: 3, reps: 15, seedKg: 0)
        plan.add(extra)
        let next = plan.rows(prescribed: rows)
        let synced = SessionPlan.syncedDraft(draft, rows: next)
        XCTAssertEqual(synced.map { "\($0.exerciseId)-\($0.setIndex)" }, next.map(\.id))
        let kept = try XCTUnwrap(synced.first { $0.exerciseId == rows[0].exerciseId && $0.setIndex == rows[0].setIndex })
        XCTAssertTrue(kept.completed)
        XCTAssertEqual(kept.kg, 77.5)
        // Removing the extra drops its sets.
        plan.removeExtra(slotId: extra.id)
        XCTAssertFalse(SessionPlan.syncedDraft(synced, rows: plan.rows(prescribed: rows)).contains { $0.exerciseId == extra.id })
    }

    @MainActor
    func testDraftStoresPlanAndStaysReadableAsPlainSets() throws {
        let context = try makeContext()
        let schedule = try CatalogTests.schedule(ClassBEngine.pplId)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        let sets = TodayController.loggedMatchingPrescribe(rows)

        // No today-only changes: the 1.0 format (plain array).
        cycle.saveDraft(sets, dayId: cycle.nextDayId)
        XCTAssertTrue(cycle.draftJSON.hasPrefix("["))
        XCTAssertEqual(cycle.loadDraft(), sets)
        XCTAssertTrue(cycle.loadDraftPlan().isEmpty)

        var plan = SessionPlan()
        plan.move(groupIds: groupIds(rows), index: 0, by: 1)
        plan.add(.makeCustom(exerciseId: "crunch", sets: 2, reps: 15, seedKg: 0))
        let full = SessionPlan.syncedDraft(sets, rows: plan.rows(prescribed: rows))
        cycle.saveDraft(full, dayId: cycle.nextDayId, plan: plan)
        XCTAssertTrue(cycle.hasDraft)
        XCTAssertEqual(cycle.loadDraft(), full)
        XCTAssertEqual(cycle.loadDraftPlan(), plan)
        // Restoring rebuilds exactly the rows the draft was saved for.
        XCTAssertEqual(cycle.loadDraftPlan().rows(prescribed: rows).map(\.id),
                       full.map { "\($0.exerciseId)-\($0.setIndex)" })
        cycle.clearDraft()
        XCTAssertTrue(cycle.loadDraftPlan().isEmpty)
    }

    // MARK: Navigation

    func testNextOpenGroupSkipsDoneAndWrapsToSkipped() throws {
        let (_, _, rows) = try pplRows()
        let groups = TodayController.grouped(rows)
        let ids = groups.compactMap { $0.first?.groupId }
        var done = Set<String>()
        let isDone: (PrescribedSet) -> Bool = { done.contains($0.groupId) }

        XCTAssertEqual(SessionPlan.nextOpenGroup(groups: groups, currentId: ids[0], isDone: isDone)?.first?.groupId, ids[1])
        // Group 1 was skipped (machine taken); 2... are done: after the last one, come back to group 1.
        done = Set(ids).subtracting([ids[1]])
        XCTAssertEqual(SessionPlan.nextOpenGroup(groups: groups, currentId: ids.last, isDone: isDone)?.first?.groupId, ids[1])
        XCTAssertEqual(SessionPlan.nextOpenGroup(groups: groups, currentId: ids[0], isDone: isDone)?.first?.groupId, ids[1])
        // The current group is never its own "next".
        XCTAssertNil(SessionPlan.nextOpenGroup(groups: groups, currentId: ids[1], isDone: isDone))
        done = Set(ids)
        XCTAssertNil(SessionPlan.nextOpenGroup(groups: groups, currentId: ids[0], isDone: isDone))
        XCTAssertNil(SessionPlan.nextOpenGroup(groups: [], currentId: nil, isDone: isDone))
    }

    // MARK: Completion

    /// Extras and a changed order are logged, but progression is exactly what the plain session produces.
    @MainActor
    func testCompleteWithExtrasAndReorderLeavesProgressionUntouched() throws {
        for programId in ProgramCatalog.allIds {
            let schedule = try CatalogTests.schedule(programId)

            let plainContext = try makeContext()
            let plainCycle = SessionService.startCycle(context: plainContext, schedule: schedule, profile: profile)
            let plainRows = SessionService.prescribe(cycle: plainCycle, schedule: schedule, profile: profile)
            SessionService.complete(context: plainContext, cycle: plainCycle, schedule: schedule, profile: profile,
                                    rows: plainRows, logged: TodayController.loggedMatchingPrescribe(plainRows))

            let context = try makeContext()
            let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
            let prescribed = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
            XCTAssertEqual(prescribed, plainRows, programId)
            var plan = SessionPlan()
            let extra = ScheduleExercise.makeCustom(exerciseId: "machine-leg-extension",
                                                    variantId: "machine-leg-extension/technogym-selectorized",
                                                    sets: 3, reps: 12, seedKg: 45)
            plan.add(extra)
            let ids = groupIds(plan.rows(prescribed: prescribed))
            plan.order = ids.reversed()
            let rows = plan.rows(prescribed: prescribed)
            XCTAssertEqual(groupIds(rows), ids.reversed(), programId)
            let logged = TodayController.loggedMatchingPrescribe(rows)
            let session = SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                                  rows: rows, logged: logged)

            XCTAssertEqual(cycle.state, plainCycle.state, "\(programId): progression must not see extras or order")
            XCTAssertFalse(cycle.state.workingKg.keys.contains { $0.hasPrefix("machine-leg-extension/") }, programId)
            let extraLogs = session.sets.filter { $0.exerciseId == extra.id }
            XCTAssertEqual(extraLogs.count, 3, programId)
            XCTAssertTrue(extraLogs.allSatisfy { $0.liftKey == "machine-leg-extension/technogym-selectorized" && $0.kg == 45 })
            XCTAssertTrue(extraLogs.allSatisfy { !$0.exerciseName.isEmpty && $0.completed })
            // History keeps the order the workout was done in.
            XCTAssertEqual(session.sets.sorted { $0.orderIndex < $1.orderIndex }.map(\.exerciseId), logged.map(\.exerciseId),
                           programId)
            let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
            XCTAssertEqual(prs.first { $0.liftId == "machine-leg-extension/technogym-selectorized" }?.kg, 45, programId)
            // The routine itself is unchanged.
            XCTAssertEqual(cycle.resolvedSchedule(), schedule, programId)
            XCTAssertFalse(cycle.hasDraft, programId)
        }
    }

    // MARK: Rest alarm

    func testRestNotificationIsPresentedWhileAppIsOnScreen() {
        XCTAssertTrue(RestAlertPresenter.foregroundOptions.contains(.sound))
        XCTAssertTrue(RestAlertPresenter.foregroundOptions.contains(.banner))
        XCTAssertTrue(UNUserNotificationCenter.current().delegate === RestAlertPresenter.shared,
                      "the app installs the presenter at launch")
    }
}
