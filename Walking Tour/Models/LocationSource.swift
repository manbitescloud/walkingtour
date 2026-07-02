import CoreLocation
import Foundation

enum LocationSource: String, CaseIterable, Identifiable, Codable {
    case current
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .current: "Current Location"
        case .manual: "Pick on Map"
        }
    }

    var icon: String {
        switch self {
        case .current: "location.fill"
        case .manual: "mappin.and.ellipse"
        }
    }
}
