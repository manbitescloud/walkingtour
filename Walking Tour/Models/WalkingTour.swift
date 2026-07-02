import CoreLocation
import Foundation

struct WalkingTour: Identifiable {
    let id: UUID
    let preferences: TourPreferences
    let startLocation: CLLocationCoordinate2D
    var stops: [TourStop]
    var totalDistanceMeters: Double
    var estimatedDurationMinutes: Double

    init(
        id: UUID = UUID(),
        preferences: TourPreferences,
        startLocation: CLLocationCoordinate2D,
        stops: [TourStop],
        totalDistanceMeters: Double,
        estimatedDurationMinutes: Double
    ) {
        self.id = id
        self.preferences = preferences
        self.startLocation = startLocation
        self.stops = stops
        self.totalDistanceMeters = totalDistanceMeters
        self.estimatedDurationMinutes = estimatedDurationMinutes
    }

    func formattedDistance(unit: DistanceUnit) -> String {
        DistanceFormatter.format(totalDistanceMeters, unit: unit)
    }

    func formattedDuration() -> String {
        if estimatedDurationMinutes >= 60 {
            let hours = Int(estimatedDurationMinutes) / 60
            let minutes = Int(estimatedDurationMinutes) % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(Int(estimatedDurationMinutes)) min"
    }

    var shareText: String {
        var lines = [
            "\(preferences.themes.displayLabel) Walking Tour",
            "\(stops.count) stops · \(preferences.routeShape.label)",
            "",
        ]
        for (index, stop) in stops.enumerated() {
            lines.append("\(index + 1). \(stop.name)")
        }
        lines.append("")
        lines.append("Planned with Walking Tour")
        return lines.joined(separator: "\n")
    }
}
