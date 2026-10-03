import XCTest
@testable import Health

/// Stage 5: PR grouping by base exercise (AC9).
final class HistoryTests: XCTestCase {
    private let lib = ExerciseLibrary.shared
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func pr(_ id: String, _ kg: Double, offset: TimeInterval = 0) -> PRInput {
        PRInput(liftId: id, kg: kg, date: day.addingTimeInterval(offset))
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertEqual(PRGrouping.group([], library: lib), [])
    }

    func testGroupsByBaseExerciseWithVariantRows() throws {
        let groups = PRGrouping.group([
            pr("cable-fly", 30), pr("cable-fly/cybex-functional-trainer", 25), pr("bench", 100),
        ], library: lib)
        XCTAssertEqual(groups.map(\.id), ["bench", "cable-fly"])
        let fly = try XCTUnwrap(groups.last)
        XCTAssertEqual(fly.title, lib.exercise(id: "cable-fly")?.name)
        XCTAssertEqual(fly.rows.map(\.variantId), ["cable-fly", "cable-fly/cybex-functional-trainer"])
        XCTAssertEqual(fly.rows.last?.title, lib.displayName(variantId: "cable-fly/cybex-functional-trainer"))
    }

    func testSortOrderRowsByKgDescGroupsByMaxKgDesc() {
        let groups = PRGrouping.group([
            pr("cable-fly", 20), pr("cable-fly/cybex-functional-trainer", 60),
            pr("bench", 100), pr("squat", 55),
        ], library: lib)
        XCTAssertEqual(groups.map(\.id), ["bench", "cable-fly", "squat"])
        XCTAssertEqual(groups[1].rows.map(\.kg), [60, 20])
    }

    func testBestPRPerVariantKeptAndMapsToSourceIndex() throws {
        let groups = PRGrouping.group([pr("bench", 90, offset: 0), pr("bench", 100, offset: 10), pr("bench", 95, offset: 20)],
                                      library: lib)
        let row = try XCTUnwrap(groups.first?.rows.first)
        XCTAssertEqual(groups.first?.rows.count, 1)
        XCTAssertEqual(row.kg, 100)
        XCTAssertEqual(row.sourceIndex, 1)
    }

    func testHiddenUserVariantIsIncludedWithNickname() throws {
        let id = "bench/u-1111"
        let groups = PRGrouping.group([pr("bench", 100), pr(id, 80)], nicknames: [id: "내 벤치"], library: lib)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rows.map(\.variantId), ["bench", id])
        XCTAssertEqual(groups[0].rows.last?.title, "내 벤치")
    }

    func testOtherGroupTitleAndKey() throws {
        let id = "other/u-2222"
        let groups = PRGrouping.group([pr(id, 40), pr("bench", 20)], nicknames: [id: "플랭크 워크"], library: lib)
        XCTAssertEqual(groups.map(\.id), ["other", "bench"])
        XCTAssertEqual(groups[0].title, "기타")
        XCTAssertEqual(groups[0].rows.first?.title, "플랭크 워크")
    }

    func testOtherWithoutNicknameFallsBackToGita() {
        let groups = PRGrouping.group([pr("other/u-3333", 10)], library: lib)
        XCTAssertEqual(groups.first?.rows.first?.title, "기타")
    }

    func testUnknownVariantFallsBackToStoredNameThenExerciseName() {
        // Library id removed entirely, no user variant: stored id is shown, never empty.
        let gone = PRGrouping.group([pr("removed-exercise/foo", 10)], library: lib)
        XCTAssertEqual(gone.first?.id, "removed-exercise")
        XCTAssertEqual(gone.first?.rows.first?.title, "removed-exercise/foo")
        XCTAssertFalse(gone.first?.title.isEmpty ?? true)
        // Unknown variant of a known exercise falls back to the exercise name.
        let known = PRGrouping.group([pr("bench/removed-brand", 10)], library: lib)
        XCTAssertEqual(known.first?.rows.first?.title, lib.exercise(id: "bench")?.name)
        // Empty id is still presentable.
        XCTAssertEqual(PRGrouping.group([pr("", 5)], library: lib).first?.rows.first?.title, "운동")
    }
}
