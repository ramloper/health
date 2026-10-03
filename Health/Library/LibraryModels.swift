import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Hashable {
    case chest, back, legs, shoulders, arms, core, fullbody

    var label: String {
        switch self {
        case .chest: return "가슴"
        case .back: return "등"
        case .legs: return "하체"
        case .shoulders: return "어깨"
        case .arms: return "팔"
        case .core: return "코어"
        case .fullbody: return "전신"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Hashable {
    case barbell, dumbbell, cable, smith, machine, bodyweight, kettlebell, band

    var label: String {
        switch self {
        case .barbell: return "바벨"
        case .dumbbell: return "덤벨"
        case .cable: return "케이블"
        case .smith: return "스미스"
        case .machine: return "머신"
        case .bodyweight: return "맨몸"
        case .kettlebell: return "케틀벨"
        case .band: return "밴드"
        }
    }
}

/// A base exercise from `Exercises/exercises.json`. `other` is never a row here — see `ExerciseLibrary.info(for:)`.
struct LibraryExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let aliases: [String]
    let group: MuscleGroup
    let equipment: Equipment
    let plane: String
    let isCompound: Bool
    let summary: String
}

/// A brand/model of a base exercise. The generic variant (no brand) has `id == exerciseId`.
struct LibraryVariant: Codable, Identifiable, Hashable {
    let id: String
    let exerciseId: String
    let brandId: String?
    let name: String
    let aliases: [String]

    var isGeneric: Bool { id == exerciseId }
}

struct LibraryBrand: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let englishName: String
}
