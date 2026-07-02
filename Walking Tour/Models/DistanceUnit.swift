import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable, Codable {
    case metric
    case imperial

    var id: String { rawValue }

    var label: String {
        switch self {
        case .metric: "Kilometers"
        case .imperial: "Miles"
        }
    }

    var shortLabel: String {
        switch self {
        case .metric: "km"
        case .imperial: "mi"
        }
    }
}

enum DistanceFormatter {
    static func format(_ meters: Double, unit: DistanceUnit, suffix: String? = nil) -> String {
        let base: String
        switch unit {
        case .metric:
            if meters >= 1_000 {
                base = String(format: "%.1f km", meters / 1_000)
            } else {
                base = String(format: "%.0f m", meters)
            }
        case .imperial:
            let miles = meters / 1_609.344
            if miles >= 0.1 {
                base = String(format: "%.1f mi", miles)
            } else {
                let feet = meters * 3.28084
                base = String(format: "%.0f ft", feet)
            }
        }
        guard let suffix else { return base }
        return "\(base) \(suffix)"
    }

    static func sliderRange(unit: DistanceUnit) -> ClosedRange<Double> {
        switch unit {
        case .metric: 500...10_000
        case .imperial: 804.672...16_093.44 // ~0.5 mi to ~10 mi
        }
    }

    static func sliderStep(unit: DistanceUnit) -> Double {
        switch unit {
        case .metric: 250
        case .imperial: 402.336 // ~0.25 mi
        }
    }

    static func displayValue(_ meters: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .metric:
            if meters >= 1_000 {
                return String(format: "%.1f km", meters / 1_000)
            }
            return String(format: "%.0f m", meters)
        case .imperial:
            return String(format: "%.1f mi", meters / 1_609.344)
        }
    }
}
