import Foundation

/// Today-only changes to a running session: extra exercises and the order of exercise groups.
/// It never touches the schedule or the progression state — engines ignore sets whose slot is not in the day.
struct SessionPlan: Codable, Equatable {
    /// Exercises added for this session only. Their slot ids are fresh, so no schedule slot shares them.
    var extras: [ScheduleExercise] = []
    /// Group ids (`PrescribedSet.groupId`) in the order the user wants. Groups not listed keep their
    /// prescribed order after the listed ones.
    var order: [String] = []

    var isEmpty: Bool { extras.isEmpty && order.isEmpty }

    /// Rows of one today-only exercise. The weight was fixed when it was added (`seedKg`).
    static func rows(for ex: ScheduleExercise) -> [PrescribedSet] {
        (0..<max(1, ex.sets)).map { index in
            PrescribedSet(
                exerciseId: ex.id, exerciseName: ex.displayName, liftKey: ex.liftKey, setIndex: index,
                kg: ex.seedKg ?? 20, reps: ex.repMax, repMax: ex.repMax,
                isWorking: true, isWarmup: false, isAMRAP: false, isBBB: false, isOptional: true,
                repMin: ex.repMin
            )
        }
    }

    static func groupId(for ex: ScheduleExercise) -> String {
        rows(for: ex).first?.groupId ?? "\(ex.id)-main"
    }

    /// The session's rows: prescribed rows, then extras, arranged by `order`.
    func rows(prescribed: [PrescribedSet]) -> [PrescribedSet] {
        let all = prescribed + extras.flatMap(Self.rows(for:))
        guard !order.isEmpty else { return all }
        let groups = TodayController.grouped(all)
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return groups.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.first.flatMap { rank[$0.groupId] } ?? Int.max
                let r = rhs.element.first.flatMap { rank[$0.groupId] } ?? Int.max
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .flatMap(\.element)
    }

    func isExtra(slotId: String) -> Bool {
        extras.contains { $0.id == slotId }
    }

    /// Swaps the group at `index` with its neighbour (`offset` is -1 or 1) in the current group order.
    mutating func move(groupIds: [String], index: Int, by offset: Int) {
        let target = index + offset
        guard groupIds.indices.contains(index), groupIds.indices.contains(target) else { return }
        var ids = groupIds
        ids.swapAt(index, target)
        order = ids
    }

    /// Adds a today-only exercise at the end of the session.
    mutating func add(_ ex: ScheduleExercise) {
        extras.append(ex)
        if !order.isEmpty { order.append(Self.groupId(for: ex)) }
    }

    mutating func removeExtra(slotId: String) {
        guard let ex = extras.first(where: { $0.id == slotId }) else { return }
        let group = Self.groupId(for: ex)
        extras.removeAll { $0.id == slotId }
        order.removeAll { $0 == group }
    }

    /// Sets the number of sets of a today-only exercise (1...10).
    mutating func setExtraSets(slotId: String, sets: Int) {
        guard let index = extras.firstIndex(where: { $0.id == slotId }) else { return }
        extras[index].sets = min(10, max(1, sets))
    }

    // MARK: Draft upkeep

    /// Draft entries for `rows`, keeping what was already entered and dropping sets that no longer exist.
    static func syncedDraft(_ draft: [CompletedSet], rows: [PrescribedSet]) -> [CompletedSet] {
        rows.map { row in
            if let existing = draft.first(where: { $0.exerciseId == row.exerciseId && $0.setIndex == row.setIndex }) {
                return existing
            }
            return CompletedSet(
                exerciseId: row.exerciseId, setIndex: row.setIndex, kg: row.kg, reps: row.reps,
                isWorking: row.isWorking, isAMRAP: row.isAMRAP, isWarmup: row.isWarmup, isBBB: row.isBBB,
                completed: false
            )
        }
    }

    // MARK: Navigation

    /// The group to work on after `currentId`: the first one after it that still has open sets, wrapping around
    /// to earlier groups (an exercise skipped because the machine was taken comes back at the end).
    static func nextOpenGroup(groups: [[PrescribedSet]], currentId: String?,
                              isDone: (PrescribedSet) -> Bool) -> [PrescribedSet]? {
        guard !groups.isEmpty else { return nil }
        let current = groups.firstIndex { $0.first?.groupId == currentId } ?? -1
        let after = groups.indices.filter { $0 > current }
        let before = groups.indices.filter { $0 < current }
        for index in after + before where groups[index].contains(where: { !isDone($0) }) {
            return groups[index]
        }
        return nil
    }
}
