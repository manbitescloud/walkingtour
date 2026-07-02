import Foundation
import MapKit

extension Error {
    var friendlyTourPlanningMessage: String {
        let nsError = self as NSError
        if nsError.domain == MKErrorDomain,
           let code = MKError.Code(rawValue: UInt(nsError.code)) {
            switch code {
            case .placemarkNotFound:
                return "Apple Maps couldn't resolve a nearby place. Wait a moment and try again, or adjust your start location slightly."
            case .loadingThrottled:
                return "Apple Maps is busy right now. Wait a few seconds and try creating the tour again."
            case .directionsNotFound:
                return "Walking directions aren't available for part of this route. Try a shorter tour or a different start point."
            case .serverFailure:
                return "Apple Maps is temporarily unavailable. Try again in a moment."
            default:
                break
            }
        }

        return localizedDescription
    }
}
