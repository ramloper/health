import Foundation
import os

/// Read-only exercise library loaded from the bundled `Exercises/*.json` folder reference.
/// Pure value type: no SwiftData or UI dependencies.
struct ExerciseLibrary {
    static let otherId = "other"
    static let otherName = "기타 (직접 추가)"

    /// Loaded once; first access should happen at app start.
    static let shared = load()

    struct ExerciseInfo: Equatable {
        let name: String
        let group: MuscleGroup?
        let equipment: Equipment?
        let summary: String?
        let isOther: Bool
    }

    struct SearchHit: Equatable, Identifiable {
        let exercise: LibraryExercise
        /// Non-generic variants whose name, aliases or brand matched the query.
        let matchedVariants: [LibraryVariant]

        var id: String { exercise.id }
        var matchedVariantIds: [String] { matchedVariants.map(\.id) }
    }

    struct DroppedRow: Equatable {
        let file: String
        let id: String
        let reason: String
    }

    let version: Int
    /// Base exercises in JSON order.
    let exercises: [LibraryExercise]
    let brands: [LibraryBrand]
    /// Preset (branded) variants in JSON order. Generic variants are implicit — see `variant(id:)`.
    let variants: [LibraryVariant]
    let dropped: [DroppedRow]

    private let exerciseIndex: [String: Int]
    private let brandIndex: [String: LibraryBrand]
    private let variantIndex: [String: LibraryVariant]
    private let variantsByExercise: [String: [LibraryVariant]]
    private let exerciseHaystacks: [String]
    private let variantHaystacks: [String: String]

    private static let logger = Logger(subsystem: "com.wooram.health", category: "library")
    private static let haystackSeparator = "\n"

    // MARK: Loading

    static func load(bundle: Bundle = .main) -> ExerciseLibrary {
        let start = DispatchTime.now().uptimeNanoseconds
        func data(_ name: String) -> Data? {
            guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Exercises") else {
                logger.error("libraryFileMissing(\(name, privacy: .public))")
                return nil
            }
            return try? Data(contentsOf: url)
        }
        let library = decode(exercises: data("exercises"), brands: data("brands"), variants: data("variants"))
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        logger.info("libraryLoaded(ms: \(ms, format: .fixed(precision: 1), privacy: .public), exercises: \(library.exercises.count, privacy: .public), brands: \(library.brands.count, privacy: .public), variants: \(library.variants.count, privacy: .public), dropped: \(library.dropped.count, privacy: .public))")
        return library
    }

    /// Lossy decode: invalid rows are dropped and logged, never fatal. In DEBUG a drop also hits `assertionFailure`
    /// unless `assertOnDrop` is false (tests that inspect `dropped`).
    static func decode(exercises exercisesData: Data?, brands brandsData: Data?, variants variantsData: Data?,
                       assertOnDrop: Bool = true) -> ExerciseLibrary {
        var dropped: [DroppedRow] = []
        func drop(_ file: String, _ id: String?, _ reason: String) {
            let id = id ?? "?"
            dropped.append(DroppedRow(file: file, id: id, reason: reason))
            logger.error("libraryRowDropped(file: \(file, privacy: .public), id: \(id, privacy: .public), reason: \(reason, privacy: .public))")
        }

        let exerciseFile = exercisesData.flatMap { try? JSONDecoder().decode(RawFile<RawExercise>.self, from: $0) }
        if exercisesData != nil && exerciseFile == nil { drop("exercises", nil, "file undecodable") }
        var exercises: [LibraryExercise] = []
        var seenExercises = Set<String>()
        for row in exerciseFile?.rows ?? [] {
            guard let raw = row.value else { drop("exercises", nil, "row undecodable"); continue }
            switch raw.validated() {
            case .failure(let reason): drop("exercises", raw.id, reason.text)
            case .success(let ex):
                guard seenExercises.insert(ex.id).inserted else { drop("exercises", ex.id, "duplicate id"); continue }
                exercises.append(ex)
            }
        }

        let brandFile = brandsData.flatMap { try? JSONDecoder().decode(RawFile<RawBrand>.self, from: $0) }
        if brandsData != nil && brandFile == nil { drop("brands", nil, "file undecodable") }
        var brands: [LibraryBrand] = []
        var seenBrands = Set<String>()
        for row in brandFile?.rows ?? [] {
            guard let raw = row.value else { drop("brands", nil, "row undecodable"); continue }
            guard let id = raw.id.nonEmpty, let name = raw.name.nonEmpty, let english = raw.englishName.nonEmpty else {
                drop("brands", raw.id, "missing id/name/englishName"); continue
            }
            guard seenBrands.insert(id).inserted else { drop("brands", id, "duplicate id"); continue }
            brands.append(LibraryBrand(id: id, name: name, englishName: english))
        }

        let variantFile = variantsData.flatMap { try? JSONDecoder().decode(RawFile<RawVariant>.self, from: $0) }
        if variantsData != nil && variantFile == nil { drop("variants", nil, "file undecodable") }
        var variants: [LibraryVariant] = []
        var seenVariants = Set<String>()
        for row in variantFile?.rows ?? [] {
            guard let raw = row.value else { drop("variants", nil, "row undecodable"); continue }
            guard let id = raw.id.nonEmpty, let exerciseId = raw.exerciseId.nonEmpty,
                  let name = raw.name.nonEmpty, let aliases = raw.aliases else {
                drop("variants", raw.id, "missing id/exerciseId/name/aliases"); continue
            }
            // Generic variants are implicit (id == exerciseId); a JSON row for one is ignored.
            if id == exerciseId { continue }
            guard seenExercises.contains(exerciseId) else { drop("variants", id, "unknown exerciseId \(exerciseId)"); continue }
            guard let brandId = raw.brandId.nonEmpty, seenBrands.contains(brandId) else {
                drop("variants", id, "unknown brandId \(raw.brandId ?? "nil")"); continue
            }
            guard baseId(ofVariant: id) == exerciseId else { drop("variants", id, "id prefix is not exerciseId/"); continue }
            guard seenVariants.insert(id).inserted else { drop("variants", id, "duplicate id"); continue }
            variants.append(LibraryVariant(id: id, exerciseId: exerciseId, brandId: brandId, name: name, aliases: aliases))
        }

        #if DEBUG
        if assertOnDrop && !dropped.isEmpty {
            assertionFailure("ExerciseLibrary dropped \(dropped.count) row(s): \(dropped.map { "\($0.file)/\($0.id): \($0.reason)" })")
        }
        #endif

        return ExerciseLibrary(version: exerciseFile?.version ?? 0, exercises: exercises, brands: brands,
                               variants: variants, dropped: dropped)
    }

    init(version: Int, exercises: [LibraryExercise], brands: [LibraryBrand], variants: [LibraryVariant],
         dropped: [DroppedRow] = []) {
        self.version = version
        self.exercises = exercises
        self.brands = brands
        self.variants = variants
        self.dropped = dropped

        var exerciseIndex: [String: Int] = [:]
        var variantIndex: [String: LibraryVariant] = [:]
        for (i, ex) in exercises.enumerated() {
            exerciseIndex[ex.id] = i
            variantIndex[ex.id] = LibraryVariant(id: ex.id, exerciseId: ex.id, brandId: nil, name: ex.name, aliases: ex.aliases)
        }
        let brandIndex = Dictionary(brands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byExercise: [String: [LibraryVariant]] = [:]
        var variantHaystacks: [String: String] = [:]
        for v in variants {
            variantIndex[v.id] = v
            byExercise[v.exerciseId, default: []].append(v)
            let brand = v.brandId.flatMap { brandIndex[$0] }
            variantHaystacks[v.id] = Self.haystack([v.name] + v.aliases + [brand?.name, brand?.englishName].compactMap { $0 })
        }
        self.exerciseIndex = exerciseIndex
        self.brandIndex = brandIndex
        self.variantIndex = variantIndex
        self.variantsByExercise = byExercise
        self.exerciseHaystacks = exercises.map { Self.haystack([$0.name] + $0.aliases) }
        self.variantHaystacks = variantHaystacks
    }

    private static func haystack(_ terms: [String]) -> String {
        terms.map(SearchNormalizer.normalize).joined(separator: haystackSeparator)
    }

    // MARK: Lookup

    func exercise(id: String) -> LibraryExercise? {
        exerciseIndex[id].map { exercises[$0] }
    }

    /// Includes the implicit generic variant (`id == exerciseId`) for every exercise.
    func variant(id: String) -> LibraryVariant? {
        variantIndex[id]
    }

    /// Preset (branded) variants of an exercise in JSON order; excludes the generic variant.
    func variants(ofExercise exerciseId: String) -> [LibraryVariant] {
        variantsByExercise[exerciseId] ?? []
    }

    func brand(id: String) -> LibraryBrand? {
        brandIndex[id]
    }

    /// `bench` → `bench`, `chest-press-machine/hammer-iso` → `chest-press-machine`, `other/u-1` → `other`.
    static func baseId(ofVariant variantId: String) -> String {
        guard let slash = variantId.firstIndex(of: "/") else { return variantId }
        return String(variantId[..<slash])
    }

    /// Generic → exercise name; preset → "브랜드명 변형명"; unknown variant of a known exercise → exercise name;
    /// otherwise nil (user variants are resolved by the caller from `UserVariant`/stored name).
    func displayName(variantId: String) -> String? {
        if let v = variant(id: variantId) {
            if v.isGeneric { return exercise(id: v.exerciseId)?.name ?? v.name }
            if let brand = v.brandId.flatMap(brand(id:)) { return "\(brand.name) \(v.name)" }
            return v.name
        }
        return exercise(id: Self.baseId(ofVariant: variantId))?.name
    }

    /// The single entry point that handles both JSON exercises and the special `other` id.
    func info(for exerciseId: String) -> ExerciseInfo? {
        if exerciseId == Self.otherId {
            return ExerciseInfo(name: Self.otherName, group: nil, equipment: nil, summary: nil, isOther: true)
        }
        guard let ex = exercise(id: exerciseId) else { return nil }
        return ExerciseInfo(name: ex.name, group: ex.group, equipment: ex.equipment,
                            summary: ex.summary.isEmpty ? nil : ex.summary, isOther: false)
    }

    // MARK: Search

    /// Matches names, aliases, variant names/aliases and brand names. A variant match surfaces its base exercise
    /// with the matched variants attached. Empty query returns every filtered exercise. Results keep JSON order.
    func search(_ query: String, group: MuscleGroup? = nil, equipment: Equipment? = nil) -> [SearchHit] {
        let q = SearchNormalizer.normalize(query)
        var hits: [SearchHit] = []
        for (i, ex) in exercises.enumerated() {
            if let group, ex.group != group { continue }
            if let equipment, ex.equipment != equipment { continue }
            if q.isEmpty {
                hits.append(SearchHit(exercise: ex, matchedVariants: []))
                continue
            }
            let matched = variants(ofExercise: ex.id).filter { variantHaystacks[$0.id]?.contains(q) == true }
            if !matched.isEmpty || exerciseHaystacks[i].contains(q) {
                hits.append(SearchHit(exercise: ex, matchedVariants: matched))
            }
        }
        return hits
    }
}

// MARK: - Raw (lossy) decoding

private struct RawFile<Row: Decodable>: Decodable {
    let version: Int?
    let rows: [LossyRow<Row>]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        version = try? c.decodeIfPresent(Int.self, forKey: Key(stringValue: "version"))
        let listKey = ["exercises", "brands", "variants"].map(Key.init(stringValue:)).first(where: c.contains)
        rows = listKey.flatMap { try? c.decode([LossyRow<Row>].self, forKey: $0) } ?? []
    }
}

private struct LossyRow<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct DropReason: Error { let text: String }

private struct RawExercise: Decodable {
    let id: String?
    let name: String?
    let aliases: [String]?
    let group: String?
    let equipment: String?
    let plane: String?
    let isCompound: Bool?
    let summary: String?

    func validated() -> Result<LibraryExercise, DropReason> {
        guard let id = id.nonEmpty else { return .failure(DropReason(text: "missing id")) }
        guard id != ExerciseLibrary.otherId, !id.contains("/") else { return .failure(DropReason(text: "reserved or invalid id")) }
        guard let name = name.nonEmpty else { return .failure(DropReason(text: "missing name")) }
        guard let isCompound else { return .failure(DropReason(text: "missing isCompound")) }
        guard let group = group.flatMap(MuscleGroup.init(rawValue:)) else { return .failure(DropReason(text: "unknown group \(group ?? "nil")")) }
        guard let equipment = equipment.flatMap(Equipment.init(rawValue:)) else {
            return .failure(DropReason(text: "unknown equipment \(equipment ?? "nil")"))
        }
        guard let plane, plane == "upper" || plane == "lower" else { return .failure(DropReason(text: "unknown plane \(plane ?? "nil")")) }
        // Text-only gaps (aliases, summary) keep the row so records never orphan; LibraryTests lint them.
        return .success(LibraryExercise(id: id, name: name, aliases: aliases ?? [], group: group, equipment: equipment,
                                        plane: plane, isCompound: isCompound, summary: summary.nonEmpty ?? ""))
    }
}

private struct RawBrand: Decodable {
    let id: String?
    let name: String?
    let englishName: String?
}

private struct RawVariant: Decodable {
    let id: String?
    let exerciseId: String?
    let brandId: String?
    let name: String?
    let aliases: [String]?
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
