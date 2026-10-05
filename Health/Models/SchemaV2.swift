import SwiftData

/// 1.1 store schema. Start of the migration chain for later versions; the 1.0 store is not migrated
/// (see `StoreBootstrap`), the file name `soejil-v2.store` is the real version signal.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static let models: [any PersistentModel.Type] = [
        AthleteProfile.self,
        TrainingCycle.self,
        WorkoutSession.self,
        SetLog.self,
        PersonalRecord.self,
        CustomRoutine.self,
        UserVariant.self
    ]
}
