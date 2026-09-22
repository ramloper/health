import SwiftUI

struct NumberPadSheet: View {
    var title: String
    var unit: String
    var allowsDecimal: Bool
    var initial: Double
    var onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var raw: String

    init(title: String, unit: String, allowsDecimal: Bool, initial: Double, onConfirm: @escaping (Double) -> Void) {
        self.title = title
        self.unit = unit
        self.allowsDecimal = allowsDecimal
        self.initial = initial
        self.onConfirm = onConfirm
        let seed = allowsDecimal ? initial.gymKg : String(Int(initial.rounded()))
        _raw = State(initialValue: seed)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Gym.faint.opacity(0.5))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Gym.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Gym.muted)
                        .frame(width: 32, height: 32)
                        .background(Gym.elevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(raw.isEmpty ? "0" : raw)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Gym.text)
                Text(unit)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Gym.faint)
            }
            .padding(.vertical, 18)

            let keys: [[String]] = [
                ["1", "2", "3"],
                ["4", "5", "6"],
                ["7", "8", "9"],
                [allowsDecimal ? "." : "", "0", "⌫"]
            ]
            VStack(spacing: 10) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                tap(key)
                            } label: {
                                Text(key)
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundStyle(key.isEmpty ? .clear : Gym.text)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(key.isEmpty ? Color.clear : Gym.elevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(key.isEmpty)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            GymCTA(title: "입력") {
                let value = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? initial
                onConfirm(max(0, value))
                dismiss()
            }
            .padding(20)
        }
        .background(Gym.card)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            if !raw.isEmpty { raw.removeLast() }
            return
        }
        if key == "." {
            guard allowsDecimal, !raw.contains(".") else { return }
            if raw.isEmpty { raw = "0." } else { raw += "." }
            return
        }
        if raw == "0" { raw = key } else { raw += key }
        if raw.filter({ $0.isNumber }).count > 5 {
            raw.removeLast()
        }
    }
}
