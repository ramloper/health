import SwiftUI

/// Today's exercise list during a session: reorder groups, jump to one, add or remove today-only exercises.
/// Nothing here changes the routine.
struct SessionPlanSheet: View {
    var groups: [[PrescribedSet]]
    var focusId: String?
    /// Slot ids of today-only exercises.
    var extraSlotIds: Set<String>
    /// Completed sets per group id.
    var doneByGroup: [String: Int]
    var onMove: (_ index: Int, _ offset: Int) -> Void
    var onFocus: (_ groupId: String) -> Void
    var onAdd: (ScheduleExercise) -> Void
    var onRemoveExtra: (_ slotId: String) -> Void
    var onSetExtraSets: (_ slotId: String, _ sets: Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("오늘 운동")
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
                .accessibilityLabel("닫기")
                .accessibilityIdentifier("plan-close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Text("순서를 바꾸거나 오늘만 할 운동을 추가해요. 루틴은 바뀌지 않아요.")
                .font(.system(size: 13))
                .foregroundStyle(Gym.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        row(index: index, group: group)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            Button { showPicker = true } label: {
                Label("오늘만 운동 추가", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Gym.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Gym.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan-add")
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Gym.bg)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .presentationBackground(Gym.bg)
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet(title: "오늘만 운동 추가", close: { showPicker = false }, onPick: onAdd)
        }
    }

    private func row(index: Int, group: [PrescribedSet]) -> some View {
        let first = group[0]
        let isExtra = extraSlotIds.contains(first.exerciseId)
        let done = doneByGroup[first.groupId] ?? 0
        let isCurrent = first.groupId == focusId
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    onFocus(first.groupId)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        GymIndexBadge(text: "\(index + 1)")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(first.exerciseName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(done == group.count ? Gym.faint : Gym.text)
                                .multilineTextAlignment(.leading)
                            Text(subtitle(group: group, done: done, isExtra: isExtra, isCurrent: isCurrent))
                                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? Gym.accent : Gym.faint)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(first.exerciseName), \(subtitle(group: group, done: done, isExtra: isExtra, isCurrent: isCurrent))")
                .accessibilityHint("이 운동으로 이동")
                .accessibilityIdentifier("plan-row-\(index)")

                moveButton("chevron.up", enabled: index > 0, identifier: "plan-up-\(index)", label: "위로") {
                    onMove(index, -1)
                }
                moveButton("chevron.down", enabled: index < groups.count - 1, identifier: "plan-down-\(index)",
                           label: "아래로") {
                    onMove(index, 1)
                }
            }
            if isExtra {
                HStack(spacing: 10) {
                    Text("세트")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Gym.muted)
                    NudgeButton(system: "minus") { onSetExtraSets(first.exerciseId, group.count - 1) }
                        .disabled(group.count <= max(1, done))
                        .opacity(group.count <= max(1, done) ? 0.4 : 1)
                    Text("\(group.count)")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Gym.text)
                        .frame(minWidth: 24)
                    NudgeButton(system: "plus") { onSetExtraSets(first.exerciseId, group.count + 1) }
                        .disabled(group.count >= 10)
                        .opacity(group.count >= 10 ? 0.4 : 1)
                    Spacer()
                    if done == 0 {
                        Button("빼기") { onRemoveExtra(first.exerciseId) }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Gym.accent)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("plan-remove-\(index)")
                    }
                }
            }
        }
        .padding(14)
        .background(Gym.card)
        .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
    }

    private func subtitle(group: [PrescribedSet], done: Int, isExtra: Bool, isCurrent: Bool) -> String {
        var parts = ["\(done)/\(group.count)세트"]
        if group.first?.isBBB == true { parts.append("BBB") }
        if isExtra { parts.append("오늘만") }
        if isCurrent { parts.append("진행 중") }
        return parts.joined(separator: " · ")
    }

    private func moveButton(_ system: String, enabled: Bool, identifier: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Gym.muted : Gym.faint.opacity(0.4))
                .frame(width: 36, height: 36)
                .background(Gym.elevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
