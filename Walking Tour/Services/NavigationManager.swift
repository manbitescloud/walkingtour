import CoreLocation
import Foundation

enum NavigationStatus: Equatable {
    case idle
    case navigating
    case arrived
    case completed
}

@MainActor
@Observable
final class NavigationManager {
    static let arrivalThresholdMeters: Double = 45

    private(set) var isActive = false
    private(set) var currentStopIndex = 0
    private(set) var distanceToCurrentStop: Double?
    private(set) var status: NavigationStatus = .idle

    var currentStop: TourStop? {
        guard let tour, currentStopIndex < tour.stops.count else { return nil }
        return tour.stops[currentStopIndex]
    }

    private var tour: WalkingTour?

    func start(tour: WalkingTour) {
        self.tour = tour
        currentStopIndex = 0
        isActive = true
        status = .navigating
        distanceToCurrentStop = nil
    }

    func stop() {
        isActive = false
        status = .idle
        tour = nil
        currentStopIndex = 0
        distanceToCurrentStop = nil
    }

    func update(location: CLLocation) {
        guard isActive, let stop = currentStop else { return }

        let distance = location.distance(from: stop.location)
        distanceToCurrentStop = distance

        if distance <= Self.arrivalThresholdMeters {
            status = .arrived
        } else {
            status = .navigating
        }
    }

    func advanceToNextStop() {
        guard let tour else { return }

        if currentStopIndex + 1 < tour.stops.count {
            currentStopIndex += 1
            status = .navigating
            distanceToCurrentStop = nil
        } else if tour.preferences.routeShape == .loop {
            status = .completed
            isActive = false
        } else {
            status = .completed
            isActive = false
        }
    }

    func goToStop(index: Int) {
        guard let tour, tour.stops.indices.contains(index) else { return }
        currentStopIndex = index
        status = .navigating
        distanceToCurrentStop = nil
    }

    var progressLabel: String {
        guard let tour else { return "" }
        if status == .completed {
            return tour.preferences.routeShape == .loop ? "Back at start — tour complete!" : "Tour complete!"
        }
        return "Stop \(currentStopIndex + 1) of \(tour.stops.count)"
    }
}
