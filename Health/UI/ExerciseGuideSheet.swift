import SwiftUI
import UIKit

struct ExerciseGuideSheet: View {
    var name: String
    var id: String = ""
    var last: (kg: Double, reps: Int)? = nil
    var prKg: Double? = nil
    var e1rm: Double? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let g = ExerciseGuide.lookup(name: name, id: id)
        let chips = g.muscle
            .replacingOccurrences(of: "(", with: "·")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x3A3A45).opacity(ThemeStore.shared.isDark ? 1 : 0.25))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(g.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Gym.text)
                    HStack(spacing: 6) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                            Text(chip)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(index == 0 ? Gym.accent : Gym.muted)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(index == 0 ? Gym.accentSoft : Gym.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Gym.muted)
                        .frame(width: 32, height: 32)
                        .background(Gym.elevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("닫기")
                .accessibilityIdentifier("guide-close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let imageName = g.imageName, UIImage(named: imageName) != nil {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .background(Color.white)
                    }
                    Text(g.summary)
                        .font(.system(size: 15))
                        .foregroundStyle(Gym.muted)
                        .lineSpacing(4)

                    HStack(spacing: 8) {
                        stat("최근", last.map { "\($0.kg.gymKg)×\($0.reps)" } ?? "—")
                        stat("최고 기록", prKg.map { "\($0.gymKg)" } ?? "—", unit: prKg == nil ? nil : "kg")
                        stat("1RM", e1rm.map { "\($0.gymKg)" } ?? "—", unit: e1rm == nil ? nil : "kg")
                    }

                    section("이렇게", items: g.steps)
                    section("이건 피하기", items: g.avoid)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Gym.card)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func stat(_ title: String, _ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Gym.faint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Gym.text)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Gym.faint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Gym.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Gym.text)
            ForEach(Array(items.enumerated()), id: \.offset) { i, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Gym.onAccent)
                        .frame(width: 18, height: 18)
                        .background(Gym.accent)
                        .clipShape(Circle())
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Gym.text)
                }
            }
        }
    }
}
