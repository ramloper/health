import SwiftUI

struct DayPickerSheet: View {
    var schedule: ProgramSchedule
    var selectedId: String
    var onPick: (ProgramDay) -> Void
    @Environment(\.dismiss) private var dismiss

    private var trainingDays: [ProgramDay] {
        DayCursor.trainingDays(in: schedule)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("오늘 할 운동")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Gym.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)

                    if trainingDays.isEmpty {
                        Text("요일이 없어요. 루틴을 다시 수정해 주세요.")
                            .font(.system(size: 15))
                            .foregroundStyle(Gym.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                    }

                    ForEach(trainingDays) { day in
                        Button {
                            onPick(day)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(day.name)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundStyle(Gym.text)
                                    Text("\(day.exercises.count)개 운동")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Gym.faint)
                                }
                                Spacer()
                                if day.id == selectedId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Gym.accent)
                                        .font(.title2)
                                }
                            }
                            .padding(16)
                            .background(day.id == selectedId ? Gym.accentSoft : Gym.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Gym.bg)
            .navigationTitle(schedule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Gym.muted)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Gym.bg)
    }
}
