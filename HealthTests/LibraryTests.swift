import XCTest
@testable import Health

final class LibraryTests: XCTestCase {
    // MARK: Helpers

    private static func bundleData(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Exercises") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Bundle library decoded without the DEBUG drop assertion so tests can report drops instead of trapping.
    private static let bundled: ExerciseLibrary = ExerciseLibrary.decode(
        exercises: bundleData("exercises"), brands: bundleData("brands"), variants: bundleData("variants"),
        assertOnDrop: false)

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func millis(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private static let fixedBrandIds: Set<String> = [
        "hammer", "technogym", "lifefitness", "cybex", "matrix", "panatta",
        "gym80", "prime", "nautilus", "hoist", "drax", "newtech"
    ]

    // MARK: AC1 schema

    func testBundleFilesPresentAndNoDroppedRows() throws {
        XCTAssertNotNil(Self.bundleData("exercises"), "Exercises/exercises.json missing from bundle")
        XCTAssertNotNil(Self.bundleData("brands"), "Exercises/brands.json missing from bundle")
        let drops = Self.bundled.dropped.map { "\($0.file)/\($0.id): \($0.reason)" }
        XCTAssertTrue(drops.isEmpty, "dropped rows: \(drops)")
    }

    func testExercisesSchemaAndUniqueness() {
        let lib = Self.bundled
        XCTAssertGreaterThanOrEqual(lib.exercises.count, 250, "exercise count \(lib.exercises.count)")
        XCTAssertGreaterThanOrEqual(lib.version, 1)

        var ids = Set<String>()
        var owner: [String: String] = [:]
        var collisions: [String] = []
        var schemaErrors: [String] = []
        for ex in lib.exercises {
            if !ids.insert(ex.id).inserted { schemaErrors.append("\(ex.id): duplicate id") }
            if ex.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) == nil {
                schemaErrors.append("\(ex.id): id not ASCII slug")
            }
            if ex.aliases.isEmpty { schemaErrors.append("\(ex.id): no aliases") }
            if ex.aliases.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                schemaErrors.append("\(ex.id): blank alias")
            }
            if ex.summary.contains(where: \.isNewline) || !(1...60).contains(ex.summary.count) {
                schemaErrors.append("\(ex.id): summary length \(ex.summary.count) or newline")
            }
            if ex.name != ex.name.precomposedStringWithCanonicalMapping { schemaErrors.append("\(ex.id): name not NFC") }
            for term in Set(([ex.name] + ex.aliases).map(SearchNormalizer.normalize)) {
                if let other = owner[term], other != ex.id {
                    collisions.append("\(term): \(other) vs \(ex.id)")
                } else {
                    owner[term] = ex.id
                }
            }
        }
        XCTAssertTrue(schemaErrors.isEmpty, "\(schemaErrors.count) schema errors, first 20: \(schemaErrors.prefix(20))")
        XCTAssertTrue(collisions.isEmpty, "normalized name/alias collisions: \(collisions)")
    }

    // MARK: AC2 minimums

    func testGroupAndEquipmentMinimums() {
        let lib = Self.bundled
        let groupMin: [MuscleGroup: Int] = [.chest: 25, .back: 35, .legs: 45, .shoulders: 25, .arms: 30, .core: 20, .fullbody: 10]
        let equipmentMin: [Equipment: Int] = [.bodyweight: 30, .kettlebell: 15, .band: 15]
        let groups = Dictionary(grouping: lib.exercises, by: \.group).mapValues(\.count)
        let equipment = Dictionary(grouping: lib.exercises, by: \.equipment).mapValues(\.count)
        for (group, min) in groupMin {
            XCTAssertGreaterThanOrEqual(groups[group] ?? 0, min, "group \(group.rawValue)")
        }
        for (eq, min) in equipmentMin {
            XCTAssertGreaterThanOrEqual(equipment[eq] ?? 0, min, "equipment \(eq.rawValue)")
        }
        let machineLike = [Equipment.machine, .cable, .smith].reduce(0) { $0 + (equipment[$1] ?? 0) }
        XCTAssertGreaterThanOrEqual(machineLike, 40, "machine+cable+smith")
    }

    func testReservedIdsAreBarbell() {
        for id in ["squat", "bench", "deadlift", "ohp"] {
            XCTAssertEqual(Self.bundled.exercise(id: id)?.equipment, .barbell, "reserved id \(id)")
        }
        XCTAssertNil(Self.bundled.exercise(id: ExerciseLibrary.otherId), "`other` must not be a JSON row")
    }

    func testReleasedIdsStillExist() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/exercise-data/released-ids.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let ids = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let missing = ids.filter {
            $0 != ExerciseLibrary.otherId && Self.bundled.variant(id: $0) == nil && Self.bundled.brand(id: $0) == nil
        }
        XCTAssertTrue(missing.isEmpty, "released ids (exercise/variant/brand) missing: \(missing)")
    }

    // MARK: AC6 brands/variants

    func testBrandsAndVariantsIntegrity() {
        let lib = Self.bundled
        XCTAssertEqual(Set(lib.brands.map(\.id)), Self.fixedBrandIds)
        XCTAssertEqual(lib.brands.count, 12)
        var namesPerPair = Set<String>()
        for v in lib.variants {
            XCTAssertNotNil(lib.exercise(id: v.exerciseId), "\(v.id) exercise")
            XCTAssertNotNil(v.brandId.flatMap(lib.brand(id:)), "\(v.id) brand")
            XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: v.id), v.exerciseId)
            if let base = lib.exercise(id: v.exerciseId) {
                XCTAssertTrue([.machine, .cable, .smith].contains(base.equipment), "\(v.id) base equipment \(base.equipment)")
            }
            let key = "\(v.exerciseId)|\(v.brandId ?? "")|\(SearchNormalizer.normalize(v.name))"
            XCTAssertTrue(namesPerPair.insert(key).inserted, "duplicate variant name \(key)")
        }
    }

    func testVariantCountMinimums() {
        let lib = Self.bundled
        XCTAssertGreaterThanOrEqual(lib.variants.count, 240, "variant count")
        let perBrand = Dictionary(grouping: lib.variants, by: { $0.brandId ?? "" }).mapValues(\.count)
        for brand in Self.fixedBrandIds {
            XCTAssertGreaterThanOrEqual(perBrand[brand] ?? 0, 20, "variants for \(brand)")
        }
    }

    // MARK: AC7 generic variant + display name

    func testGenericVariantAndDisplayName() {
        let lib = Self.bundled
        for ex in lib.exercises {
            let generic = lib.variant(id: ex.id)
            XCTAssertEqual(generic?.isGeneric, true, ex.id)
            XCTAssertNil(generic?.brandId, ex.id)
            XCTAssertEqual(lib.displayName(variantId: ex.id), ex.name)
        }
        for v in lib.variants {
            let brand = v.brandId.flatMap(lib.brand(id:))
            XCTAssertEqual(lib.displayName(variantId: v.id), "\(brand?.name ?? "") \(v.name)")
        }
    }

    func testDisplayNameFallsBack() {
        let lib = Self.fixture
        XCTAssertEqual(lib.displayName(variantId: "bench"), "벤치프레스")
        XCTAssertEqual(lib.displayName(variantId: "chest-press-machine/hammer-iso"), "해머스트렝스 아이소 래터럴 체스트 프레스")
        XCTAssertEqual(lib.displayName(variantId: "bench/removed-model"), "벤치프레스", "unknown variant falls back to base")
        XCTAssertNil(lib.displayName(variantId: "other/u-123"), "user variants resolve outside the library")
        XCTAssertNil(lib.displayName(variantId: "nope"))
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: "chest-press-machine/hammer-iso"), "chest-press-machine")
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: "bench"), "bench")
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: "other/u-123"), "other")
    }

    // MARK: AC18/19 info(for:)

    func testInfoForOther() throws {
        let info = try XCTUnwrap(Self.fixture.info(for: ExerciseLibrary.otherId))
        XCTAssertTrue(info.isOther)
        XCTAssertEqual(info.name, "기타 (직접 추가)")
        XCTAssertNil(info.group)
        XCTAssertNil(info.equipment)
        XCTAssertNil(info.summary)
        XCTAssertNil(Self.fixture.info(for: "missing"))
    }

    func testInfoForEveryExercise() {
        var missingSummary: [String] = []
        for ex in Self.bundled.exercises {
            let info = Self.bundled.info(for: ex.id)
            XCTAssertEqual(info?.isOther, false)
            XCTAssertEqual(info?.group, ex.group)
            XCTAssertEqual(info?.equipment, ex.equipment)
            if info?.summary == nil { missingSummary.append(ex.id) }
        }
        XCTAssertTrue(missingSummary.isEmpty, "\(missingSummary.count) exercises without summary")
    }

    // MARK: AC4 (interim) program names resolve by name/alias

    func testProgramExerciseNamesResolve() throws {
        var terms = Set<String>()
        for ex in Self.bundled.exercises {
            terms.formUnion(([ex.name] + ex.aliases).map(SearchNormalizer.normalize))
        }
        var names = Set<String>()
        for id in ProgramCatalog.allIds {
            let schedule = try CatalogTests.schedule(id)
            for day in schedule.days { names.formUnion(day.exercises.map(\.name)) }
        }
        let unresolved = names.filter { !terms.contains(SearchNormalizer.normalize($0)) }.sorted()
        XCTAssertTrue(unresolved.isEmpty, "\(unresolved.count)/\(names.count) program names unresolved: \(unresolved)")
    }

    // MARK: AC5 load time

    func testLoadUnder50ms() {
        var samples: [Double] = []
        measure {
            samples.append(Self.millis { _ = ExerciseLibrary.load(bundle: .main) })
        }
        XCTAssertLessThan(Self.median(samples), 50, "load samples ms: \(samples)")
    }

    // MARK: AC11 search

    func testSearchNormalization() {
        let lib = Self.bundled
        let nfd = "벤치프레스".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(nfd.unicodeScalars.count, "벤치프레스".unicodeScalars.count)
        for query in ["벤치 프레스", "BENCH", nfd, "벤치-프레스", "ｂｅｎｃｈ"] {
            XCTAssertTrue(lib.search(query).contains { $0.exercise.id == "bench" }, "query \(query)")
        }
        XCTAssertEqual(SearchNormalizer.normalize("Bench·Press_ 1"), "benchpress1")
    }

    func testSearchMatchesNameAliasBrandVariant() throws {
        let lib = Self.fixture
        XCTAssertEqual(lib.search("bp").map(\.id), ["bench"])
        let byBrand = try XCTUnwrap(lib.search("해머").first)
        XCTAssertEqual(byBrand.id, "chest-press-machine")
        XCTAssertEqual(byBrand.matchedVariantIds, ["chest-press-machine/hammer-iso"])
        XCTAssertEqual(lib.search("Hammer Strength").first?.matchedVariantIds, ["chest-press-machine/hammer-iso"])
        let byVariant = try XCTUnwrap(lib.search("아이소 래터럴").first)
        XCTAssertEqual(byVariant.id, "chest-press-machine")
        XCTAssertFalse(byVariant.matchedVariants.isEmpty)
        let byExerciseOnly = try XCTUnwrap(lib.search("체스트 프레스 머신").first)
        XCTAssertTrue(byExerciseOnly.matchedVariants.isEmpty)
        XCTAssertTrue(lib.search("없는운동").isEmpty)
    }

    func testSearchFiltersAndEmptyQuery() {
        let lib = Self.fixture
        XCTAssertEqual(lib.search("").map(\.id), ["bench", "chest-press-machine", "squat"])
        XCTAssertEqual(lib.search("  ", group: .legs).map(\.id), ["squat"])
        XCTAssertEqual(lib.search("", group: .chest, equipment: .machine).map(\.id), ["chest-press-machine"])
        XCTAssertEqual(lib.search("프레스", equipment: .barbell).map(\.id), ["bench"])
        XCTAssertEqual(Self.bundled.search("").map(\.id), Self.bundled.exercises.map(\.id))
    }

    func testSearchUnder16ms() {
        let lib = Self.bundled
        let queries = ["벤", "프레스", "BENCH", "해머", "덤벨 컬", "zzz"]
        var samples: [Double] = []
        measure {
            for q in queries {
                samples.append(Self.millis { _ = lib.search(q) })
            }
        }
        XCTAssertLessThan(samples.max() ?? 0, 16, "search samples ms: \(samples)")
    }

    // MARK: Loader robustness

    func testInvalidRowsAreDroppedNotFatal() {
        let exercises = Data("""
        {"version": 1, "exercises": [
          {"id": "ok", "name": "정상", "aliases": ["ok"], "group": "chest", "equipment": "barbell", "plane": "upper", "isCompound": true, "summary": "정상"},
          {"id": "bad-group", "name": "그룹", "aliases": ["g"], "group": "neck", "equipment": "barbell", "plane": "upper", "isCompound": true, "summary": "x"},
          {"id": "bad-eq", "name": "장비", "aliases": ["e"], "group": "chest", "equipment": "rope", "plane": "upper", "isCompound": true, "summary": "x"},
          {"id": "no-summary", "name": "요약", "aliases": ["s"], "group": "chest", "equipment": "barbell", "plane": "upper", "isCompound": true},
          {"id": "ok", "name": "중복", "aliases": ["d"], "group": "chest", "equipment": "barbell", "plane": "upper", "isCompound": true, "summary": "x"},
          {"id": "other", "name": "기타", "aliases": ["o"], "group": "chest", "equipment": "barbell", "plane": "upper", "isCompound": true, "summary": "x"},
          {"id": 3},
          "garbage"
        ]}
        """.utf8)
        let brands = Data(#"{"version": 1, "brands": [{"id": "hammer", "name": "해머스트렝스", "englishName": "Hammer Strength"}, {"id": "x"}]}"#.utf8)
        let variants = Data("""
        {"version": 1, "variants": [
          {"id": "ok/hammer-a", "exerciseId": "ok", "brandId": "hammer", "name": "A", "aliases": []},
          {"id": "ok/zzz-a", "exerciseId": "ok", "brandId": "zzz", "name": "B", "aliases": []},
          {"id": "gone/hammer-a", "exerciseId": "gone", "brandId": "hammer", "name": "C", "aliases": []},
          {"id": "wrong-prefix", "exerciseId": "ok", "brandId": "hammer", "name": "D", "aliases": []},
          {"id": "ok", "exerciseId": "ok", "brandId": null, "name": "generic", "aliases": []}
        ]}
        """.utf8)
        let lib = ExerciseLibrary.decode(exercises: exercises, brands: brands, variants: variants, assertOnDrop: false)
        XCTAssertEqual(lib.exercises.map(\.id), ["ok", "no-summary"], "text-only gaps keep the row")
        XCTAssertEqual(lib.exercise(id: "no-summary")?.summary, "")
        XCTAssertEqual(lib.brands.map(\.id), ["hammer"])
        XCTAssertEqual(lib.variants.map(\.id), ["ok/hammer-a"])
        XCTAssertEqual(lib.dropped.count, 6 + 1 + 3, "\(lib.dropped)")
        XCTAssertEqual(lib.variant(id: "ok")?.isGeneric, true)

        let empty = ExerciseLibrary.decode(exercises: nil, brands: Data("not json".utf8), variants: nil, assertOnDrop: false)
        XCTAssertTrue(empty.exercises.isEmpty)
        XCTAssertEqual(empty.dropped.count, 1)
    }

    // MARK: Fixture

    private static let fixture: ExerciseLibrary = ExerciseLibrary(
        version: 1,
        exercises: [
            LibraryExercise(id: "bench", name: "벤치프레스", aliases: ["벤치 프레스", "bench press", "BP"], group: .chest,
                            equipment: .barbell, plane: "upper", isCompound: true, summary: "바벨 벤치"),
            LibraryExercise(id: "chest-press-machine", name: "체스트 프레스 머신", aliases: ["chest press"], group: .chest,
                            equipment: .machine, plane: "upper", isCompound: true, summary: "머신 프레스"),
            LibraryExercise(id: "squat", name: "스쿼트", aliases: ["back squat"], group: .legs,
                            equipment: .barbell, plane: "lower", isCompound: true, summary: "바벨 스쿼트")
        ],
        brands: [LibraryBrand(id: "hammer", name: "해머스트렝스", englishName: "Hammer Strength")],
        variants: [
            LibraryVariant(id: "chest-press-machine/hammer-iso", exerciseId: "chest-press-machine", brandId: "hammer",
                           name: "아이소 래터럴 체스트 프레스", aliases: ["ISO-Lateral"])
        ])
}
