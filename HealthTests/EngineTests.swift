import XCTest
import SwiftData
@testable import Health

final class KgTests: XCTestCase {
    func testNearestTiesTowardZero() {
        XCTAssertEqual(Kg.nearest(33.75), 32.5)
        XCTAssertEqual(Kg.nearest(57.375), 57.5)
        XCTAssertEqual(Kg.trainingMax(fromOneRM: 75), 67.5)
    }
}

final class CatalogTests: XCTestCase {
    func testLoadsSevenSchedulesWithoutMathFields() throws {
        for id in ProgramCatalog.allIds {
            let data = try XCTUnwrap(Self.jsonData(id))
            let text = String(data: data, encoding: .utf8) ?? ""
            XCTAssertFalse(text.lowercased().contains("percent"))
            XCTAssertFalse(text.contains("increment"))
            let schedule = try ProgramCatalog.decode(data)
            XCTAssertEqual(schedule.id, id)
        }
    }

    static func jsonData(_ id: String) -> Data? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Health/Resources/Programs/\(id).json")
        return try? Data(contentsOf: url)
    }

    static func schedule(_ id: String) throws -> ProgramSchedule {
        guard let data = jsonData(id) else {
            throw NSError(domain: "CatalogTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(id).json"])
        }
        return try ProgramCatalog.decode(data)
    }
}

final class SixDayTests: XCTestCase {
    func testBenchAndSquatBumpAndMiss() throws {
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        XCTAssertEqual(state.nextDayId, "chest-a")
        let engine = Hypertrophy6DayEngine()
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let bench = rows.filter { $0.exerciseId == "bench" }
        XCTAssertEqual(bench.count, 4)
        XCTAssertEqual(bench.first?.kg, 55)
        var logged = TodayController.loggedMatchingPrescribe(rows)
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "chest-a", sets: logged)).applied(to: state)
        XCTAssertEqual(state.workingKg["bench"], 57.5)

        state.nextDayId = "chest-a"
        var miss = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: profile, state: state))
        for i in miss.indices where miss[i].exerciseId == "bench" {
            miss[i].reps = 6
        }
        let afterMiss = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "chest-a", sets: miss)).applied(to: state)
        XCTAssertEqual(afterMiss.workingKg["bench"], 57.5)
    }

    func testSquatPlusFive() throws {
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        state.nextDayId = "legs-a"
        let engine = Hypertrophy6DayEngine()
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        XCTAssertEqual(rows.filter { $0.exerciseId == "squat" }.first?.kg, 80)
        let logged = TodayController.loggedMatchingPrescribe(rows)
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "legs-a", sets: logged)).applied(to: state)
        XCTAssertEqual(state.workingKg["squat"], 85)
    }

    func testDeloadAfter30() throws {
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let engine = Hypertrophy6DayEngine()
        for _ in 0..<30 {
            let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
            let logged = TodayController.loggedMatchingPrescribe(rows)
            state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: state.nextDayId, sets: logged)).applied(to: state)
        }
        XCTAssertEqual(state.deloadSessionsRemaining, 6)
        let deloadRows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let normal = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let full = engine.prescribe(schedule: schedule, profile: profile, state: {
            var s = normal
            s.nextDayId = state.nextDayId
            return s
        }())
        let fullCount = Dictionary(grouping: full, by: \.exerciseId).mapValues(\.count)
        let deloadCount = Dictionary(grouping: deloadRows, by: \.exerciseId).mapValues(\.count)
        for (id, n) in fullCount {
            XCTAssertEqual(deloadCount[id] ?? 0, Int(ceil(Double(n) / 2.0)))
        }
    }
}

final class FiveThreeOneTests: XCTestCase {
    func testWeek1BenchOraclesAndW1DoesNotBumpTM() throws {
        let schedule = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        XCTAssertEqual(state.tm["bench"], 67.5)
        state.nextDayId = "bench"
        let engine = FiveThreeOneBBBEngine()
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let work = rows.filter { $0.isWorking && !$0.isBBB }
        XCTAssertEqual(work.map(\.kg), [45, 50, 57.5])
        let bbb = rows.filter(\.isBBB)
        XCTAssertEqual(bbb.count, 5)
        XCTAssertTrue(bbb.allSatisfy { $0.kg == 32.5 && $0.reps == 10 })
        let logged = TodayController.loggedMatchingPrescribe(rows)
        let after = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "bench", sets: logged)).applied(to: state)
        XCTAssertEqual(after.tm["bench"], 67.5)
        XCTAssertEqual(rows, engine.prescribe(schedule: schedule, profile: profile, state: state))
    }

    func testW3AmrapBumpsAfterCycle() throws {
        let schedule = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let engine = FiveThreeOneBBBEngine()
        state.weekIndex = 3
        state.nextDayId = "bench"
        var logged = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: profile, state: state))
        if let i = logged.firstIndex(where: \.isAMRAP) { logged[i].reps = 3 }
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "bench", sets: logged)).applied(to: state)
        XCTAssertEqual(state.pendingTmBump["bench"], 2.5)
        state.weekIndex = 4
        state.nextDayId = "press"
        state.trainingSessionsCompleted = 3 // fourth session of the week closes it

        let last = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: profile, state: state))
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "press", sets: last)).applied(to: state)
        XCTAssertEqual(state.weekIndex, 1)
        XCTAssertEqual(state.tm["bench"], 70)
        XCTAssertTrue(state.pendingTmBump.isEmpty)
    }

    func testW3MissNoBump() throws {
        let schedule = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let engine = FiveThreeOneBBBEngine()
        state.weekIndex = 3
        state.nextDayId = "bench"
        var logged = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: profile, state: state))
        if let i = logged.firstIndex(where: \.isAMRAP) { logged[i].reps = 0; logged[i].completed = true }
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "bench", sets: logged)).applied(to: state)
        XCTAssertNil(state.pendingTmBump["bench"])
    }
}

final class NSunsTests: XCTestCase {
    func testBenchDayAMRAP() throws {
        let schedule = try CatalogTests.schedule(NSuns5DayEngine.id)
        var profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        state.tm["bench"] = 100
        state.nextDayId = "bench"
        let engine = NSuns5DayEngine()
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let t1Amrap = try XCTUnwrap(rows.first(where: { $0.exerciseId == "bench" && $0.isAMRAP }))
        XCTAssertEqual(t1Amrap.kg, 95)
        var logged = TodayController.loggedMatchingPrescribe(rows)
        if let i = logged.firstIndex(where: { $0.exerciseId == "bench" && $0.isAMRAP }) {
            logged[i].reps = 6
        }
        state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "bench", sets: logged)).applied(to: state)
        XCTAssertEqual(state.tm["bench"], 105)
    }
}

final class SSTests: XCTestCase {
    func testSuccessMissStall() throws {
        let schedule = try CatalogTests.schedule(StartingStrengthEngine.id)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        XCTAssertEqual(state.nextDayId, "a")
        let engine = StartingStrengthEngine()
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        XCTAssertEqual(rows.filter { $0.exerciseId == "squat" }.map(\.reps), [5, 5, 5])
        XCTAssertEqual(Set(rows.map(\.exerciseId)), Set(["squat", "bench", "deadlift"]))
        let logged = TodayController.loggedMatchingPrescribe(rows)
        let afterSuccess = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: "a", sets: logged)).applied(to: state)
        XCTAssertEqual(afterSuccess.workingKg["squat"], 85)

        var stallState = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        for n in 1...3 {
            stallState.nextDayId = "a"
            var fail = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: profile, state: stallState))
            for i in fail.indices where fail[i].exerciseId == "squat" { fail[i].reps = 3 }
            stallState = engine.advance(schedule: schedule, profile: profile, state: stallState, session: CompletedSession(dayId: "a", sets: fail)).applied(to: stallState)
            if n < 3 {
                XCTAssertEqual(stallState.workingKg["squat"], 80)
                XCTAssertEqual(stallState.stall["squat"], n)
            }
        }
        XCTAssertEqual(stallState.workingKg["squat"], 72.5)
        XCTAssertEqual(stallState.stall["squat"], 0)
    }
}

final class ClassBTests: XCTestCase {
    func testPPLNotChestAAndNoDeload() throws {
        let schedule = try CatalogTests.schedule(ClassBEngine.pplId)
        XCTAssertEqual(schedule.days.first?.id, "push-a")
        XCTAssertNotEqual(schedule.days.first?.id, "chest-a")
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let engine = ClassBEngine(programId: ClassBEngine.pplId)
        let first = engine.prescribe(schedule: schedule, profile: profile, state: state)
        XCTAssertGreaterThan(first.count, 1)
        for _ in 0..<30 {
            let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
            state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: state.nextDayId, sets: TodayController.loggedMatchingPrescribe(rows))).applied(to: state)
        }
        state.nextDayId = "push-a"
        let after = engine.prescribe(schedule: schedule, profile: profile, state: state)
        XCTAssertEqual(after.filter { $0.exerciseId == "ppl-bench" }.count, 3)
        XCTAssertEqual(state.deloadSessionsRemaining, 0)
    }

    func testPHULPowerRangeAndNoDeload() throws {
        let schedule = try CatalogTests.schedule(ClassBEngine.phulId)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        XCTAssertEqual(state.nextDayId, "upper-power")
        let engine = ClassBEngine(programId: ClassBEngine.phulId)
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let bench = rows.filter { $0.exerciseId == "phul-bench" }
        XCTAssertEqual(bench.first?.repMax, 5)
        XCTAssertEqual(bench.first?.reps, 5)
        XCTAssertLessThanOrEqual(bench.first?.repMax ?? 99, 5)
        for _ in 0..<30 {
            let r = engine.prescribe(schedule: schedule, profile: profile, state: state)
            state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: state.nextDayId, sets: TodayController.loggedMatchingPrescribe(r))).applied(to: state)
        }
        state.nextDayId = "upper-power"
        XCTAssertEqual(engine.prescribe(schedule: schedule, profile: profile, state: state).filter { $0.exerciseId == "phul-bench" }.count, 3)
    }

    func testUpperLowerCompoundScheme() throws {
        let schedule = try CatalogTests.schedule(ClassBEngine.ulId)
        let profile = ProfileInputs.documentDefaults
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        let engine = ClassBEngine(programId: ClassBEngine.ulId)
        let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
        let bench = rows.filter { $0.exerciseId == "ul-bench" }
        XCTAssertEqual(bench.count, 4)
        XCTAssertEqual(bench.first?.repMax, 8)
        for _ in 0..<30 {
            let r = engine.prescribe(schedule: schedule, profile: profile, state: state)
            state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: state.nextDayId, sets: TodayController.loggedMatchingPrescribe(r))).applied(to: state)
        }
        state.nextDayId = "upper-a"
        XCTAssertEqual(engine.prescribe(schedule: schedule, profile: profile, state: state).filter { $0.exerciseId == "ul-bench" }.count, 4)
    }
}

final class TodayWiringTests: XCTestCase {
    func testSuggestedEqualsPrescribeAndCompleteAppliesAdvance() throws {
        let cases: [(String, (TodayController) -> Void)] = [
            (Hypertrophy6DayEngine.id, { ctl in
                XCTAssertEqual(ctl.prescribed.filter { $0.exerciseId == "bench" }.first?.kg, 55)
            }),
            (FiveThreeOneBBBEngine.id, { ctl in
                var c = ctl
                c.state.nextDayId = "bench"
                let rows = c.prescribed
                XCTAssertEqual(rows.filter { $0.isWorking && !$0.isBBB }.map(\.kg), [45, 50, 57.5])
                XCTAssertEqual(rows.filter(\.isBBB).map(\.kg), Array(repeating: 32.5, count: 5))
            }),
            (NSuns5DayEngine.id, { ctl in
                var c = ctl
                c.state.tm["bench"] = 100
                c.state.nextDayId = "bench"
                XCTAssertEqual(c.prescribed.first(where: { $0.exerciseId == "bench" && $0.isAMRAP })?.kg, 95)
            }),
            (StartingStrengthEngine.id, { ctl in
                XCTAssertEqual(ctl.prescribed.filter { $0.exerciseId == "squat" }.map(\.reps), [5, 5, 5])
            }),
            (ClassBEngine.pplId, { ctl in
                XCTAssertEqual(ctl.state.nextDayId, "push-a")
                XCTAssertGreaterThan(ctl.prescribed.count, 3)
            }),
            (ClassBEngine.phulId, { ctl in
                XCTAssertEqual(ctl.prescribed.filter { $0.exerciseId == "phul-bench" }.first?.repMax, 5)
            }),
            (ClassBEngine.ulId, { ctl in
                XCTAssertEqual(ctl.prescribed.filter { $0.exerciseId == "ul-bench" }.count, 4)
            })
        ]
        for (id, extra) in cases {
            let schedule = try CatalogTests.schedule(id)
            let profile = ProfileInputs.documentDefaults
            let state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
            let ctl = TodayController(schedule: schedule, profile: profile, state: state)
            extra(ctl)
            var working = ctl
            if id == FiveThreeOneBBBEngine.id { working.state.nextDayId = "bench" }
            if id == NSuns5DayEngine.id {
                working.state.nextDayId = "bench"
                working.state.tm["bench"] = 100
            }
            let rows = working.prescribed
            XCTAssertFalse(rows.isEmpty, id)
            let logged = TodayController.loggedMatchingPrescribe(rows)
            let next = working.completing(logged)
            XCTAssertNotEqual(next.trainingSessionsCompleted, state.trainingSessionsCompleted)
        }
    }

    func testProgramSwitchResetsCycle() throws {
        let six = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let ppl = try CatalogTests.schedule(ClassBEngine.pplId)
        let a = ProgramCatalog.seededState(schedule: six, profile: .documentDefaults)
        let b = ProgramCatalog.seededState(schedule: ppl, profile: .documentDefaults)
        XCTAssertEqual(a.nextDayId, "chest-a")
        XCTAssertEqual(b.nextDayId, "push-a")
        XCTAssertNotEqual(a.programId, b.programId)
    }
}

final class EditDayTests: XCTestCase {
    func testReplacingChestAExercisesChangesPrescribe() throws {
        var schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let custom = ScheduleExercise(
            id: "custom-fly",
            name: "플라이",
            sets: 3,
            repMin: 12,
            repMax: 15,
            isWorking: true,
            isOptional: false,
            plane: "upper",
            seedKg: 12
        )
        guard let idx = schedule.days.firstIndex(where: { $0.id == "chest-a" }) else {
            return XCTFail("chest-a missing")
        }
        schedule.days[idx].exercises = [custom]
        var state = ProgramCatalog.seededState(schedule: schedule, profile: .documentDefaults)
        state.nextDayId = "chest-a"
        let rows = Hypertrophy6DayEngine().prescribe(schedule: schedule, profile: .documentDefaults, state: state)
        XCTAssertEqual(rows.map(\.exerciseId), ["custom-fly", "custom-fly", "custom-fly"])
        XCTAssertEqual(rows.first?.kg, 12)
    }
}

final class GuideTests: XCTestCase {
    func testChestSupportedRowAndFacePullHaveCues() {
        let row = ExerciseGuide.lookup(name: "체스트서포트 로우")
        XCTAssertTrue(row.summary.contains("가슴"))
        XCTAssertFalse(row.steps.isEmpty)
        let pull = ExerciseGuide.lookup(name: "페이스풀")
        XCTAssertTrue(pull.muscle.contains("후면") || pull.muscle.contains("삼각"))
        let ohp = ExerciseGuide.lookup(name: "OHP")
        XCTAssertEqual(ohp.title, "오버헤드 프레스 (OHP)")
    }

    func testCatalogTitlesAndDefaultPlane() {
        XCTAssertTrue(ExerciseGuide.catalogTitles.contains("벤치프레스"))
        XCTAssertEqual(ExerciseGuide.defaultPlane(for: "스쿼트"), "lower")
        XCTAssertEqual(ExerciseGuide.defaultPlane(for: "벤치프레스"), "upper")
    }

    func testPickerGroups() {
        XCTAssertEqual(ExerciseGuide.group(for: "복근"), "코어")
        XCTAssertEqual(ExerciseGuide.group(for: "체스트서포트 로우"), "등")
        XCTAssertEqual(ExerciseGuide.group(for: "페이스풀"), "어깨")
        XCTAssertEqual(ExerciseGuide.group(for: "리어델트 플라이"), "어깨")
        XCTAssertEqual(ExerciseGuide.group(for: "클로즈그립 벤치"), "팔")
        XCTAssertEqual(ExerciseGuide.group(for: "오버헤드 익스텐션"), "팔")
        XCTAssertEqual(ExerciseGuide.group(for: "레그 익스텐션"), "하체")
        XCTAssertEqual(ExerciseGuide.group(for: "OHP"), "어깨")
        XCTAssertEqual(ExerciseGuide.group(for: "딥스"), "가슴")
        XCTAssertEqual(ExerciseGuide.group(for: "슈러그"), "등")
        XCTAssertEqual(ExerciseGuide.group(for: "데드리프트"), "하체")
        let expected: [String: String] = [
            "벤치프레스": "가슴",
            "인클라인 프레스": "가슴",
            "케이블/펙덱 플라이": "가슴",
            "라이트 플랫 덤벨 프레스": "가슴",
            "딥스": "가슴",
            "랫풀다운": "등",
            "체스트서포트 로우": "등",
            "스트레이트암 풀다운": "등",
            "슈러그": "등",
            "바벨로우": "등",
            "시티드 케이블 로우": "등",
            "파워클린 (대체: 펜들레이 로우)": "등",
            "사이드 레터럴": "어깨",
            "오버헤드 프레스 (OHP)": "어깨",
            "페이스풀": "어깨",
            "리어델트 플라이": "어깨",
            "트라이셉스 푸시다운": "팔",
            "오버헤드 익스텐션": "팔",
            "컬": "팔",
            "해머컬": "팔",
            "프리처 컬": "팔",
            "클로즈그립 벤치": "팔",
            "스쿼트": "하체",
            "프론트 스쿼트": "하체",
            "레그프레스": "하체",
            "레그 익스텐션": "하체",
            "레그컬": "하체",
            "카프 레이즈": "하체",
            "데드리프트": "하체",
            "RDL (루마니안 데드)": "하체",
            "힙 쓰러스트": "하체",
            "런지": "하체",
            "복근": "코어"
        ]
        for title in ExerciseGuide.catalogTitles {
            XCTAssertEqual(ExerciseGuide.group(for: title), expected[title], title)
        }
    }
}

final class CustomRoutineTests: XCTestCase {
    func testCustomIdUsesClassBNotSixDay() {
        let engine = EngineRegistry.engine(for: "custom-abc")
        XCTAssertEqual(engine.programId, "custom-abc")
        XCTAssertTrue(engine is ClassBEngine)
        XCTAssertEqual(EngineRegistry.engine(for: Hypertrophy6DayEngine.id).programId, Hypertrophy6DayEngine.id)
    }

    func testMakeAndCopyCustomSchedule() throws {
        let blank = ProgramSchedule.makeCustom(name: "집 루틴")
        XCTAssertTrue(blank.isCustom)
        XCTAssertEqual(blank.name, "집 루틴")
        XCTAssertEqual(blank.days.count, 1)
        XCTAssertFalse(blank.days[0].isRest)

        let ppl = try CatalogTests.schedule(ClassBEngine.pplId)
        let copy = ProgramSchedule.copiedAsCustom(from: ppl)
        XCTAssertTrue(copy.isCustom)
        XCTAssertNotEqual(copy.id, ppl.id)
        XCTAssertEqual(DayCursor.trainingDays(in: copy).count, DayCursor.trainingDays(in: ppl).count)
        XCTAssertEqual(copy.days.first?.exercises.first?.name, ppl.days.first?.exercises.first?.name)
        XCTAssertNotEqual(copy.days.first?.exercises.first?.id, ppl.days.first?.exercises.first?.id)
        XCTAssertTrue(copy.name.contains("내 루틴"))
    }

    func testCustomPrescribeAndDoubleProgression() {
        let schedule = ProgramSchedule(
            id: "custom-test",
            name: "테스트",
            days: [
                ProgramDay(id: "d1", name: "가슴", isRest: false, exercises: [
                    ScheduleExercise.makeCustom(name: "벤치프레스", sets: 3, reps: 12, seedKg: 50)
                ]),
                ProgramDay(id: "d2", name: "등", isRest: false, exercises: [
                    ScheduleExercise.makeCustom(name: "랫풀다운", sets: 3, reps: 12, seedKg: 40)
                ])
            ]
        )
        let benchId = schedule.days[0].exercises[0].id
        XCTAssertEqual(ExerciseGuide.defaultPlane(for: "벤치프레스"), "upper")
        let engine = EngineRegistry.engine(for: schedule.id)
        var state = ProgramCatalog.seededState(schedule: schedule, profile: .documentDefaults)
        XCTAssertEqual(state.nextDayId, "d1")
        XCTAssertEqual(state.workingKg[benchId], 50)
        let rows = engine.prescribe(schedule: schedule, profile: .documentDefaults, state: state)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows.allSatisfy { $0.kg == 50 && $0.reps == 12 })
        let afterHit = engine.advance(
            schedule: schedule,
            profile: .documentDefaults,
            state: state,
            session: CompletedSession(dayId: "d1", sets: TodayController.loggedMatchingPrescribe(rows))
        ).applied(to: state)
        XCTAssertEqual(afterHit.workingKg[benchId], 52.5)
        XCTAssertEqual(afterHit.nextDayId, "d2")
        XCTAssertEqual(afterHit.deloadSessionsRemaining, 0)

        state.nextDayId = "d1"
        var miss = TodayController.loggedMatchingPrescribe(rows)
        for i in miss.indices { miss[i].reps = 8 }
        let afterMiss = engine.advance(
            schedule: schedule,
            profile: .documentDefaults,
            state: state,
            session: CompletedSession(dayId: "d1", sets: miss)
        ).applied(to: state)
        XCTAssertEqual(afterMiss.workingKg[benchId], 50)
    }

    func testScheduleJSONRoundTrip() throws {
        var schedule = ProgramSchedule.makeCustom(name: "라운드트립")
        schedule.days[0].exercises = [ScheduleExercise.makeCustom(name: "컬", seedKg: 12)]
        let json = try XCTUnwrap(TrainingCycle.encodeSchedule(schedule))
        let decoded = try JSONDecoder().decode(ProgramSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "라운드트립")
        XCTAssertEqual(decoded.days[0].exercises[0].name, "컬")
        XCTAssertEqual(decoded.days[0].exercises[0].seedKg, 12)
        XCTAssertFalse((json.lowercased().contains("percent")))
    }

    @MainActor
    func testPersistCustomAndApplyToActiveCycle() throws {
        let schema = Schema([
            AthleteProfile.self,
            TrainingCycle.self,
            WorkoutSession.self,
            SetLog.self,
            PersonalRecord.self,
            CustomRoutine.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        var schedule = ProgramSchedule.makeCustom(name: "저장 루틴")
        schedule.days[0].exercises = [ScheduleExercise.makeCustom(name: "벤치프레스", seedKg: 40)]
        let routine = SessionService.persistCustom(context: context, existing: nil, schedule: schedule, cycle: nil)
        XCTAssertEqual(routine.name, "저장 루틴")
        XCTAssertEqual(routine.resolvedSchedule()?.days.first?.exercises.first?.name, "벤치프레스")

        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults)
        XCTAssertEqual(cycle.programId, schedule.id)
        XCTAssertTrue(EngineRegistry.isCustom(cycle.programId))

        schedule.days.append(.blank(named: "2일차"))
        schedule.days[1].exercises = [ScheduleExercise.makeCustom(name: "스쿼트", seedKg: 80)]
        schedule.name = "저장 루틴 수정"
        _ = SessionService.persistCustom(context: context, existing: routine, schedule: schedule, cycle: cycle)
        XCTAssertEqual(routine.name, "저장 루틴 수정")
        XCTAssertEqual(cycle.resolvedSchedule()?.days.count, 2)
        XCTAssertEqual(cycle.state.workingKg[schedule.days[1].exercises[0].id], 80)
    }
}

final class ReviewFixTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            AthleteProfile.self, TrainingCycle.self, WorkoutSession.self,
            SetLog.self, PersonalRecord.self, CustomRoutine.self
        ])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Programs sit under Programs/ in the bundle; the app must find them there, not via a dev-machine path.
    func testCatalogLoadsFromBundleSubdirectory() {
        XCTAssertEqual(ProgramCatalog.loadAll().count, ProgramCatalog.allIds.count)
        XCTAssertEqual(ProgramCatalog.load(FiveThreeOneBBBEngine.id)?.id, FiveThreeOneBBBEngine.id)
    }

    @MainActor
    func testStartingSameProgramKeepsProgressUnlessRestart() throws {
        let context = try makeContext()
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults)
        cycle.setWorkingKg("bench", 80)
        let again = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults, startingDayId: "legs-a")
        XCTAssertTrue(again === cycle)
        XCTAssertEqual(again.state.workingKg["bench"], 80)
        XCTAssertEqual(again.nextDayId, "legs-a")
        let fresh = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults, restart: true)
        XCTAssertFalse(fresh === cycle)
        XCTAssertFalse(cycle.isActive)
        XCTAssertEqual(fresh.state.workingKg["bench"], 55)
    }

    func testStartingStrengthSkippedLiftDoesNotStall() throws {
        let schedule = try CatalogTests.schedule(StartingStrengthEngine.id)
        let engine = StartingStrengthEngine()
        let state = ProgramCatalog.seededState(schedule: schedule, profile: .documentDefaults)
        var sets = TodayController.loggedMatchingPrescribe(engine.prescribe(schedule: schedule, profile: .documentDefaults, state: state))
        for i in sets.indices where sets[i].exerciseId == "squat" { sets[i].completed = false }
        let next = engine.advance(schedule: schedule, profile: .documentDefaults, state: state, session: CompletedSession(dayId: "a", sets: sets)).applied(to: state)
        XCTAssertEqual(next.workingKg["squat"], 80)
        XCTAssertNil(next.stall["squat"])
        XCTAssertEqual(next.workingKg["bench"], 57.5)
    }

    func testFiveThreeOneWeekAdvancesEveryFourSessionsRegardlessOfOrder() throws {
        let schedule = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let engine = FiveThreeOneBBBEngine()
        var state = ProgramCatalog.seededState(schedule: schedule, profile: .documentDefaults)
        for day in ["press", "squat", "press", "bench"] {
            state.nextDayId = day
            let rows = engine.prescribe(schedule: schedule, profile: .documentDefaults, state: state)
            state = engine.advance(schedule: schedule, profile: .documentDefaults, state: state, session: CompletedSession(dayId: day, sets: TodayController.loggedMatchingPrescribe(rows))).applied(to: state)
        }
        XCTAssertEqual(state.weekIndex, 2)
    }

    func testLiftKeyMergesAcrossPrograms() {
        XCTAssertEqual(ExerciseGuide.liftKey(id: "bench", name: "벤치프레스"), "벤치프레스")
        XCTAssertEqual(ExerciseGuide.liftKey(id: "ppl-bench", name: "벤치프레스"), "벤치프레스")
        XCTAssertEqual(ExerciseGuide.liftKey(id: "ex-123", name: "벤치프레스"), "벤치프레스")
        XCTAssertEqual(ExerciseGuide.liftKey(id: "bench", name: "BBB 벤치프레스"), "벤치프레스")
        XCTAssertEqual(ExerciseGuide.liftKey(id: "cap-t2", name: "T2 벤치"), "클로즈그립 벤치")
        XCTAssertEqual(ExerciseGuide.liftKey(id: "ex-999", name: "이상한 운동"), "이상한 운동")
        XCTAssertFalse(ExerciseGuide.lookup(name: "라이트 플랫 덤벨 프레스").isGeneric)
    }

    @MainActor
    func testCompleteWritesPRsByLiftKeyAndSkipsWarmupsAndZeroReps() throws {
        let context = try makeContext()
        let schedule = try CatalogTests.schedule(FiveThreeOneBBBEngine.id)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults, startingDayId: "bench")
        let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: .documentDefaults)
        var logged = TodayController.loggedMatchingPrescribe(rows)
        for i in logged.indices where logged[i].isWorking && !logged[i].isBBB { logged[i].completed = false }
        // Only warmups (isWorking == false) and BBB sets remain completed; the top warmup is 40 kg.
        SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: .documentDefaults, rows: rows, logged: logged)
        let prs = try context.fetch(FetchDescriptor<PersonalRecord>())
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.liftId, "벤치프레스")
        XCTAssertEqual(prs.first?.kg, 32.5) // BBB weight, not the heavier warmup
        XCTAssertNil(SessionService.lastHint(context: context, exerciseId: "bench", exerciseName: "벤치프레스").map(\.kg).flatMap { $0 == 40 ? $0 : nil })
        XCTAssertEqual(SessionService.personalRecordKg(context: context, exerciseId: "ppl-bench", exerciseName: "벤치프레스"), 32.5)
        XCTAssertTrue(cycle.draftJSON.isEmpty)
    }

    @MainActor
    func testDraftRoundTripOnCycle() throws {
        let context = try makeContext()
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults)
        var sets = TodayController.loggedMatchingPrescribe(SessionService.prescribe(cycle: cycle, schedule: schedule, profile: .documentDefaults))
        sets[0].completed = true
        sets[0].kg = 60
        cycle.saveDraft(sets, dayId: cycle.nextDayId)
        XCTAssertTrue(cycle.hasDraft)
        XCTAssertEqual(cycle.loadDraft(), sets)
        cycle.clearDraft()
        XCTAssertFalse(cycle.hasDraft)
        XCTAssertNil(cycle.loadDraft())
    }

    func testRepLabelShowsRange() throws {
        let schedule = try CatalogTests.schedule(Hypertrophy6DayEngine.id)
        let bench = try XCTUnwrap(schedule.days[0].exercises.first)
        XCTAssertEqual(bench.repLabel, "5~8회")
        XCTAssertEqual(ScheduleExercise.makeCustom(name: "컬", reps: 10).repLabel, "10회")
    }
}
