import SwiftUI
import SwiftData

/// Section layout of the variant sheet (AC12/AC17). Pure so it is unit-tested without UI.
enum VariantSections {
    enum Kind: Equatable {
        /// "일반": the generic variant (`id == exerciseId`). Absent for `other`.
        case generic
        /// "내 헬스장": preset variants of the user's gym brands + user variants. Only when gym brands are set.
        case gym
        /// "내 변형": user variants when no gym brand is set (and always for `other`).
        case myVariants
        /// "다른 브랜드": remaining preset variants, collapsed, grouped by brand.
        case otherBrands
        /// "새 변형 만들기".
        case new
    }

    struct Row: Equatable, Identifiable {
        /// Variant id (library or user).
        let id: String
        let title: String
        /// Brand name shown for grouping and subtitles; nil for generic and brandless user variants.
        let brandName: String?
        let isUser: Bool
    }

    struct Section: Equatable {
        let kind: Kind
        let rows: [Row]
    }

    static func build(exerciseId: String, library: ExerciseLibrary, gymBrandIds: [String],
                      userVariants: [UserVariant]) -> [Section] {
        let mine = userVariants
            .filter { $0.exerciseId == exerciseId && !$0.isHidden }
            .map { Row(id: $0.id, title: $0.displayName(in: library), brandName: $0.brandLabel(in: library), isUser: true) }

        if exerciseId == ExerciseLibrary.otherId {
            var sections: [Section] = []
            if !mine.isEmpty { sections.append(Section(kind: .myVariants, rows: mine)) }
            sections.append(Section(kind: .new, rows: []))
            return sections
        }

        let generic = Row(id: exerciseId, title: "일반",
                          brandName: nil, isUser: false)
        var sections = [Section(kind: .generic, rows: [generic])]

        let gym = Set(gymBrandIds)
        let brandOrder = Dictionary(library.brands.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let presets = library.variants(ofExercise: exerciseId)
        func row(_ v: LibraryVariant) -> Row {
            Row(id: v.id, title: v.name, brandName: v.brandId.flatMap { library.brand(id: $0)?.name }, isUser: false)
        }

        if !gym.isEmpty {
            let gymPresets = presets.filter { $0.brandId.map(gym.contains) == true }.map(row)
            sections.append(Section(kind: .gym, rows: gymPresets + mine))
        } else if !mine.isEmpty {
            sections.append(Section(kind: .myVariants, rows: mine))
        }

        let others = presets
            .enumerated()
            .filter { $0.element.brandId.map(gym.contains) != true }
            .sorted {
                let a = $0.element.brandId.flatMap { brandOrder[$0] } ?? Int.max
                let b = $1.element.brandId.flatMap { brandOrder[$0] } ?? Int.max
                return a == b ? $0.offset < $1.offset : a < b
            }
            .map { row($0.element) }
        if !others.isEmpty { sections.append(Section(kind: .otherBrands, rows: others)) }

        sections.append(Section(kind: .new, rows: []))
        return sections
    }

    /// Slot for a picked row. User variants carry their own plane (`other` has no library plane).
    static func slot(exerciseId: String, row: Row, library: ExerciseLibrary,
                     userVariants: [UserVariant]) -> ScheduleExercise {
        if row.isUser, let uv = userVariants.first(where: { $0.id == row.id }) {
            return .makeCustom(exerciseId: exerciseId, variantId: uv.id, name: uv.displayName(in: library), plane: uv.plane)
        }
        return .makeCustom(exerciseId: exerciseId, variantId: row.id)
    }
}

extension UserVariant {
    /// Library brand name, or the free-text brand; nil when neither (e.g. `other`).
    func brandLabel(in library: ExerciseLibrary) -> String? {
        if let name = brandId.flatMap({ library.brand(id: $0)?.name }) { return name }
        let custom = brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? nil : custom
    }

    /// "브랜드명 별명" like preset variants; just the nickname when brandless.
    func displayName(in library: ExerciseLibrary) -> String {
        brandLabel(in: library).map { "\($0) \(nickname)" } ?? nickname
    }
}

/// Second picker step, pushed inside the picker's `NavigationStack`. `close` dismisses the whole picker sheet.
struct VariantPickerView: View {
    var exerciseId: String
    var onPick: (ScheduleExercise) -> Void
    var close: () -> Void
    @Environment(\.modelContext) private var context
    @ObservedObject private var theme = ThemeStore.shared
    @Query private var profiles: [AthleteProfile]
    @Query(sort: \UserVariant.createdAt) private var userVariants: [UserVariant]
    @State private var otherBrandsExpanded = false
    @State private var form: FormTarget?

    private var library: ExerciseLibrary { ExerciseLibrary.shared }

    private struct FormTarget: Identifiable, Hashable {
        var id: String { editingId ?? "new" }
        var editingId: String?
    }

    private var title: String {
        library.info(for: exerciseId)?.name ?? exerciseId
    }

    private var sections: [VariantSections.Section] {
        VariantSections.build(exerciseId: exerciseId, library: library,
                              gymBrandIds: profiles.first?.gymBrandIds ?? [], userVariants: userVariants)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let info = library.info(for: exerciseId), let group = info.group, let equipment = info.equipment {
                    Text("\(group.label) · \(equipment.label)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Gym.faint)
                }
                ForEach(sections, id: \.kind) { section in
                    sectionView(section)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Gym.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $form) { target in
            UserVariantForm(
                exerciseId: exerciseId,
                editing: target.editingId.flatMap { id in userVariants.first { $0.id == id } },
                onPick: onPick,
                close: close
            )
        }
    }

    @ViewBuilder
    private func sectionView(_ section: VariantSections.Section) -> some View {
        switch section.kind {
        case .generic:
            GymCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(section.rows) { row in
                        variantRow(row, subtitle: title)
                    }
                }
                .padding(.horizontal, 16)
            }
        case .gym:
            titled("내 헬스장", identifier: "gym-section") {
                if section.rows.isEmpty {
                    Text("설정한 브랜드의 변형이 없어요")
                        .font(.system(size: 14))
                        .foregroundStyle(Gym.faint)
                        .padding(.vertical, 14)
                } else {
                    ForEach(section.rows) { row in
                        variantRow(row, subtitle: row.isUser ? "내 변형" : row.brandName)
                    }
                }
            }
        case .myVariants:
            titled("내 변형", identifier: "my-variants-section") {
                ForEach(section.rows) { row in
                    variantRow(row, subtitle: nil)
                }
            }
        case .otherBrands:
            GymCard(padding: 0) {
                DisclosureGroup(isExpanded: $otherBrandsExpanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(brandGroups(section.rows), id: \.brand) { group in
                            Text(group.brand)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Gym.faint)
                                .padding(.top, 12)
                            ForEach(group.rows) { row in
                                variantRow(row, subtitle: nil)
                            }
                        }
                    }
                } label: {
                    Text("다른 브랜드")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Gym.text)
                        .padding(.vertical, 14)
                }
                .tint(Gym.muted)
                .accessibilityIdentifier("other-brands-section")
                .padding(.horizontal, 16)
            }
        case .new:
            Button {
                form = FormTarget(editingId: nil)
            } label: {
                Label("새 변형 만들기", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Gym.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Gym.card)
                    .clipShape(RoundedRectangle(cornerRadius: Gym.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("variant-new")
        }
    }

    private func titled<Content: View>(_ heading: String, identifier: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Gym.text)
                .padding(.horizontal, 4)
            GymCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func brandGroups(_ rows: [VariantSections.Row]) -> [(brand: String, rows: [VariantSections.Row])] {
        var groups: [(brand: String, rows: [VariantSections.Row])] = []
        for row in rows {
            let brand = row.brandName ?? ""
            if groups.last?.brand == brand {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((brand, [row]))
            }
        }
        return groups
    }

    private func variantRow(_ row: VariantSections.Row, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Gym.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Gym.faint)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Gym.muted)
                .frame(width: 32, height: 32)
                .background(Gym.elevated)
                .clipShape(Circle())
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { pick(row) }
        .onLongPressGesture(minimumDuration: 0.4) {
            if row.isUser { form = FormTarget(editingId: row.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pick(row) }
        .modifier(EditActionIfUser(isUser: row.isUser) { form = FormTarget(editingId: row.id) })
        .accessibilityIdentifier("variant-row-\(row.id)")
    }

    private func pick(_ row: VariantSections.Row) {
        onPick(VariantSections.slot(exerciseId: exerciseId, row: row, library: library, userVariants: userVariants))
        close()
    }
}

/// VoiceOver equivalent of the long press on user variant rows.
private struct EditActionIfUser: ViewModifier {
    var isUser: Bool
    var edit: () -> Void

    func body(content: Content) -> some View {
        if isUser {
            content.accessibilityAction(named: "수정") { edit() }
        } else {
            content
        }
    }
}
