import SwiftUI

struct MetronomeSettingsView: View {
    @ObservedObject var metronome: GymMetronome
    @ObservedObject private var theme = ThemeStore.shared
    var showsToggle: Bool = true

    private var pal: GymPalette { theme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("메트로놈")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(pal.text)
                    Text("\(metronome.bpm) BPM")
                        .font(.system(size: 13))
                        .foregroundStyle(pal.faint)
                }
                Spacer()
                if showsToggle {
                    Toggle("", isOn: $metronome.isOn)
                        .labelsHidden()
                        .tint(pal.accent)
                }
            }

            HStack(spacing: 10) {
                metronomeNudge("minus") {
                    metronome.bpm = max(40, metronome.bpm - 2)
                }
                Text("\(metronome.bpm)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(metronome.isOn ? pal.accent : pal.text)
                    .frame(minWidth: 64)
                metronomeNudge("plus") {
                    metronome.bpm = min(180, metronome.bpm + 2)
                }
            }

            GymSlider(
                value: Binding(
                    get: { Double(metronome.bpm) },
                    set: { metronome.bpm = Int($0.rounded()) }
                ),
                range: 40...180,
                accent: pal.accent,
                track: pal.elevated
            )

            HStack {
                ForEach([60, 80, 100, 120], id: \.self) { preset in
                    Button("\(preset)") { metronome.bpm = preset }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(metronome.bpm == preset ? pal.accent : pal.elevated)
                        .foregroundStyle(metronome.bpm == preset ? pal.onAccent : pal.text)
                        .clipShape(Capsule())
                }
            }
        }
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private func metronomeNudge(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.body.weight(.bold))
                .foregroundStyle(pal.text)
                .frame(width: 36, height: 36)
                .background(pal.elevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GymSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var accent: Color
    var track: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = max(12, min(width - 12, width * progress))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                    .frame(height: 6)
                Capsule()
                    .fill(accent)
                    .frame(width: x, height: 6)
                Circle()
                    .fill(accent)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                    .offset(x: x - 12)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let p = min(1, max(0, drag.location.x / width))
                    value = range.lowerBound + p * (range.upperBound - range.lowerBound)
                }
            )
        }
        .frame(height: 28)
    }
}

struct MetronomeSettingsSheet: View {
    @ObservedObject var metronome: GymMetronome
    @ObservedObject private var theme = ThemeStore.shared
    var stopsOnDismiss = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.palette.faint.opacity(0.45))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            HStack {
                Text("메트로놈")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.palette.text)
                Spacer()
                Button("닫기") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.palette.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            MetronomeSettingsView(metronome: metronome)
                .padding(24)
            Spacer()
        }
        .background(theme.palette.card)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .presentationDetents([.height(360)])
        .presentationBackground(theme.palette.card)
        .onDisappear {
            if stopsOnDismiss { metronome.isOn = false }
        }
    }
}
