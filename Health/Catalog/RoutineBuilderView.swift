import SwiftUI
import SwiftData

struct RoutineBuilderView: View {
    var existing: CustomRoutine?
    var seed: ProgramSchedule
    var cycle: TrainingCycle?
    var onFinished: (ProgramSchedule, Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var days: [ProgramDay]
    @State private var scheduleId: String
    @State private var editingDay: ProgramDay?

    init(
        existing: CustomRoutine?,
        seed: ProgramSchedule,
        cycle: TrainingCycle?,
        onFinished: @escaping (ProgramSchedule, Bool) -> Void
    ) {
        self.existing = existing
        self.seed = seed
        self.cycle = cycle
        self.onFinished = onFinished
        _name = State(initialValue: seed.name)
        _days = State(initialValue: seed.days)
        _scheduleId = State(initialValue: seed.id)
    }

    private var trimmedName: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "내 루틴" : value
    }

    private var canStart: Bool {
        days.contains { !$0.isRest && !$0.exercises.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    GymCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("루틴 이름")
                                .font(.caption)
                                .foregroundStyle(Gym.muted)
                            TextField("예: 집 헬스 4일", text: $name)
                                .font(.title3.weight(.bold))
                        }
                    }

                    Button {
                        save(startNow: true)
                    } label: {
                        Text("사용")
                            .font(.headline)
                            .foregroundStyle(Gym.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canStart ? Gym.accent : Gym.accent.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)

                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        dayCard(index: index, day: day)
                    }

                    Button {
                        days.append(.blank(named: "\(days.count + 1)일차"))
                    } label: {
                        Label("요일 추가", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Gym.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Gym.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        save(startNow: false)
                    } label: {
                        Text("저장")
                            .font(.headline)
                            .foregroundStyle(Gym.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Gym.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Gym.bg)
            .navigationTitle(existing == nil ? "새 루틴" : "루틴 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Gym.muted)
                }
            }
            .navigationDestination(item: $editingDay) { day in
                ExerciseEditorView(
                    dayName: day.name,
                    exercises: liveExercises(for: day.id),
                    usesOwnStack: false
                ) { updated in
                    if let index = days.firstIndex(where: { $0.id == day.id }) {
                        days[index].exercises = updated
                    }
                }
            }
        }
        .presentationBackground(Gym.bg)
    }

    private func liveExercises(for dayId: String) -> [ScheduleExercise] {
        days.first(where: { $0.id == dayId })?.exercises ?? []
    }

    private func dayCard(index: Int, day: ProgramDay) -> some View {
        GymCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("요일 이름", text: bindingName(at: index))
                        .font(.headline)
                    Spacer()
                    if days.count > 1 {
                        Button(role: .destructive) {
                            days.removeAll { $0.id == day.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Gym.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if day.exercises.isEmpty {
                    Text("운동이 없습니다")
                        .font(.caption)
                        .foregroundStyle(Gym.muted)
                } else {
                    ForEach(day.exercises) { ex in
                        HStack {
                            Text(ex.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(ex.sets)세트 × \(ex.targetReps)회")
                                .font(.caption)
                                .foregroundStyle(Gym.muted)
                        }
                    }
                }
                Button {
                    editingDay = days[index]
                } label: {
                    Text("운동 편집")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Gym.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Gym.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bindingName(at index: Int) -> Binding<String> {
        Binding(
            get: { days.indices.contains(index) ? days[index].name : "" },
            set: { if days.indices.contains(index) { days[index].name = $0 } }
        )
    }

    private func save(startNow: Bool) {
        let schedule = ProgramSchedule(id: scheduleId, name: trimmedName, days: days)
        _ = SessionService.persistCustom(
            context: context,
            existing: existing,
            schedule: schedule,
            cycle: cycle
        )
        try? context.save()
        onFinished(schedule, startNow)
        dismiss()
    }
}
