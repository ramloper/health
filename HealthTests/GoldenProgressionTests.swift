import XCTest
@testable import Health

/// Golden progression fixture captured from main's engines before the exercise-library key migration.
/// Record: `./scripts/record-golden.sh` (or `./scripts/record-golden.sh force` to overwrite).
final class GoldenProgressionTests: XCTestCase {
    static let sessionCount = 40
    static let programIds = [
        Hypertrophy6DayEngine.id,
        ClassBEngine.pplId,
        ClassBEngine.phulId,
        ClassBEngine.ulId,
        StartingStrengthEngine.id,
    ]

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/progression-golden-v1.json")
    }

    struct GoldenFile: Codable, Equatable {
        var sourceCommit: String
        var sessions: Int
        var programs: [GoldenProgram]
    }

    struct GoldenProgram: Codable, Equatable {
        var id: String
        var sessions: [GoldenSession]
    }

    /// State after advancing the session (`dayId` is the day that was trained).
    struct GoldenSession: Codable, Equatable {
        var index: Int
        var dayId: String
        var prescribedCount: Int
        var nextDayId: String
        var weekIndex: Int
        var trainingSessionsCompleted: Int
        var deloadSessionsRemaining: Int
        var workingKg: [String: Double]
        var stall: [String: Int]
        var tm: [String: Double]
        var pendingTmBump: [String: Double]
    }

    /// Session i, row j: `(i+j) % 7 == 0` → reps −2 (min 1); `i % 11 == 0` → first exercise's sets not completed.
    static func perturb(_ rows: [PrescribedSet], session i: Int) -> [CompletedSet] {
        var logged = TodayController.loggedMatchingPrescribe(rows)
        let firstExerciseId = rows.first?.exerciseId
        for j in logged.indices {
            if (i + j) % 7 == 0 {
                logged[j].reps = max(1, logged[j].reps - 2)
            }
            if i % 11 == 0, logged[j].exerciseId == firstExerciseId {
                logged[j].completed = false
            }
        }
        return logged
    }

    static func simulate(programId: String) throws -> GoldenProgram {
        let schedule = try CatalogTests.schedule(programId)
        let profile = ProfileInputs.documentDefaults
        let engine = EngineRegistry.engine(for: programId)
        var state = ProgramCatalog.seededState(schedule: schedule, profile: profile)
        var sessions: [GoldenSession] = []
        for i in 0..<sessionCount {
            let dayId = state.nextDayId
            let rows = engine.prescribe(schedule: schedule, profile: profile, state: state)
            let logged = perturb(rows, session: i)
            state = engine.advance(schedule: schedule, profile: profile, state: state, session: CompletedSession(dayId: dayId, sets: logged)).applied(to: state)
            sessions.append(GoldenSession(
                index: i,
                dayId: dayId,
                prescribedCount: rows.count,
                nextDayId: state.nextDayId,
                weekIndex: state.weekIndex,
                trainingSessionsCompleted: state.trainingSessionsCompleted,
                deloadSessionsRemaining: state.deloadSessionsRemaining,
                workingKg: state.workingKg,
                stall: state.stall,
                tm: state.tm,
                pendingTmBump: state.pendingTmBump
            ))
        }
        return GoldenProgram(id: programId, sessions: sessions)
    }

    static func simulateAll(sourceCommit: String) throws -> GoldenFile {
        GoldenFile(
            sourceCommit: sourceCommit,
            sessions: sessionCount,
            programs: try programIds.map { try simulate(programId: $0) }
        )
    }

    func testRecordGolden() throws {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["RECORD_GOLDEN"], !mode.isEmpty else {
            throw XCTSkip("RECORD_GOLDEN not set; run ./scripts/record-golden.sh")
        }
        let url = Self.fixtureURL
        if FileManager.default.fileExists(atPath: url.path), mode != "force" {
            XCTFail("fixture exists; use RECORD_GOLDEN=force")
            return
        }
        let golden = try Self.simulateAll(sourceCommit: env["GOLDEN_COMMIT"] ?? "unknown")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(golden)
        data.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func testProgressionMatchesGolden() throws {
        let url = Self.fixtureURL
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("missing fixture \(url.path)")
        }
        let golden = try JSONDecoder().decode(GoldenFile.self, from: data)
        XCTAssertEqual(golden.sessions, Self.sessionCount)
        XCTAssertEqual(golden.programs.map(\.id), Self.programIds)
        for expected in golden.programs {
            let actual = try Self.simulate(programId: expected.id)
            XCTAssertEqual(actual.sessions.count, expected.sessions.count, "\(expected.id): session count")
            for (e, a) in zip(expected.sessions, actual.sessions) {
                let at = "\(expected.id) session \(e.index)"
                XCTAssertEqual(a.index, e.index, "\(at): index")
                XCTAssertEqual(a.dayId, e.dayId, "\(at): dayId")
                XCTAssertEqual(a.prescribedCount, e.prescribedCount, "\(at): prescribedCount")
                XCTAssertEqual(a.nextDayId, e.nextDayId, "\(at): nextDayId")
                XCTAssertEqual(a.weekIndex, e.weekIndex, "\(at): weekIndex")
                XCTAssertEqual(a.trainingSessionsCompleted, e.trainingSessionsCompleted, "\(at): trainingSessionsCompleted")
                XCTAssertEqual(a.deloadSessionsRemaining, e.deloadSessionsRemaining, "\(at): deloadSessionsRemaining")
                assertDictionary(a.workingKg, e.workingKg, "\(at): workingKg")
                assertDictionary(a.stall, e.stall, "\(at): stall")
                assertDictionary(a.tm, e.tm, "\(at): tm")
                assertDictionary(a.pendingTmBump, e.pendingTmBump, "\(at): pendingTmBump")
            }
        }
    }

    private func assertDictionary<V: Equatable>(_ actual: [String: V], _ expected: [String: V], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for key in Set(actual.keys).union(expected.keys).sorted() {
            let a = actual[key].map { "\($0)" } ?? "nil"
            let e = expected[key].map { "\($0)" } ?? "nil"
            XCTAssertTrue(actual[key] == expected[key], "\(label)[\(key)]: expected \(e), got \(a)", file: file, line: line)
        }
    }
}
