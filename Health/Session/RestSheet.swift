import SwiftUI

struct RestDurationSheet: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    private var pal: GymPalette { theme.palette }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(pal.faint.opacity(0.45))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            HStack {
                Text("기본 휴식")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(pal.text)
                Spacer()
                Button("완료") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(pal.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 20) {
                Text(clock(theme.restSeconds))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(pal.text)

                HStack(spacing: 12) {
                    restAdjust(-10)
                    restAdjust(10)
                }

                HStack {
                    ForEach([60, 90, 120, 180], id: \.self) { preset in
                        Button(clock(preset)) { theme.restSeconds = preset }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(theme.restSeconds == preset ? pal.accent : pal.elevated)
                            .foregroundStyle(theme.restSeconds == preset ? pal.onAccent : pal.text)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(24)
            Spacer()
        }
        .background(pal.card)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .presentationDetents([.height(340)])
        .presentationBackground(pal.card)
    }

    private func restAdjust(_ delta: Int) -> some View {
        Button {
            theme.restSeconds = min(600, max(10, theme.restSeconds + delta))
        } label: {
            Text(delta > 0 ? "+10초" : "-10초")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(pal.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(pal.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct RestCountdownSheet: View {
    var remaining: Int
    var onAdjust: (Int) -> Void
    var onSkip: () -> Void
    @ObservedObject private var theme = ThemeStore.shared

    private var pal: GymPalette { theme.palette }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(pal.faint.opacity(0.45))
                .frame(width: 40, height: 4)
                .padding(.top, 10)

            Text("휴식")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pal.faint)
                .padding(.top, 20)

            Text(clock(remaining))
                .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(pal.text)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button {
                    onAdjust(-10)
                } label: {
                    Text("-10초")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pal.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(pal.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onAdjust(10)
                } label: {
                    Text("+10초")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pal.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(pal.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Button(action: onSkip) {
                Text("휴식 건너뛰기")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(pal.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(pal.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(24)

            Spacer()
        }
        .background(pal.card)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .presentationDetents([.medium])
        .presentationBackground(pal.card)
        .interactiveDismissDisabled(false)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
