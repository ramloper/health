import SwiftUI
import SwiftData

/// "우리 헬스장 브랜드": multi-select of the bundled brands, written to `AthleteProfile.gymBrandIds`.
struct GymBrandsSheet: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeStore.shared

    private var brands: [LibraryBrand] { ExerciseLibrary.shared.brands }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("우리 헬스장 브랜드")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Gym.text)
                Spacer()
                Button("완료") { dismiss() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Gym.accent)
                    .accessibilityIdentifier("gym-brands-done")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Text("선택한 브랜드의 머신이 운동 추가 화면에서 먼저 보여요.")
                .font(.system(size: 13))
                .foregroundStyle(Gym.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 6)

            ScrollView {
                GymCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(brands) { brand in
                            row(brand)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Gym.bg)
        .presentationDetents([.large])
    }

    private func row(_ brand: LibraryBrand) -> some View {
        let on = profile.gymBrandIds.contains(brand.id)
        return Button { toggle(brand.id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(brand.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Gym.text)
                    Text(brand.englishName)
                        .font(.system(size: 12))
                        .foregroundStyle(Gym.faint)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? Gym.accent : Gym.tabIdle)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("gym-brand-\(brand.id)")
    }

    private func toggle(_ id: String) {
        if let index = profile.gymBrandIds.firstIndex(of: id) {
            profile.gymBrandIds.remove(at: index)
        } else {
            // Keep library order so the picker sections are stable.
            let selected = Set(profile.gymBrandIds + [id])
            profile.gymBrandIds = brands.map(\.id).filter(selected.contains)
        }
        try? context.save()
    }
}
