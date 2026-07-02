import CoreLocation
import Foundation

struct RecentLocation: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let name: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(coordinate: CLLocationCoordinate2D, name: String) {
        id = UUID()
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.name = name
    }

    func isDuplicate(of other: RecentLocation, proximityMeters: CLLocationDistance = 100) -> Bool {
        if name.caseInsensitiveCompare(other.name) == .orderedSame {
            return true
        }
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return here.distance(from: there) < proximityMeters
    }
}
