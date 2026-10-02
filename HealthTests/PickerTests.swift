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
