import Foundation

enum TourLengthMode: String, CaseIterable, Identifiable, Codable {
    case distance
    case time

    var id: String { rawValue }

    var label: String {
        switch self {
        case .distance: "Distance"
        case .time: "Time"
        }
    }
}

struct TourPreferences: Codable, Equatable {
    var lengthMode: TourLengthMode = .distance
    var distanceMeters: Double = 3_000
    var durationMinutes: Double = 45
    var routeShape: RouteShape = .loop
    var themes: [TourTheme] = [.highlights]
    var includeFoodStops: Bool = true
    var includeCoffeeStops: Bool = true
    var startLocationSource: LocationSource = .current
    var startLocationName: String = ""

    /// Average walking speed used to convert time ↔ distance (~5 km/h).
    static let walkingSpeedMetersPerMinute: Double = 83
    static let minDurationMinutes: Double = 15
    static let maxDurationMinutes: Double = 480

    var targetDistanceMeters: Double {
        switch lengthMode {
        case .distance:
            distanceMeters
        case .time:
            durationMinutes * Self.walkingSpeedMetersPerMinute
        }
    }

    var estimatedDurationMinutes: Double {
        switch lengthMode {
        case .distance:
            distanceMeters / Self.walkingSpeedMetersPerMinute
        case .time:
            durationMinutes
        }
    }

    var searchRadiusMeters: Int {
        let divisor = routeShape == .loop ? 2.0 : 1.5
        return min(Int(targetDistanceMeters / divisor), 5_000)
    }

    mutating func applyThemeDefaults() {
        if themes.contains(.foodie) {
            includeFoodStops = true
            includeCoffeeStops = true
        }
    }

    mutating func toggleTheme(_ theme: TourTheme) {
        if let index = themes.firstIndex(of: theme) {
            themes.remove(at: index)
            if themes.isEmpty {
                themes = [.highlights]
            }
        } else {
            if theme == .highlights {
                themes = [.highlights]
            } else {
                themes.removeAll { $0 == .highlights }
                themes.append(theme)
            }
        }
    }

    func isThemeSelected(_ theme: TourTheme) -> Bool {
        themes.contains(theme)
    }

    enum CodingKeys: String, CodingKey {
        case lengthMode, distanceMeters, durationMinutes, routeShape
        case themes, theme
        case includeFoodStops, includeCoffeeStops
        case startLocationSource, startLocationName
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lengthMode = try container.decodeIfPresent(TourLengthMode.self, forKey: .lengthMode) ?? .distance
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 3_000
        durationMinutes = try container.decodeIfPresent(Double.self, forKey: .durationMinutes) ?? 45
        routeShape = try container.decodeIfPresent(RouteShape.self, forKey: .routeShape) ?? .loop
        includeFoodStops = try container.decodeIfPresent(Bool.self, forKey: .includeFoodStops) ?? true
        includeCoffeeStops = try container.decodeIfPresent(Bool.self, forKey: .includeCoffeeStops) ?? true
        startLocationSource = try container.decodeIfPresent(LocationSource.self, forKey: .startLocationSource) ?? .current
        startLocationName = try container.decodeIfPresent(String.self, forKey: .startLocationName) ?? ""

        if let decodedThemes = try container.decodeIfPresent([TourTheme].self, forKey: .themes), !decodedThemes.isEmpty {
            themes = decodedThemes
        } else if let singleTheme = try container.decodeIfPresent(TourTheme.self, forKey: .theme) {
            themes = [singleTheme]
        } else {
            themes = [.highlights]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lengthMode, forKey: .lengthMode)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(routeShape, forKey: .routeShape)
        try container.encode(themes, forKey: .themes)
        try container.encode(includeFoodStops, forKey: .includeFoodStops)
        try container.encode(includeCoffeeStops, forKey: .includeCoffeeStops)
        try container.encode(startLocationSource, forKey: .startLocationSource)
        try container.encode(startLocationName, forKey: .startLocationName)
    }
}
