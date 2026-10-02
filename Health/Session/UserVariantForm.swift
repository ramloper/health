import SwiftUI
import SwiftData

/// Validated input of the user variant form (AC10).
struct UserVariantDraft: Equatable {
    var exerciseId: String
    /// Library brand id; nil with `customBrand` for "직접 입력".
    var brandId: String?
    var customBrand: String = ""
    var nickname: String = ""
    var plane: String = "upper"

    var isOther: Bool { exerciseId == ExerciseLibrary.otherId }
    var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedCustomBrand: String { customBrand.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nickname is required; non-`other` variants also need a brand (library or typed). `other` is brandless.
    var isValid: Bool {
        guard !trimmedNickname.isEmpty else { return false }
        return isOther || brandId != nil || !trimmedCustomBrand.isEmpty
    }
}

/// SwiftData side of user variants, kept out of views so it is unit-tested.
enum UserVariantStore {
    static func newId(exerciseId: String) -> String {
        "\(exerciseId)/u-\(UUID().uuidString)"
    }

    /// Inserts a new variant from a valid draft. `other` keeps the draft plane; others use the exercise plane.
    @discardableResult
    static func insert(_ draft: UserVariantDraft, context: ModelContext,
                       library: ExerciseLibrary = .shared) -> UserVariant? {
        guard draft.isValid else { return nil }
        let variant = UserVariant(
            id: newId(exerciseId: draft.exerciseId),
            exerciseId: draft.exerciseId,
            brandId: draft.isOther ? nil : draft.brandId,
            brandName: draft.isOther || draft.brandId != nil ? nil : draft.trimmedCustomBrand,
            nickname: draft.trimmedNickname,
            plane: draft.isOther ? draft.plane : (library.exercise(id: draft.exerciseId)?.plane ?? draft.plane)
        )
        context.insert(variant)
        try? context.save()
        return variant
    }

    static func update(_ variant: UserVariant, from draft: UserVariantDraft, context: ModelContext) {
        guard draft.isValid else { return }
        variant.nickname = draft.trimmedNickname
        if draft.isOther {
            variant.plane = draft.plane
        } else {
            variant.brandId = draft.brandId
            variant.brandName = draft.brandId == nil ? draft.trimmedCustomBrand : nil
        }
        try? context.save()
    }

    /// Free text in the picker becomes a user variant of `other` (AC14), never a library exercise.
    static func addFreeText(_ text: String, context: ModelContext, library: ExerciseLibrary = .shared) -> ScheduleExercise? {
        let draft = UserVariantDraft(exerciseId: ExerciseLibrary.otherId, nickname: text, plane: PlaneGuess.guess(text))
        guard let variant = insert(draft, context: context, library: library) else { return nil }
        return .makeCustom(exerciseId: variant.exerciseId, variantId: variant.id, name: variant.nickname, plane: variant.plane)
    }

    /// A variant with any logged set or PR is hidden instead of deleted so records keep their key.
    static func canDelete(_ variantId: String, context: ModelContext) -> Bool {
        let sets = FetchDescriptor<SetLog>(predicate: #Predicate { $0.liftKey == variantId })
        let prs = FetchDescriptor<PersonalRecord>(predicate: #Predicate { $0.liftId == variantId })
        return ((try? context.fetchCount(sets)) ?? 1) == 0 && ((try? context.fetchCount(prs)) ?? 1) == 0
    }

    /// Deletes when unrecorded, otherwise hides. Returns true when deleted.
    @discardableResult
    static func remove(_ variant: UserVariant, context: ModelContext) -> Bool {
        let deleted = canDelete(variant.id, context: context)
        if deleted {
            context.delete(variant)
        } else {
            variant.isHidden = true
        }
        try? context.save()
        return deleted
    }
}

/// Create (pushed from "새 변형 만들기") or edit (long press on a user variant) a user variant.
struct UserVariantForm: View {
    var exerciseId: String
    var editing: UserVariant?
    var onPick: (ScheduleExercise) -> Void
    var close: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared
    @State private var draft: UserVariantDraft
    @State private var isCustomBrand = false
    @State private var planeTouched = false

    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    init(exerciseId: String, editing: UserVariant?, onPick: @escaping (ScheduleExercise) -> Void, close: @escaping () -> Void) {
        self.exerciseId = exerciseId
        self.editing = editing
        self.onPick = onPick
        self.close = close
        var draft = UserVariantDraft(exerciseId: exerciseId)
        if let editing {
            draft.brandId = editing.brandId
            draft.customBrand = editing.brandName ?? ""
            draft.nickname = editing.nickname
            draft.plane = editing.plane
        }
        _draft = State(initialValue: draft)
        _isCustomBrand = State(initialValue: editing != nil && editing?.brandId == nil && !(editing?.brandName ?? "").isEmpty)
        _planeTouched = State(initialValue: editing != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !draft.isOther {
                    field("브랜드") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(library.brands) { brand in
                                chip(brand.name, on: !isCustomBrand && draft.brandId == brand.id,
                                     identifier: "variant-form-brand-\(brand.id)") {
                                    isCustomBrand = false
                                    draft.brandId = brand.id
                                }
                            }
                            chip("직접 입력", on: isCustomBrand, identifier: "variant-form-brand-custom") {
                                isCustomBrand = true
                                draft.brandId = nil
                            }
                        }
                        if isCustomBrand {
                            textField("브랜드 이름", text: $draft.customBrand, identifier: "variant-form-brand-name")
                        }
                    }
                }

                field("별명") {
                    textField(draft.isOther ? "예: 스쿼트 머신" : "예: 2층 파란 머신", text: $draft.nickname,
                              identifier: "variant-form-nickname")
                }

                if draft.isOther {
                    field("부위") {
                        HStack(spacing: 8) {
                            chip("상체", on: draft.plane == "upper", identifier: "variant-form-plane-upper") {
                                planeTouched = true
                                draft.plane = "upper"
                            }
                            chip("하체", on: draft.plane == "lower", identifier: "variant-form-plane-lower") {
                                planeTouched = true
                                draft.plane = "lower"
                            }
                        }
                    }
                }

                GymCTA(title: editing == nil ? "저장하고 추가" : "저장", enabled: draft.isValid, action: save)
                    .accessibilityIdentifier("variant-form-save")

                if let editing {
                    let deletable = UserVariantStore.canDelete(editing.id, context: context)
                    Button(role: .destructive) {
                        UserVariantStore.remove(editing, context: context)
                        dismiss()
                    } label: {
                        Text(deletable ? "이 변형 삭제" : "숨기기 (기록은 그대로 남아요)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Gym.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("variant-form-remove")
                }
            }
            .padding(24)
        }
        .background(Gym.bg)
        .navigationTitle(editing == nil ? "새 변형" : "변형 수정")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft.nickname) { _, name in
            if draft.isOther && !planeTouched { draft.plane = PlaneGuess.guess(name) }
        }
    }

    private func save() {
        if let editing {
            UserVariantStore.update(editing, from: draft, context: context)
            dismiss()
            return
        }
        guard let variant = UserVariantStore.insert(draft, context: context, library: library) else { return }
        onPick(.makeCustom(exerciseId: variant.exerciseId, variantId: variant.id,
                           name: variant.displayName(in: library), plane: variant.plane))
        close()
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Gym.text)
            content()
        }
    }

    private func textField(_ prompt: String, text: Binding<String>, identifier: String) -> some View {
        TextField(prompt, text: text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Gym.text)
            .padding(14)
            .background(Gym.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityIdentifier(identifier)
    }

    private func chip(_ title: String, on: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(on ? Gym.bg : Gym.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Gym.text : Gym.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
