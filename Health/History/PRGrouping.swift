import Foundation

/// Lightweight PR input so grouping stays a pure function (no SwiftData).
struct PRInput: Equatable {
    let liftId: String
    let kg: Double
    let date: Date
}

struct PRRow: Equatable, Identifiable {
    let variantId: String
    let title: String
    let kg: Double
    let date: Date
    /// Index of the winning record in the input array (used to map a row back to its model for deletion).
    let sourceIndex: Int
    var id: String { variantId }
}

struct PRGroup: Equatable, Identifiable {
    /// Base exercise id (`other` for free-text records).
    let id: String
    let title: String
    let rows: [PRRow]
    var maxKg: Double { rows.first?.kg ?? 0 }
}

enum PRGrouping {
    static let otherTitle = "기타"

    /// Groups PRs by base exercise. One row per variant (its best PR). Rows sort by kg desc, groups by their best kg desc.
    /// `nicknames` maps user variant ids (including hidden ones) to their nickname.
    static func group(_ records: [PRInput],
                      nicknames: [String: String] = [:],
                      library: ExerciseLibrary = .shared) -> [PRGroup] {
        var best: [String: (index: Int, record: PRInput)] = [:]
        for (index, record) in records.enumerated() {
            if let current = best[record.liftId] {
                if record.kg > current.record.kg || (record.kg == current.record.kg && record.date > current.record.date) {
                    best[record.liftId] = (index, record)
                }
            } else {
                best[record.liftId] = (index, record)
            }
        }

        var rowsByBase: [String: [PRRow]] = [:]
        for (variantId, entry) in best {
            let row = PRRow(variantId: variantId,
                            title: rowTitle(variantId, nicknames: nicknames, library: library),
                            kg: entry.record.kg, date: entry.record.date, sourceIndex: entry.index)
            rowsByBase[ExerciseLibrary.baseId(ofVariant: variantId), default: []].append(row)
        }

        let groups = rowsByBase.map { baseId, rows -> PRGroup in
            let sorted = rows.sorted(by: rowOrder)
            return PRGroup(id: baseId, title: groupTitle(baseId, fallback: sorted.first?.title, library: library), rows: sorted)
        }
        return groups.sorted {
            if $0.maxKg != $1.maxKg { return $0.maxKg > $1.maxKg }
            return $0.id < $1.id
        }
    }

    static func rowTitle(_ variantId: String, nicknames: [String: String], library: ExerciseLibrary) -> String {
        // A user variant id is not a library variant, so check the nickname before the exercise-name fallback.
        if library.variant(id: variantId) == nil, let nickname = nicknames[variantId], !nickname.isEmpty { return nickname }
        if let name = library.displayName(variantId: variantId) { return name }
        if ExerciseLibrary.baseId(ofVariant: variantId) == ExerciseLibrary.otherId { return otherTitle }
        return variantId.isEmpty ? "운동" : variantId
    }

    private static func groupTitle(_ baseId: String, fallback: String?, library: ExerciseLibrary) -> String {
        if baseId == ExerciseLibrary.otherId { return otherTitle }
        if let name = library.info(for: baseId)?.name { return name }
        return fallback ?? (baseId.isEmpty ? "운동" : baseId)
    }

    private static func rowOrder(_ a: PRRow, _ b: PRRow) -> Bool {
        if a.kg != b.kg { return a.kg > b.kg }
        return a.variantId < b.variantId
    }
}
