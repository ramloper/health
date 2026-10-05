import XCTest
import SwiftData
@testable import Health

/// Stage 2 record-key migration: record key = variant id, progression key = stateKey (`variantId|tag`).
final class LibraryKeyTests: XCTestCase {
    private let profile = ProfileInputs.documentDefaults

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func bundled() throws -> [ProgramSchedule] {
        try ProgramCatalog.allIds.map(CatalogTests.schedule)
    }

    private func slots(_ schedule: ProgramSchedule) -> [ScheduleExercise] {
        schedule.days.flatMap(\.exercises)
    }

    /// 1.0 TodayView 1RM lookup by name substring, kept verbatim as the reference for the id table.
    private static func legacyOneRMLift(name n: String) -> String? {
        if n.contains("벤치") { return "bench" }
        if n.contains("스쿼트") { return "squat" }
        if n.contains("데드") { return "dead" }
        if n.contains("오버헤드") || n.contains("OHP") { return "ohp" }
        return nil
    }

    // MARK: Tag rule (bundled programs)

    func testBundledRepeatedVariantsHaveDistinctStateKeys() throws {
        let schedules = try bundled()
        XCTAssertEqual(schedules.count, 7)
        XCTAssertEqual(schedules.map { slots($0).count }.reduce(0, +), 135)
        for schedule in schedules {
            let all = slots(schedule)
            for slot in all {
                XCTAssertNotNil(ExerciseLibrary.shared.exercise(id: slot.exerciseId), "\(schedule.id)/\(slot.id)")
                XCTAssertEqual(slot.variantId, slot.exerciseId, "\(schedule.id)/\(slot.id): bundled slots use the generic variant")
                XCTAssertTrue(slot.stateKey.hasPrefix(slot.variantId))
            }
            for (variant, group) in Dictionary(grouping: all, by: \.variantId) where group.count >= 2 {
                if schedule.id == StartingStrengthEngine.id {
                    // 1.0 SS shares one squat slot between A and B; the bundled program keeps them merged.
                    XCTAssertTrue(group.allSatisfy { $0.progressionTag == nil }, "\(schedule.id): \(variant)")
                    continue
                }
                XCTAssertTrue(group.allSatisfy { $0.progressionTag != nil }, "\(schedule.id): \(variant) repeats untagged")
                XCTAssertEqual(Set(group.map(\.stateKey)).count, group.count, "\(schedule.id): \(variant) stateKeys collide")
            }
            for (key, group) in Dictionary(grouping: all, by: \.stateKey) {
                XCTAssertEqual(Set(group.map(\.repMin)).count, 1, "\(schedule.id): \(key) repMin")
                XCTAssertEqual(Set(group.map(\.repMax)).count, 1, "\(schedule.id): \(key) repMax")
                XCTAssertEqual(Set(group.map(\.seedKg)).count, 1, "\(schedule.id): \(key) seedKg")
            }
        }
    }

    // MARK: Copies

    func testCopiedProgramsKeepDistinctStateKeysPerSlot() throws {
        for source in try bundled() {
            let copy = ProgramSchedule.copiedAsCustom(from: source)
            let all = slots(copy)
            XCTAssertEqual(all.count, slots(source).count, source.id)
            XCTAssertEqual(Set(all.map(\.stateKey)).count, all.count, "\(source.id) copy shares a stateKey")

            // Every slot logs its own weight; any merged key would overwrite another slot's result.
            var weightBySlot: [String: Double] = [:]
            for (i, slot) in all.enumerated() { weightBySlot[slot.id] = 20 + 2.5 * Double(i) }
            let engine = EngineRegistry.engine(for: copy.id)
            XCTAssertTrue(engine is ClassBEngine, source.id)
            var state = ProgramCatalog.seededState(schedule: copy, profile: profile)
            var expected = state.workingKg
            for _ in 0..<3 {
                let day = try XCTUnwrap(copy.days.first { $0.id == state.nextDayId })
                let rows = engine.prescribe(schedule: copy, profile: profile, state: state)
                var logged = TodayController.loggedMatchingPrescribe(rows)
                for i in logged.indices { logged[i].kg = weightBySlot[logged[i].exerciseId] ?? 0 }
                state = engine.advance(schedule: copy, profile: profile, state: state,
                                       session: CompletedSession(dayId: day.id, sets: logged)).applied(to: state)
                for slot in day.exercises where slot.isWorking && slot.sets > 0 {
                    expected[slot.stateKey] = (weightBySlot[slot.id] ?? 0) + (slot.plane == "lower" ? 5 : 2.5)
                }
                XCTAssertEqual(state.workingKg, expected, source.id)
            }

            switch source.id {
            case NSuns5DayEngine.id:
                XCTAssertEqual(all.filter { $0.variantId == "squat" }.map(\.stateKey), ["squat|t1", "squat|t2"])
            case StartingStrengthEngine.id:
                XCTAssertEqual(all.filter { $0.variantId == "squat" }.map(\.stateKey), ["squat|a", "squat|b"])
                XCTAssertEqual(all.filter { $0.variantId != "squat" }.compactMap(\.progressionTag), [])
            case ClassBEngine.pplId:
                XCTAssertEqual(all.filter { $0.variantId == "bench" }.map(\.stateKey), ["bench|a", "bench|b"])
            default:
                break
            }
        }
    }

    func testCopyOfCustomRoutineDoesNotAutoTag() {
        var custom = ProgramSchedule.makeCustom(name: "두 번")
        custom.days = [
            ProgramDay(id: "d1", name: "1", isRest: false, exercises: [.makeCustom(exerciseId: "bench")]),
            ProgramDay(id: "d2", name: "2", isRest: false, exercises: [.makeCustom(exerciseId: "bench")])
        ]
        let copy = ProgramSchedule.copiedAsCustom(from: custom)
        XCTAssertEqual(slots(copy).map(\.stateKey), ["bench", "bench"])
    }

    // MARK: Training-max programs

    func testTrainingMaxSlotMapping() throws {
        let fto = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let ftoState = ProgramCatalog.seededState(schedule: fto, profile: profile)
        let ftoMap = ["squat": "squat", "bench": "bench", "dead": "deadlift", "press": "ohp"]
        XCTAssertEqual(Set(fto.days.map(\.id)), Set(ftoMap.keys))
        for day in fto.days {
            let expected = try XCTUnwrap(ftoMap[day.id])
            XCTAssertEqual(day.exercises.map(\.exerciseId), [expected], day.id)
            XCTAssertNil(day.exercises[0].progressionTag)
            XCTAssertNotNil(ftoState.tm[expected], "TM key for \(day.id)")
        }

        let ns = try CatalogTests.schedule(NSuns5DayEngine.id)
        let nsState = ProgramCatalog.seededState(schedule: ns, profile: profile)
        // dayId → (slot exerciseId, TM key). cap runs close-grip bench off the bench TM (Q5).
        let nsMap: [String: (String, String)] = [
            "cap": ("close-grip-bench", "bench"), "ohp": ("ohp", "ohp"), "dead": ("deadlift", "deadlift"),
            "bench": ("bench", "bench"), "squat": ("squat", "squat")
        ]
        XCTAssertEqual(Set(ns.days.map(\.id)), Set(nsMap.keys))
        for day in ns.days {
            let (exerciseId, tmKey) = try XCTUnwrap(nsMap[day.id])
            XCTAssertEqual(day.exercises.map(\.exerciseId), [exerciseId, exerciseId], day.id)
            XCTAssertEqual(day.exercises.map(\.progressionTag), ["t1", "t2"], day.id)
            XCTAssertEqual(day.exercises[1].label, "T2")
            XCTAssertNotNil(nsState.tm[tmKey], day.id)
            var state = nsState
            state.tm[tmKey] = 100
            state.nextDayId = day.id
            let rows = NSuns5DayEngine().prescribe(schedule: ns, profile: profile, state: state)
            XCTAssertEqual(rows.first(where: \.isAMRAP)?.kg, 95, "\(day.id) reads TM \(tmKey)")
        }
    }

    func testTrainingMaxRowsCarrySlotVariantLiftKey() throws {
        let ns = try CatalogTests.schedule(NSuns5DayEngine.id)
        let expected: [String: (t1: String, t2: String)] = [
            "cap": ("close-grip-bench", "close-grip-bench"), "bench": ("bench", "bench"),
            "squat": ("squat", "squat"), "dead": ("deadlift", "deadlift"), "ohp": ("ohp", "ohp")
        ]
        for day in ns.days {
            var state = ProgramCatalog.seededState(schedule: ns, profile: profile)
            state.nextDayId = day.id
            let rows = NSuns5DayEngine().prescribe(schedule: ns, profile: profile, state: state)
            let t2Slot = day.exercises[1].id
            let keys = try XCTUnwrap(expected[day.id])
            let t1 = rows.filter { $0.exerciseId != t2Slot }
            let t2 = rows.filter { $0.exerciseId == t2Slot }
            XCTAssertEqual(t1.count, 6)
            XCTAssertEqual(t2.count, 6)
            XCTAssertTrue(t1.allSatisfy { $0.liftKey == keys.t1 }, day.id)
            XCTAssertTrue(t2.allSatisfy { $0.liftKey == keys.t2 }, day.id)
        }

        let fto = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        for day in fto.days {
            var state = ProgramCatalog.seededState(schedule: fto, profile: profile)
            state.nextDayId = day.id
            let rows = FiveThreeOneBBBEngine().prescribe(schedule: fto, profile: profile, state: state)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertTrue(rows.allSatisfy { $0.liftKey == day.exercises[0].variantId }, day.id)
        }
    }

    // MARK: Determinism

    func testSameStateKeyTwiceInOneDayIsDeterministic() {
        var schedule = ProgramSchedule.makeCustom(name: "같은 운동 두 번")
        let heavy = ScheduleExercise.makeCustom(exerciseId: "bench", sets: 3, reps: 5, seedKg: 60)
        let light = ScheduleExercise.makeCustom(exerciseId: "bench", sets: 3, reps: 10, seedKg: 40)
        schedule.days[0].exercises = [heavy, light]
        let dayId = schedule.days[0].id
        XCTAssertEqual(heavy.stateKey, light.stateKey)

        let state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        XCTAssertEqual(state.workingKg, ["bench": 60], "first slot wins the seed")
        let rows = ClassBEngine(programId: schedule.id).prescribe(schedule: schedule, profile: profile, state: state)
        XCTAssertEqual(rows.count, 6)
        XCTAssertTrue(rows.allSatisfy { $0.kg == 60 && $0.liftKey == "bench" }, "shared weight (Q1)")

        var hit = TodayController.loggedMatchingPrescribe(rows)
        for i in hit.indices where hit[i].exerciseId == light.id { hit[i].kg = 50 }
        var miss = hit
        for i in miss.indices where miss[i].exerciseId == light.id { miss[i].reps = 8 }

        let engines: [ProgressionEngine] = [ClassBEngine(programId: schedule.id), Hypertrophy6DayEngine(), StartingStrengthEngine()]
        for engine in engines {
            for (logged, expected) in [(hit, 52.5), (miss, 50.0)] {
                var results = Set<Double>()
                for k in 0..<logged.count {
                    for order in [Array(logged[k...] + logged[..<k]), Array((logged[k...] + logged[..<k]).reversed())] {
                        let next = engine.advance(schedule: schedule, profile: profile, state: state,
                                                  session: CompletedSession(dayId: dayId, sets: order))
                        results.insert(next.workingKgByExerciseId["bench"] ?? -1)
                        XCTAssertEqual(next.workingKgByExerciseId.count, 1, "\(engine.programId): one key")
                    }
                }
                XCTAssertEqual(results, [expected], engine.programId)
            }
        }
    }

    // MARK: Session records

    @MainActor
    func testCompleteSkipsPRWhenRowMissing() throws {
        let context = try makeContext()
        var schedule = ProgramSchedule.makeCustom(name: "행 없음")
        schedule.days[0].exercises = [.makeCustom(exerciseId: "bench", sets: 2, reps: 5, seedKg: 60)]
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        let session = SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                              rows: [], logged: TodayController.loggedMatchingPrescribe(rows))
        XCTAssertEqual(session.sets.count, 2)
        XCTAssertTrue(session.sets.allSatisfy { $0.liftKey.isEmpty }, "no slot id or name as record key")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonalRecord>()).isEmpty)

        let again = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                rows: again, logged: TodayController.loggedMatchingPrescribe(again))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonalRecord>()).map(\.liftId), ["bench"])
    }

    @MainActor
    func testCompleteWritesVariantLiftKeyAndPR() throws {
        let context = try makeContext()
        let schedule = try CatalogTests.schedule(ClassBEngine.pplId)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
        let day = try XCTUnwrap(schedule.days.first { $0.id == cycle.nextDayId })
        XCTAssertEqual(day.id, "push-a")
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        let session = SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                              rows: rows, logged: TodayController.loggedMatchingPrescribe(rows))
        XCTAssertFalse(session.sets.isEmpty)
        for set in session.sets {
            let slot = try XCTUnwrap(day.exercises.first { $0.id == set.exerciseId })
            XCTAssertEqual(set.liftKey, slot.variantId, slot.id)
        }
        let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
        let working = day.exercises.filter(\.isWorking)
        XCTAssertEqual(Set(prs.map(\.liftId)), Set(working.map(\.variantId)))
        XCTAssertFalse(prs.contains { $0.liftId.contains("|") || $0.liftId.hasPrefix("ppl-") })
        let bench = try XCTUnwrap(day.exercises.first { $0.id == "ppl-bench" })
        let seed = try XCTUnwrap(bench.seedKg)
        XCTAssertEqual(prs.first { $0.liftId == "bench" }?.kg, seed)
        XCTAssertEqual(SessionService.personalRecordKg(context: context, liftKey: "bench"), seed)
        XCTAssertEqual(SessionService.lastHint(context: context, liftKey: "bench")?.kg, seed)
        // Progression lands on the slot's stateKey, never on the record key.
        XCTAssertEqual(cycle.state.workingKg["bench|a"], seed + 2.5)
        XCTAssertNil(cycle.state.workingKg["bench"])
    }

    /// AC8: two variants of one base exercise keep separate PRs and next prescriptions.
    @MainActor
    func testVariantKeyedProgressionIsSeparate() throws {
        let context = try makeContext()
        let base = "machine-chest-press"
        let hammer = "\(base)/hammer-plate-loaded"
        let technogym = "\(base)/technogym-selectorized"
        let library = ExerciseLibrary.shared
        XCTAssertEqual(library.variant(id: hammer)?.exerciseId, base)
        XCTAssertEqual(library.variant(id: technogym)?.exerciseId, base)
        var schedule = ProgramSchedule.makeCustom(name: "머신 두 대")
        schedule.days[0].exercises = [
            .makeCustom(exerciseId: base, variantId: hammer, sets: 3, reps: 10, seedKg: 60),
            .makeCustom(exerciseId: base, variantId: technogym, sets: 3, reps: 10, seedKg: 45)
        ]
        XCTAssertTrue(schedule.days[0].exercises[0].name.hasPrefix("해머스트렝스 "))
        XCTAssertTrue(schedule.days[0].exercises[1].name.hasPrefix("테크노짐 "))
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        XCTAssertEqual(Set(rows.filter { $0.liftKey == hammer }.map(\.kg)), [60])
        XCTAssertEqual(Set(rows.filter { $0.liftKey == technogym }.map(\.kg)), [45])
        SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                rows: rows, logged: TodayController.loggedMatchingPrescribe(rows))

        let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: prs.map { ($0.liftId, $0.kg) }), [hammer: 60, technogym: 45])
        let next = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        XCTAssertEqual(Set(next.filter { $0.liftKey == hammer }.map(\.kg)), [62.5])
        XCTAssertEqual(Set(next.filter { $0.liftKey == technogym }.map(\.kg)), [47.5])
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: hammer), ExerciseLibrary.baseId(ofVariant: technogym))
    }

    // MARK: 1RM display mapping

    func testOneRMMappingByExerciseId() throws {
        XCTAssertEqual(OneRMMap.mappedExerciseIds, [
            "bench", "close-grip-bench", "db-bench-press", "deadlift", "front-squat", "incline-bench", "ohp",
            "smith-bench-press", "smith-squat", "squat"
        ])
        for id in OneRMMap.mappedExerciseIds {
            XCTAssertNotNil(ExerciseLibrary.shared.exercise(id: id), id)
        }
        XCTAssertEqual(OneRMMap.lift(forExerciseId: "close-grip-bench"), "bench")
        XCTAssertEqual(OneRMMap.lift(forExerciseId: "front-squat"), "squat")
        XCTAssertEqual(OneRMMap.lift(forExerciseId: "deadlift"), "dead")
        XCTAssertNil(OneRMMap.lift(forExerciseId: "romanian-deadlift"))
        XCTAssertNil(OneRMMap.lift(forExerciseId: "decline-bench"))
        XCTAssertNil(OneRMMap.lift(forExerciseId: ExerciseLibrary.otherId))

        // Intended differences from the 1.0 name-substring mapping (slot key → old, new).
        let intended: [String: [String?]] = [
            "hypertrophy-6day/chest-a/overhead-extension": ["ohp", nil],
            "ppl-metallicadpa/push-a/ppl-oh-ext": ["ohp", nil],
            "ppl-metallicadpa/push-b/ppl-oh-ext-b": ["ohp", nil],
            "hypertrophy-6day/chest-b/light-flat": [nil, "bench"],
            "phul/upper-hyp/phul-uh-incline": [nil, "bench"],
            "nsuns-5day/ohp/ohp-t2": [nil, "ohp"],
            "ss-novice-lp/b/ohp": [nil, "ohp"]
        ]
        var differences: [String: [String?]] = [:]
        var count = 0
        for schedule in try bundled() {
            for day in schedule.days {
                for slot in day.exercises {
                    count += 1
                    let old = Self.legacyOneRMLift(name: slot.name)
                    let new = OneRMMap.lift(forExerciseId: slot.exerciseId)
                    if old != new { differences["\(schedule.id)/\(day.id)/\(slot.id)"] = [old, new] }
                }
            }
        }
        XCTAssertEqual(count, 135)
        XCTAssertEqual(differences, intended)
    }

    // MARK: `other`

    @MainActor
    func testOtherVariantFlowsThroughGuideHistoryAndSchedule() throws {
        let context = try makeContext()
        let other = ExerciseLibrary.otherId
        let variantId = "\(other)/u-\(UUID().uuidString)"
        let plane = PlaneGuess.guess("스쿼트 머신")
        XCTAssertEqual(plane, "lower")
        context.insert(UserVariant(id: variantId, exerciseId: other, nickname: "스쿼트 머신", plane: plane))

        let slot = ScheduleExercise.makeCustom(exerciseId: other, variantId: variantId, name: "스쿼트 머신",
                                               plane: plane, sets: 2, reps: 8, seedKg: 40)
        XCTAssertEqual(slot.plane, "lower")
        XCTAssertEqual(slot.isCompound, false)
        XCTAssertNil(slot.progressionTag)
        XCTAssertEqual(slot.liftKey, variantId)
        XCTAssertEqual(slot.stateKey, variantId)
        XCTAssertEqual(slot.displayName, "스쿼트 머신")

        let library = ExerciseLibrary.shared
        XCTAssertNil(library.exercise(id: other))
        XCTAssertEqual(library.info(for: other)?.isOther, true)
        XCTAssertNil(library.displayName(variantId: variantId))
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: variantId), other)
        XCTAssertNil(OneRMMap.lift(forExerciseId: other))

        let guide = GuideContent.make(exerciseId: other, variantId: variantId, fallbackName: slot.name)
        XCTAssertTrue(guide.isOther)
        XCTAssertTrue(guide.chips.isEmpty)
        XCTAssertEqual(guide.title, "스쿼트 머신")
        XCTAssertEqual(guide.summary, "직접 추가한 운동")
        XCTAssertNil(guide.detail)

        var schedule = ProgramSchedule.makeCustom(name: "기타 루틴")
        schedule.days[0].exercises = [slot]
        let routine = SessionService.persistCustom(context: context, existing: nil, schedule: schedule, cycle: nil)
        XCTAssertEqual(routine.resolvedSchedule(), schedule)

        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile)
        XCTAssertEqual(cycle.state.workingKg[variantId], 40)
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile)
        XCTAssertTrue(rows.allSatisfy { $0.liftKey == variantId })
        let session = SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile,
                                              rows: rows, logged: TodayController.loggedMatchingPrescribe(rows))
        XCTAssertTrue(session.sets.allSatisfy { $0.liftKey == variantId })
        let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertEqual(prs.map(\.liftId), [variantId])
        XCTAssertEqual(SessionService.lastHint(context: context, liftKey: variantId)?.kg, 40)
        XCTAssertEqual(cycle.state.workingKg[variantId], 45)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(SessionService.ExportDocument.self, from: SessionService.exportJSON(context: context))
        XCTAssertEqual(export.personalRecords.first?.liftId, variantId)
        XCTAssertEqual(export.personalRecords.first?.lift, "스쿼트 머신")
        XCTAssertEqual(export.sessions.first?.sets.first?.liftId, variantId)
    }

    // MARK: Codable

    func testScheduleRoundTripKeepsTagAndVariant() throws {
        for source in try bundled() {
            for schedule in [source, ProgramSchedule.copiedAsCustom(from: source)] {
                let json = try XCTUnwrap(TrainingCycle.encodeSchedule(schedule))
                let decoded = try JSONDecoder().decode(ProgramSchedule.self, from: Data(json.utf8))
                XCTAssertEqual(decoded, schedule, schedule.id)
                XCTAssertEqual(slots(decoded).map(\.stateKey), slots(schedule).map(\.stateKey))
                XCTAssertEqual(slots(decoded).map(\.label), slots(schedule).map(\.label))
            }
        }

        let ppl = try CatalogTests.schedule(ClassBEngine.pplId)
        let lateral = try XCTUnwrap(slots(ppl).first { $0.id == "ppl-lateral" })
        XCTAssertEqual(lateral.stateKey, "db-lateral-raise|a")
        let swapped = lateral.replacingVariant("machine-lateral-raise/u-1", name: "머신 레터럴",
                                               exerciseId: "machine-lateral-raise", plane: "upper")
        XCTAssertEqual(swapped.id, lateral.id)
        XCTAssertEqual(swapped.progressionTag, "a")
        XCTAssertEqual([swapped.sets, swapped.repMin, swapped.repMax], [lateral.sets, lateral.repMin, lateral.repMax])
        XCTAssertEqual(swapped.seedKg, lateral.seedKg)
        XCTAssertEqual(swapped.liftKey, "machine-lateral-raise/u-1")
        XCTAssertEqual(swapped.stateKey, "machine-lateral-raise/u-1|a")
        let swappedJSON = try JSONEncoder().encode(swapped)
        XCTAssertEqual(try JSONDecoder().decode(ScheduleExercise.self, from: swappedJSON), swapped)

        let minimal = #"{"id":"x","name":"벤치프레스","sets":3,"repMin":5,"repMax":5,"isWorking":true,"isOptional":false,"plane":"upper","exerciseId":"bench"}"#
        let decoded = try JSONDecoder().decode(ScheduleExercise.self, from: Data(minimal.utf8))
        XCTAssertEqual(decoded.variantId, "bench")
        XCTAssertNil(decoded.progressionTag)
        XCTAssertNil(decoded.label)
        // 1.0 schedules have no exerciseId and must not decode.
        let legacy = #"{"id":"x","name":"벤치프레스","sets":3,"repMin":5,"repMax":5,"isWorking":true,"isOptional":false,"plane":"upper"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ScheduleExercise.self, from: Data(legacy.utf8)))
    }
}
