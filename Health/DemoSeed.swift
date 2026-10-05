#if DEBUG
import Foundation
import SwiftData

/// Sample data for App Store screenshots (`--demo` launch argument). Never runs in release builds.
enum DemoSeed {
    @MainActor
    static func seed(_ context: ModelContext) {
        let profile = AthleteProfile(bench1RM: 90, squat1RM: 130, dead1RM: 160, ohp1RM: 60, hasCompletedOnboarding: true)
        profile.gymBrandIds = ["hammer", "technogym"] // 09-picker: "내 헬스장" section
        context.insert(profile)
        guard let schedule = ProgramCatalog.load(Hypertrophy6DayEngine.id) else { return }
        let cycle = SessionService.startCycle(context: context, schedule: schedule, profile: profile.inputs)

        let calendar = Calendar.current
        let sessionCount = 12 // two full weeks, so the demo lands on 가슴A
        for i in 0..<sessionCount {
            let rows = SessionService.prescribe(cycle: cycle, schedule: schedule, profile: profile.inputs)
            var logged = TodayController.loggedMatchingPrescribe(rows)
            // Miss the top reps on a couple of isolation lifts now and then so weights look lived-in.
            for j in logged.indices where (i + j) % 7 == 0 && !logged[j].exerciseId.contains("bench") {
                logged[j].reps = max(1, logged[j].reps - 2)
            }
            let session = SessionService.complete(context: context, cycle: cycle, schedule: schedule, profile: profile.inputs, rows: rows, logged: logged)
            let daysAgo = (sessionCount - i) * 2 - 1
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now).map {
                calendar.date(bySettingHour: 19, minute: 10 + i, second: 0, of: $0) ?? $0
            } ?? .now
            session.date = date
            for set in session.sets { set.date = date }
        }
        for pr in (try? context.fetch(FetchDescriptor<PersonalRecord>())) ?? [] {
            pr.date = calendar.date(byAdding: .day, value: -3, to: .now) ?? .now
        }

        var custom = ProgramSchedule.makeCustom(name: "집 헬스 3일")
        custom.days = [
            ProgramDay(id: "h1", name: "밀기", isRest: false, exercises: [
                .makeCustom(exerciseId: "bench", sets: 4, reps: 8, seedKg: 60),
                .makeCustom(exerciseId: "db-lateral-raise", sets: 3, reps: 15, seedKg: 8),
                .makeCustom(exerciseId: "cable-pushdown", sets: 3, reps: 12, seedKg: 20)
            ]),
            ProgramDay(id: "h2", name: "당기기", isRest: false, exercises: [
                .makeCustom(exerciseId: "bent-over-row", sets: 4, reps: 8, seedKg: 50),
                .makeCustom(exerciseId: "cable-lat-pulldown", sets: 3, reps: 10, seedKg: 45),
                .makeCustom(exerciseId: "db-hammer-curl", sets: 3, reps: 12, seedKg: 12)
            ]),
            ProgramDay(id: "h3", name: "하체", isRest: false, exercises: [
                .makeCustom(exerciseId: "squat", sets: 4, reps: 6, seedKg: 90),
                .makeCustom(exerciseId: "romanian-deadlift", sets: 3, reps: 10, seedKg: 70),
                .makeCustom(exerciseId: "machine-standing-calf-raise", sets: 4, reps: 15, seedKg: 40)
            ])
        ]
        _ = SessionService.persistCustom(context: context, existing: nil, schedule: custom, cycle: nil)
        try? context.save()
    }
}
#endif
