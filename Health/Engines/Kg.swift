import Foundation

enum Kg {
    static let plate: Double = 2.5

    /// Nearest 2.5 kg, ties toward 0 (half-down on the 2.5 grid).
    /// 33.75 → 32.5; 57.375 → 57.5.
    static func nearest(_ value: Double) -> Double {
        let units = value / plate
        let floored = units.rounded(.towardZero)
        let frac = abs(units) - abs(floored)
        let magnitude: Double
        if frac > 0.5 {
            magnitude = abs(floored) + 1
        } else {
            magnitude = abs(floored)
        }
        return (value < 0 ? -magnitude : magnitude) * plate
    }

    static func roundDown(_ value: Double) -> Double {
        floor(value / plate) * plate
    }

    static func trainingMax(fromOneRM oneRM: Double) -> Double {
        roundDown(oneRM * 0.9)
    }

    static func percent(_ tm: Double, _ pct: Double) -> Double {
        nearest(tm * pct)
    }
}
