import Foundation

enum RouteShape: String, CaseIterable, Identifiable, Codable {
    case loop
    case oneWay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loop: "Loop"
        case .oneWay: "One Way"
        }
    }

    var description: String {
        switch self {
        case .loop: "Returns to your starting point"
        case .oneWay: "Ends at the last stop"
        }
    }
}
