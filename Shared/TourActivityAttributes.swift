import ActivityKit
import Foundation

/// Shared between the main app and the Live Activity widget extension.
/// Keep this file dependency-free (no app-only types) so both targets can compile it.
struct TourActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentStopIndex: Int
        var totalStops: Int
        var currentStopName: String
        var currentStopCategoryIcon: String
        var nextStopName: String?
        var distanceToCurrentStopMeters: Double?
        var latitude: Double
        var longitude: Double
        var stopLatitudes: [Double]
        var stopLongitudes: [Double]
        var stopNames: [String]
        var startLatitude: Double
        var startLongitude: Double
        var isArrived: Bool

        var progressLabel: String {
            "Stop \(currentStopIndex + 1) of \(totalStops)"
        }
    }

    var tourName: String
    var routeShapeLabel: String
}
