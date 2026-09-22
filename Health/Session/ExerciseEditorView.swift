import SwiftUI

struct ExerciseEditorView: View {
    var dayName: String
    @State var exercises: [ScheduleExercise]
    var usesOwnStack: Bool = true
    var onSave: ([ScheduleExercise]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    var body: some View {
        Group {
            if usesOwnStack {
                NavigationStack { editorBody }
            } else {
                editorBody
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { name in
                exercises.append(.makeCustom(name: name))
            }
        }
        .presentationBackground(Gym.bg)
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
                    showPicker = true
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
                    TextField("운동 이름", text: nameBinding(at: index))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Gym.text)
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

    private func nameBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { exercises.indices.contains(index) ? exercises[index].name : "" },
            set: { name in
                guard exercises.indices.contains(index) else { return }
                exercises[index].name = name
                exercises[index].plane = ExerciseGuide.defaultPlane(for: name)
            }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let next = index + offset
        guard exercises.indices.contains(index), exercises.indices.contains(next) else { return }
        exercises.swapAt(index, next)
    }
}

struct ExercisePickerSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var group = "전체"
    @State private var selected: [String] = []

    private var filtered: [String] {
        let all = ExerciseGuide.catalogTitles
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { title in
            let groupOK = group == "전체" || ExerciseGuide.group(for: title) == group
            let queryOK = q.isEmpty || title.localizedCaseInsensitiveContains(q)
            return groupOK && queryOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("운동 추가")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Gym.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Gym.muted)
                        .frame(width: 32, height: 32)
                        .background(Gym.card)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Gym.tabIdle)
                TextField("운동 이름 검색 · 없으면 직접 추가", text: $query)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Gym.text)
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !ExerciseGuide.catalogTitles.contains(where: { $0 == query.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                    Button("추가") {
                        toggle(query.trimmingCharacters(in: .whitespacesAndNewlines))
                        query = ""
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Gym.accent)
                }
            }
            .padding(14)
            .background(Gym.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExerciseGuide.filterGroups, id: \.self) { item in
                        Button {
                            group = item
                        } label: {
                            Text(item)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(group == item ? Gym.bg : Gym.muted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(group == item ? Gym.text : Gym.card)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { title in
                        let on = selected.contains(title)
                        Button { toggle(title) } label: {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Gym.text)
                                    Text(ExerciseGuide.lookup(name: title).muscle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Gym.faint)
                                }
                                Spacer()
                                Text(on ? "✓" : "+")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(on ? .white : Gym.muted)
                                    .frame(width: 34, height: 34)
                                    .background(on ? Gym.accent : Gym.elevated)
                                    .clipShape(Circle())
                            }
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }

            GymCTA(title: selected.isEmpty ? "닫기" : "\(selected.count)개 추가하기") {
                selected.forEach(onPick)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Gym.bg)
    }

    private func toggle(_ name: String) {
        if let i = selected.firstIndex(of: name) {
            selected.remove(at: i)
        } else {
            selected.append(name)
        }
    }
}
