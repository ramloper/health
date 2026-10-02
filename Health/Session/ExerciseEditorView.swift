import SwiftUI

struct ExerciseEditorView: View {
    var dayName: String
    @State var exercises: [ScheduleExercise]
    var usesOwnStack: Bool = true
    var onSave: ([ScheduleExercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared
    @State private var picker: PickerTarget?

    /// `replacingSlotId == nil` adds a slot; otherwise "운동 바꾸기" swaps that slot's variant.
    private struct PickerTarget: Identifiable {
        let id = UUID()
        var replacingSlotId: String?
    }

    var body: some View {
        Group {
            if usesOwnStack {
                NavigationStack { editorBody }
            } else {
                editorBody
            }
        }
        .sheet(item: $picker) { target in
            ExercisePickerSheet(title: target.replacingSlotId == nil ? "운동 추가" : "운동 바꾸기",
                                close: { picker = nil }) { picked in
                apply(picked, replacing: target.replacingSlotId)
            }
        }
        .presentationBackground(Gym.bg)
    }

    private func apply(_ picked: ScheduleExercise, replacing slotId: String?) {
        guard let slotId else {
            exercises.append(picked)
            return
        }
        guard let index = exercises.firstIndex(where: { $0.id == slotId }) else { return }
        exercises[index] = exercises[index].replacingVariant(picked.variantId, name: picked.name,
                                                             exerciseId: picked.exerciseId, plane: picked.plane)
    }

    private var editorBody: some View {
        ScrollView {
            VStack(spacing: 12) {
                if exercises.isEmpty {
                    Text("아직 운동이 없어요. 아래에서 추가하세요.")
                        .font(.system(size: 15))
                        .foregroundStyle(Gym.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, _ in
                    exerciseCard(index: index)
                }
                Button {
                    picker = PickerTarget(replacingSlotId: nil)
                } label: {
                    Label("운동 추가", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Gym.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Gym.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Gym.bg)
        .navigationTitle("\(dayName) 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }.foregroundStyle(Gym.muted)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("저장") {
                    onSave(exercises)
                    dismiss()
                }
                .foregroundStyle(Gym.accent)
                .fontWeight(.bold)
            }
        }
    }

    private func exerciseCard(index: Int) -> some View {
        let ex = exercises[index]
        return GymCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ex.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Gym.text)
                        Button {
                            picker = PickerTarget(replacingSlotId: ex.id)
                        } label: {
                            Label("운동 바꾸기", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Gym.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("exercise-replace-\(ex.id)")
                    }
                    Spacer(minLength: 8)
                    if exercises.count > 1 {
                        Button { move(index, by: -1) } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(index == 0 ? Gym.faint.opacity(0.4) : Gym.muted)
                                .frame(width: 32, height: 32)
                                .background(Gym.elevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        Button { move(index, by: 1) } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(index == exercises.count - 1 ? Gym.faint.opacity(0.4) : Gym.muted)
                                .frame(width: 32, height: 32)
                                .background(Gym.elevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == exercises.count - 1)
                    }
                }

                editorRow("세트", value: "\(ex.sets)", minus: {
                    exercises[index].sets = max(1, ex.sets - 1)
                }, plus: {
                    exercises[index].sets += 1
                })
                editorRow("횟수", value: "\(ex.targetReps)", minus: {
                    exercises[index].targetReps = max(1, ex.targetReps - 1)
                }, plus: {
                    exercises[index].targetReps += 1
                })
                editorRow("시작 kg", value: (ex.seedKg ?? 20).gymKg, minus: {
                    exercises[index].seedKg = max(0, (ex.seedKg ?? 20) - 2.5)
                }, plus: {
                    exercises[index].seedKg = (ex.seedKg ?? 20) + 2.5
                })

                Button(role: .destructive) {
                    exercises.removeAll { $0.id == ex.id }
                } label: {
                    Text("이 운동 삭제")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Gym.accent)
                }
            }
        }
    }

    private func editorRow(_ title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Gym.muted)
            Spacer()
            NudgeButton(system: "minus", action: minus)
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Gym.text)
                .frame(minWidth: 44, alignment: .center)
            NudgeButton(system: "plus", action: plus)
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let next = index + offset
        guard exercises.indices.contains(index), exercises.indices.contains(next) else { return }
        exercises.swapAt(index, next)
    }
}


/// Two-step picker (D2): this root owns `close` and a `NavigationStack`; tapping an exercise pushes
/// `VariantPickerView`, long-pressing adds its generic variant. Every pick goes through `onPick` + `close`.
struct ExercisePickerSheet: View {
    var title: String = "운동 추가"
    /// Dismisses the sheet (sets the presenting state); pushed screens call it after picking.
    var close: () -> Void
    var onPick: (ScheduleExercise) -> Void
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @State private var query = ""
    @State private var group: MuscleGroup?
    @State private var equipment: Equipment?
    @State private var path: [String] = []

    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    private var hits: [ExerciseLibrary.SearchHit] {
        library.search(query, group: group, equipment: equipment)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { exerciseId in
                    VariantPickerView(exerciseId: exerciseId, onPick: onPick, close: close)
                }
        }
        .tint(Gym.accent)
    }

    private var root: some View {
        let hits = hits
        let unfiltered = group == nil && equipment == nil && trimmedQuery.isEmpty
        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Gym.text)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Gym.muted)
                        .frame(width: 32, height: 32)
                        .background(Gym.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
                .accessibilityIdentifier("picker-close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Gym.tabIdle)
                TextField("운동·브랜드 검색", text: $query)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Gym.text)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("picker-search")
            }
            .padding(14)
            .background(Gym.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 18)

            chipRow([MuscleGroup?.none] + MuscleGroup.allCases.map(Optional.some), selection: $group,
                    label: { $0?.label ?? "전체" }, identifier: { "group-chip-\($0?.rawValue ?? "all")" })
                .padding(.top, 14)
            chipRow([Equipment?.none] + Equipment.allCases.map(Optional.some), selection: $equipment,
                    label: { $0?.label ?? "전체" }, identifier: { "equip-chip-\($0?.rawValue ?? "all")" })
                .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if hits.isEmpty && !trimmedQuery.isEmpty {
                        freeTextRow(trimmedQuery)
                    }
                    ForEach(hits) { hit in
                        exerciseRow(hit)
                    }
                    if unfiltered {
                        otherRow
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .padding(.top, 6)
        }
        .background(Gym.bg)
    }

    private func chipRow<Item: Hashable>(_ items: [Item], selection: Binding<Item>, label: @escaping (Item) -> String,
                                         identifier: @escaping (Item) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = selection.wrappedValue == item
                    Button {
                        selection.wrappedValue = item
                    } label: {
                        Text(label(item))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Gym.bg : Gym.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? Gym.text : Gym.card)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier(identifier(item))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func exerciseRow(_ hit: ExerciseLibrary.SearchHit) -> some View {
        let exercise = hit.exercise
        return rowContent(title: exercise.name,
                          subtitle: "\(exercise.group.label) · \(exercise.equipment.label)",
                          hint: matchedHint(hit.matchedVariants))
            .onLongPressGesture(minimumDuration: 0.4) { addGeneric(exercise.id) }
            .onTapGesture { path.append(exercise.id) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { path.append(exercise.id) }
            .accessibilityAction(named: "일반으로 추가") { addGeneric(exercise.id) }
            .accessibilityIdentifier("ex-row-\(exercise.id)")
    }

    /// `other` has no generic variant, so no long press: it only opens the user-variant list.
    private var otherRow: some View {
        rowContent(title: ExerciseLibrary.otherName, subtitle: "내가 만든 운동", hint: nil)
            .onTapGesture { path.append(ExerciseLibrary.otherId) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { path.append(ExerciseLibrary.otherId) }
            .accessibilityIdentifier("ex-row-\(ExerciseLibrary.otherId)")
    }

    private func freeTextRow(_ text: String) -> some View {
        Button {
            guard let slot = UserVariantStore.addFreeText(text, context: context, library: library) else { return }
            onPick(slot)
            close()
        } label: {
            Label("'\(text)' 직접 추가", systemImage: "plus.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Gym.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("picker-add-free")
    }

    private func rowContent(title: String, subtitle: String, hint: String?) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Gym.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Gym.faint)
                if let hint {
                    Text(hint)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Gym.accent)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Gym.tabIdle)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func matchedHint(_ variants: [LibraryVariant]) -> String? {
        guard !variants.isEmpty else { return nil }
        let names = variants.prefix(2).compactMap { library.displayName(variantId: $0.id) }
        let more = variants.count > 2 ? " 외 \(variants.count - 2)개" : ""
        return names.joined(separator: ", ") + more
    }

    private func addGeneric(_ exerciseId: String) {
        onPick(.makeCustom(exerciseId: exerciseId))
        close()
    }
}
