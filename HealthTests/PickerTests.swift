import XCTest
import SwiftData
@testable import Health

/// Stage 4 picker logic: variant sheet sections (AC12/AC17), user variants (AC10/AC14), "운동 바꾸기", guide header (AC19).
@MainActor
final class PickerTests: XCTestCase {
    private let library = ExerciseLibrary.shared
    private let machine = "machine-chest-press"

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func kinds(_ sections: [VariantSections.Section]) -> [VariantSections.Kind] {
        sections.map(\.kind)
    }

    private func userVariant(_ exerciseId: String, nickname: String = "파란 머신", brandId: String? = "hammer",
                             hidden: Bool = false) -> UserVariant {
        UserVariant(id: UserVariantStore.newId(exerciseId: exerciseId), exerciseId: exerciseId, brandId: brandId,
                    nickname: nickname, plane: "upper", isHidden: hidden)
    }

    // MARK: testVariantSheetSections

    func testVariantSheetSectionsGymSet() throws {
        let mine = userVariant(machine, brandId: nil)
        mine.brandName = "우리동네"
        let sections = VariantSections.build(exerciseId: machine, library: library, gymBrandIds: ["hammer"],
                                             userVariants: [mine, userVariant("bench")])
        XCTAssertEqual(kinds(sections), [.generic, .gym, .otherBrands, .new])
        XCTAssertEqual(sections[0].rows.map(\.id), [machine])

        let presets = library.variants(ofExercise: machine)
        let hammer = presets.filter { $0.brandId == "hammer" }.map(\.id)
        XCTAssertFalse(hammer.isEmpty)
        XCTAssertEqual(sections[1].rows.map(\.id), hammer + [mine.id])
        XCTAssertEqual(sections[1].rows.last?.title, "우리동네 파란 머신")
        XCTAssertEqual(sections[1].rows.last?.isUser, true)

        let others = sections[2].rows.map(\.id)
        XCTAssertEqual(Set(others), Set(presets.map(\.id)).subtracting(hammer))
        XCTAssertFalse(others.contains { hammer.contains($0) })
        // Grouped by brand in brands.json order.
        let order = library.brands.map(\.name)
        let brandIndexes = sections[2].rows.compactMap { $0.brandName.flatMap(order.firstIndex(of:)) }
        XCTAssertEqual(brandIndexes, brandIndexes.sorted())
        XCTAssertTrue(sections[3].rows.isEmpty)
    }

    func testVariantSheetSectionsGymEmptyWithUserVariants() {
        let mine = userVariant(machine)
        let hidden = userVariant(machine, nickname: "숨김", hidden: true)
        let sections = VariantSections.build(exerciseId: machine, library: library, gymBrandIds: [],
                                             userVariants: [mine, hidden])
        XCTAssertEqual(kinds(sections), [.generic, .myVariants, .otherBrands, .new])
        XCTAssertEqual(sections[1].rows.map(\.id), [mine.id])
        XCTAssertEqual(sections[1].rows.first?.title, "해머스트렝스 파란 머신")
        XCTAssertEqual(sections[2].rows.count, library.variants(ofExercise: machine).count)
    }

    func testVariantSheetSectionsGymEmptyNoUserVariants() {
        let sections = VariantSections.build(exerciseId: machine, library: library, gymBrandIds: [],
                                             userVariants: [userVariant("bench")])
        XCTAssertEqual(kinds(sections), [.generic, .otherBrands, .new])
        // An exercise without presets has only 일반 + 새 변형.
        let plain = library.exercises.first { library.variants(ofExercise: $0.id).isEmpty }!
        XCTAssertEqual(kinds(VariantSections.build(exerciseId: plain.id, library: library, gymBrandIds: ["hammer"],
                                                   userVariants: [])), [.generic, .gym, .new])
    }

    func testVariantSheetSectionsOther() {
        let other = ExerciseLibrary.otherId
        let mine = userVariant(other, nickname: "스쿼트 머신", brandId: nil)
        let sections = VariantSections.build(exerciseId: other, library: library, gymBrandIds: ["hammer"],
                                             userVariants: [mine])
        XCTAssertEqual(kinds(sections), [.myVariants, .new])
        XCTAssertEqual(sections[0].rows.map(\.title), ["스쿼트 머신"])
        XCTAssertEqual(kinds(VariantSections.build(exerciseId: other, library: library, gymBrandIds: [],
                                                   userVariants: [])), [.new])
    }

    // MARK: Picked slots

    func testPickedSlotsCarryVariantIds() {
        let preset = library.variants(ofExercise: machine)[0]
        let mine = userVariant(machine)
        let sections = VariantSections.build(exerciseId: machine, library: library, gymBrandIds: [],
                                             userVariants: [mine])
        let rows = sections.flatMap(\.rows)

        let generic = VariantSections.slot(exerciseId: machine, row: rows.first { $0.id == machine }!,
                                           library: library, userVariants: [mine])
        XCTAssertEqual(generic.variantId, machine)
        XCTAssertEqual(generic.exerciseId, machine)

        let branded = VariantSections.slot(exerciseId: machine, row: rows.first { $0.id == preset.id }!,
                                           library: library, userVariants: [mine])
        XCTAssertEqual(branded.variantId, preset.id)
        XCTAssertEqual(branded.name, library.displayName(variantId: preset.id))

        let user = VariantSections.slot(exerciseId: machine, row: rows.first { $0.id == mine.id }!,
                                        library: library, userVariants: [mine])
        XCTAssertEqual(user.variantId, mine.id)
        XCTAssertEqual(user.liftKey, mine.id)
        XCTAssertEqual(user.name, "해머스트렝스 파란 머신")
        XCTAssertNil(user.progressionTag)
    }

    func testReplaceKeepsSlotFields() {
        var bench = ScheduleExercise.makeCustom(exerciseId: "bench", sets: 5, reps: 5, seedKg: 60)
        bench.progressionTag = "a"
        bench.label = "T1"
        let preset = library.variants(ofExercise: machine)[0]
        let picked = ScheduleExercise.makeCustom(exerciseId: machine, variantId: preset.id)
        let replaced = bench.replacingVariant(picked.variantId, name: picked.name, exerciseId: picked.exerciseId,
                                              plane: picked.plane)
        XCTAssertEqual(replaced.id, bench.id)
        XCTAssertEqual(replaced.sets, bench.sets)
        XCTAssertEqual(replaced.repMin, bench.repMin)
        XCTAssertEqual(replaced.repMax, bench.repMax)
        XCTAssertEqual(replaced.seedKg, bench.seedKg)
        XCTAssertEqual(replaced.progressionTag, "a")
        XCTAssertEqual(replaced.label, "T1")
        XCTAssertEqual(replaced.variantId, preset.id)
        XCTAssertEqual(replaced.exerciseId, machine)
        XCTAssertEqual(replaced.stateKey, "\(preset.id)|\(bench.progressionTag!)")
    }

    // MARK: User variants (AC10, AC14)

    func testUserVariantValidation() {
        var draft = UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "   ")
        XCTAssertFalse(draft.isValid, "blank nickname")
        draft.nickname = " 파란 머신 "
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.trimmedNickname, "파란 머신")
        draft.brandId = nil
        XCTAssertFalse(draft.isValid, "non-other needs a brand")
        draft.customBrand = "  "
        XCTAssertFalse(draft.isValid)
        draft.customBrand = "동네 브랜드"
        XCTAssertTrue(draft.isValid)
        XCTAssertTrue(UserVariantDraft(exerciseId: ExerciseLibrary.otherId, nickname: "케이블 X").isValid,
                      "other is brandless")
    }

    func testUserVariantInsertAndUpdate() throws {
        let context = try makeContext()
        var draft = UserVariantDraft(exerciseId: machine, brandId: nil, customBrand: " 동네 ", nickname: " 파란 머신 ")
        let variant = try XCTUnwrap(UserVariantStore.insert(draft, context: context))
        XCTAssertTrue(variant.id.hasPrefix("\(machine)/u-"))
        XCTAssertEqual(ExerciseLibrary.baseId(ofVariant: variant.id), machine)
        XCTAssertNil(variant.brandId)
        XCTAssertEqual(variant.brandName, "동네")
        XCTAssertEqual(variant.nickname, "파란 머신")
        XCTAssertEqual(variant.plane, library.exercise(id: machine)?.plane)

        draft.brandId = "technogym"
        draft.nickname = "빨간 머신"
        UserVariantStore.update(variant, from: draft, context: context)
        XCTAssertEqual(variant.brandId, "technogym")
        XCTAssertNil(variant.brandName)
        XCTAssertEqual(variant.displayName(in: library), "테크노짐 빨간 머신")
        XCTAssertNil(UserVariantStore.insert(UserVariantDraft(exerciseId: machine, brandId: "hammer"), context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserVariant>()), 1)
    }

    func testFreeTextCreatesOtherVariant() throws {
        let context = try makeContext()
        let before = library.exercises.count
        let slot = try XCTUnwrap(UserVariantStore.addFreeText("스쿼트 머신", context: context))
        let variants = try context.fetch(FetchDescriptor<UserVariant>())
        XCTAssertEqual(variants.count, 1)
        let variant = try XCTUnwrap(variants.first)
        XCTAssertEqual(variant.exerciseId, ExerciseLibrary.otherId)
        XCTAssertNil(variant.brandId)
        XCTAssertNil(variant.brandName)
        XCTAssertEqual(variant.plane, "lower")
        XCTAssertEqual(slot.exerciseId, ExerciseLibrary.otherId)
        XCTAssertEqual(slot.variantId, variant.id)
        XCTAssertEqual(slot.name, "스쿼트 머신")
        XCTAssertEqual(slot.displayName, "스쿼트 머신")
        XCTAssertEqual(slot.plane, "lower")
        XCTAssertEqual(slot.isCompound, false)
        XCTAssertEqual(library.exercises.count, before)
        XCTAssertNil(UserVariantStore.addFreeText("   ", context: context))
    }

    func testUserVariantHiddenNotDeletedWhenRecorded() throws {
        let context = try makeContext()
        let recorded = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "기록 있음"), context: context))
        let fresh = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "기록 없음"), context: context))
        context.insert(SetLog(exerciseId: "ex-1", exerciseName: "기록 있음", setIndex: 0, kg: 40, reps: 10,
                              completed: true, isWorking: true, isAMRAP: false, isWarmup: false, isBBB: false,
                              liftKey: recorded.id))
        context.insert(PersonalRecord(liftId: recorded.id, kg: 40))
        try context.save()

        XCTAssertFalse(UserVariantStore.canDelete(recorded.id, context: context))
        XCTAssertTrue(UserVariantStore.canDelete(fresh.id, context: context))

        XCTAssertFalse(UserVariantStore.remove(recorded, context: context))
        XCTAssertTrue(recorded.isHidden)
        XCTAssertTrue(UserVariantStore.remove(fresh, context: context))

        let remaining = try context.fetch(FetchDescriptor<UserVariant>())
        XCTAssertEqual(remaining.map(\.id), [recorded.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), 1)

        let sections = VariantSections.build(exerciseId: machine, library: library, gymBrandIds: ["hammer"],
                                             userVariants: remaining)
        XCTAssertFalse(sections.flatMap(\.rows).contains { $0.id == recorded.id })
    }

    // MARK: Guide header (AC19)

    func testGuideVariantHeader() {
        XCTAssertNil(GuideVariantHeader.text(exerciseId: machine, variantId: machine, fallbackName: nil, userVariant: nil))
        let preset = library.variants(ofExercise: machine).first { $0.brandId == "hammer" }!
        XCTAssertEqual(GuideVariantHeader.text(exerciseId: machine, variantId: preset.id, fallbackName: nil, userVariant: nil),
                       "해머스트렝스 · \(preset.name)")
        let mine = userVariant(machine)
        XCTAssertEqual(GuideVariantHeader.text(exerciseId: machine, variantId: mine.id, fallbackName: nil, userVariant: mine),
                       "해머스트렝스 · 파란 머신")
        let other = userVariant(ExerciseLibrary.otherId, nickname: "스쿼트 머신", brandId: nil)
        XCTAssertEqual(GuideVariantHeader.text(exerciseId: ExerciseLibrary.otherId, variantId: other.id,
                                               fallbackName: "스쿼트 머신", userVariant: other), "스쿼트 머신")
        XCTAssertEqual(GuideVariantHeader.text(exerciseId: ExerciseLibrary.otherId, variantId: other.id,
                                               fallbackName: "저장된 이름", userVariant: nil), "저장된 이름")
    }
}

extension PickerTests {
    func testUserVariantSlotDisplaysNickname() {
        let slot = ScheduleExercise.makeCustom(
            exerciseId: "machine-chest-press",
            variantId: "machine-chest-press/u-test",
            name: "해머스트렝스 파란 머신",
            plane: "upper"
        )
        XCTAssertEqual(slot.displayName, "해머스트렝스 파란 머신")
        let generic = ScheduleExercise.makeCustom(exerciseId: "bench", variantId: "bench", name: "임의", plane: "upper")
        XCTAssertEqual(generic.displayName, "벤치프레스")
    }
}

// MARK: - Review fixes (H1, M1, M2, M4, L1)

extension PickerTests {
    private func routineSchedule(with slot: ScheduleExercise) -> ProgramSchedule {
        var schedule = ProgramSchedule.makeCustom(name: "변형 루틴")
        schedule.days[0].exercises = [slot]
        return schedule
    }

    func testFreeTextReusesExistingOtherVariant() throws {
        let context = try makeContext()
        let first = try XCTUnwrap(UserVariantStore.addFreeText("케이블 X", context: context))
        let second = try XCTUnwrap(UserVariantStore.addFreeText(" 케이블x ", context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserVariant>()), 1)
        XCTAssertEqual(second.variantId, first.variantId)
        XCTAssertNotEqual(second.id, first.id, "each pick is its own slot")

        // A hidden variant is not reused; a new visible one is created.
        let hidden = try XCTUnwrap(context.fetch(FetchDescriptor<UserVariant>()).first)
        hidden.isHidden = true
        try context.save()
        let third = try XCTUnwrap(UserVariantStore.addFreeText("케이블 X", context: context))
        XCTAssertNotEqual(third.variantId, first.variantId)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserVariant>()), 2)
    }

    func testUserVariantSearchMatchesNicknameAndBrand() {
        let mine = userVariant(machine, nickname: "2층 파란 머신", brandId: "hammer")
        let custom = userVariant(machine, nickname: "구석 머신", brandId: nil)
        custom.brandName = "동네브랜드"
        let other = userVariant(ExerciseLibrary.otherId, nickname: "스쿼트 머신", brandId: nil)
        let hidden = userVariant(machine, nickname: "파란 숨김", hidden: true)
        let all = [mine, custom, other, hidden]

        XCTAssertEqual(UserVariantSearch.match(query: "파란", variants: all, library: library).map(\.id), [mine.id])
        XCTAssertEqual(UserVariantSearch.match(query: "2층파란", variants: all, library: library).map(\.id), [mine.id])
        XCTAssertEqual(UserVariantSearch.match(query: "동네 브랜드", variants: all, library: library).map(\.id), [custom.id])
        XCTAssertEqual(UserVariantSearch.match(query: "해머", variants: all, library: library).map(\.id), [mine.id])
        XCTAssertEqual(UserVariantSearch.match(query: "스쿼트머신", variants: all, library: library).map(\.id), [other.id])
        XCTAssertEqual(Set(UserVariantSearch.match(query: "머신", variants: all, library: library).map(\.id)),
                       [mine.id, custom.id, other.id])
        XCTAssertTrue(UserVariantSearch.match(query: "  ", variants: all, library: library).isEmpty)
        // The library search stays library-only.
        XCTAssertFalse(library.search("2층 파란").contains { $0.exercise.id == machine })
    }

    func testUserVariantInScheduleIsHiddenNotDeleted() throws {
        let context = try makeContext()
        let inRoutine = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "루틴용"), context: context))
        let inPending = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "대기용"), context: context))
        let unused = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "안 씀"), context: context))

        let routineSlot = ScheduleExercise.makeCustom(exerciseId: machine, variantId: inRoutine.id,
                                                      name: inRoutine.displayName(in: library), plane: "upper")
        let schedule = routineSchedule(with: routineSlot)
        _ = SessionService.persistCustom(context: context, existing: nil, schedule: schedule, cycle: nil)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults)
        cycle.pendingSchedule = routineSchedule(with: .makeCustom(exerciseId: machine, variantId: inPending.id,
                                                                  name: "대기용", plane: "upper"))
        try context.save()

        XCTAssertFalse(UserVariantStore.canDelete(inRoutine.id, context: context))
        XCTAssertFalse(UserVariantStore.canDelete(inPending.id, context: context))
        XCTAssertTrue(UserVariantStore.canDelete(unused.id, context: context))

        XCTAssertFalse(UserVariantStore.remove(inRoutine, context: context))
        XCTAssertTrue(inRoutine.isHidden)
        XCTAssertTrue(UserVariantStore.remove(unused, context: context))
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<UserVariant>()).map(\.id)), [inRoutine.id, inPending.id])
    }

    func testRenamingUserVariantUpdatesSchedules() throws {
        let context = try makeContext()
        var draft = UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "파란 머신")
        let variant = try XCTUnwrap(UserVariantStore.insert(draft, context: context))
        let slot = ScheduleExercise.makeCustom(exerciseId: machine, variantId: variant.id,
                                               name: variant.displayName(in: library), plane: "upper")
        var schedule = routineSchedule(with: slot)
        schedule.days[0].exercises.append(.makeCustom(exerciseId: "bench"))
        let routine = SessionService.persistCustom(context: context, existing: nil, schedule: schedule, cycle: nil)
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: .documentDefaults)
        cycle.pendingSchedule = schedule
        let draftBefore = cycle.draftJSON
        try context.save()

        draft.nickname = "빨간 머신"
        UserVariantStore.update(variant, from: draft, context: context)

        for stored in [routine.resolvedSchedule(), cycle.resolvedSchedule(), cycle.pendingSchedule] {
            let exercises = try XCTUnwrap(stored).days[0].exercises
            XCTAssertEqual(exercises[0].name, "해머스트렝스 빨간 머신")
            XCTAssertEqual(exercises[0].displayName, "해머스트렝스 빨간 머신")
            XCTAssertEqual(exercises[0].id, slot.id)
            XCTAssertEqual(exercises[1].name, "벤치프레스", "other slots untouched")
        }
        XCTAssertEqual(cycle.draftJSON, draftBefore)
    }

    func testExportUsesNicknameForUserVariant() throws {
        let context = try makeContext()
        let variant = try XCTUnwrap(UserVariantStore.insert(
            UserVariantDraft(exerciseId: machine, brandId: "hammer", nickname: "파란 머신"), context: context))
        context.insert(PersonalRecord(liftId: variant.id, kg: 50))
        context.insert(PersonalRecord(liftId: machine, kg: 40))
        try context.save()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(SessionService.ExportDocument.self, from: SessionService.exportJSON(context: context))
        let lifts = Dictionary(uniqueKeysWithValues: export.personalRecords.map { ($0.liftId, $0.lift) })
        XCTAssertEqual(lifts[variant.id], "파란 머신")
        XCTAssertEqual(lifts[machine], library.displayName(variantId: machine))
    }

    func testHintsScopedByStateKey() throws {
        let context = try makeContext()
        var heavy = ScheduleExercise.makeCustom(exerciseId: "shrug", sets: 1, reps: 5)
        heavy.progressionTag = "heavy"
        var light = ScheduleExercise.makeCustom(exerciseId: "shrug", sets: 1, reps: 12)
        light.progressionTag = "light"
        light.label = "라이트"
        let plain = ScheduleExercise.makeCustom(exerciseId: "bench", sets: 1, reps: 10)
        var schedule = ProgramSchedule.makeCustom()
        schedule.days = [ProgramDay(id: "a", name: "A", isRest: false, exercises: [heavy, plain]),
                         ProgramDay(id: "b", name: "B", isRest: false, exercises: [light])]

        func log(_ slot: ScheduleExercise, kg: Double, reps: Int, date: Date) {
            context.insert(SetLog(exerciseId: slot.id, exerciseName: slot.displayName, setIndex: 0, kg: kg, reps: reps,
                                  completed: true, isWorking: true, isAMRAP: false, isWarmup: false, isBBB: false,
                                  liftKey: slot.liftKey, date: date))
        }
        log(heavy, kg: 100, reps: 5, date: Date(timeIntervalSince1970: 1_000))
        log(light, kg: 60, reps: 12, date: Date(timeIntervalSince1970: 2_000))
        log(plain, kg: 70, reps: 10, date: Date(timeIntervalSince1970: 3_000))
        try context.save()

        func row(_ slot: ScheduleExercise) -> PrescribedSet {
            PrescribedSet(exerciseId: slot.id, exerciseName: slot.displayName, liftKey: slot.liftKey, setIndex: 0,
                          kg: 0, reps: slot.repMax, repMax: slot.repMax, isWorking: true, isWarmup: false,
                          isAMRAP: false, isBBB: false, isOptional: false)
        }
        let hints = SessionService.lastHints(context: context, rows: [row(heavy), row(plain), row(light)],
                                             schedule: schedule)
        XCTAssertEqual(hints[heavy.id]?.kg, 100, "heavy slot must not show the newer light set")
        XCTAssertEqual(hints[light.id]?.kg, 60)
        XCTAssertEqual(hints[plain.id]?.kg, 70)

        // A tagged slot with no history of its own falls back to the variant's last set.
        var fresh = heavy
        fresh.id = "ex-fresh"
        fresh.progressionTag = "volume"
        schedule.days[0].exercises.append(fresh)
        let fallback = SessionService.lastHints(context: context, rows: [row(fresh)], schedule: schedule)
        XCTAssertEqual(fallback[fresh.id]?.kg, 60)
    }
}
