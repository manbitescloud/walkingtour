import CoreLocation
import Foundation

struct SavedTour: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    let preferences: TourPreferences
    let startLatitude: Double
    let startLongitude: Double
    var stops: [TourStop]
    let totalDistanceMeters: Double
    let estimatedDurationMinutes: Double

    var startLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    init(from tour: WalkingTour, name: String) {
        id = tour.id
        self.name = name
        createdAt = Date()
        preferences = tour.preferences
        startLatitude = tour.startLocation.latitude
        startLongitude = tour.startLocation.longitude
        stops = tour.stops
        totalDistanceMeters = tour.totalDistanceMeters
        estimatedDurationMinutes = tour.estimatedDurationMinutes
    }

    func asWalkingTour() -> WalkingTour {
        WalkingTour(
            id: id,
            preferences: preferences,
            startLocation: startLocation,
            stops: stops,
            totalDistanceMeters: totalDistanceMeters,
            estimatedDurationMinutes: estimatedDurationMinutes
        )
    }
}
