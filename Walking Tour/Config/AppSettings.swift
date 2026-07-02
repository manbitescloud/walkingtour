import CoreLocation
import Foundation

enum AppSettingsKey {
    static let distanceUnit = "distanceUnit"
    static let routeShape = "routeShape"
    static let appearance = "appearance"
    static let recentLocations = "recentLocations"
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var distanceUnit: DistanceUnit {
        didSet { UserDefaults.standard.set(distanceUnit.rawValue, forKey: AppSettingsKey.distanceUnit) }
    }

    var routeShape: RouteShape {
        didSet { UserDefaults.standard.set(routeShape.rawValue, forKey: AppSettingsKey.routeShape) }
    }

    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: AppSettingsKey.appearance) }
    }

    private(set) var recentLocations: [RecentLocation] = [] {
        didSet { persistRecentLocations() }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: AppSettingsKey.distanceUnit),
           let unit = DistanceUnit(rawValue: raw) {
            distanceUnit = unit
        } else {
            distanceUnit = Locale.current.measurementSystem == .metric ? .metric : .imperial
        }

        if let raw = UserDefaults.standard.string(forKey: AppSettingsKey.routeShape),
           let shape = RouteShape(rawValue: raw) {
            routeShape = shape
        } else {
            routeShape = .loop
        }

        if let raw = UserDefaults.standard.string(forKey: AppSettingsKey.appearance),
           let saved = AppAppearance(rawValue: raw) {
            appearance = saved
        } else {
            appearance = .system
        }

        recentLocations = Self.loadRecentLocations()
    }

    func addRecentLocation(coordinate: CLLocationCoordinate2D, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "Selected Location" : trimmed
        let entry = RecentLocation(coordinate: coordinate, name: displayName)

        var updated = recentLocations.filter { !$0.isDuplicate(of: entry) }
        updated.insert(entry, at: 0)
        recentLocations = Array(updated.prefix(10))
    }

    private func persistRecentLocations() {
        guard let data = try? JSONEncoder().encode(recentLocations) else { return }
        UserDefaults.standard.set(data, forKey: AppSettingsKey.recentLocations)
    }

    private static func loadRecentLocations() -> [RecentLocation] {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsKey.recentLocations),
              let decoded = try? JSONDecoder().decode([RecentLocation].self, from: data) else {
            return []
        }
        return decoded
    }
}
