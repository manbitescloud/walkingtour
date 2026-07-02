import ActivityKit
import CoreLocation
import Foundation

/// Drives the Live Activity (Dynamic Island / Lock Screen) shown while a tour is being navigated.
/// The activity mirrors whichever stop is currently active in-app; iOS doesn't allow arbitrary
/// swipe gestures inside Live Activity content, so "swiping through stops" happens in the app
/// (or via the arrival/advance flow) and is reflected live in the widget.
@MainActor
final class TourLiveActivityManager {
    private var activity: Activity<TourActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(tour: WalkingTour, currentStopIndex: Int) {
        guard isSupported else { return }
        end()

        let attributes = TourActivityAttributes(
            tourName: "\(tour.preferences.themes.displayLabel) Walking Tour",
            routeShapeLabel: tour.preferences.routeShape.label
        )
        let state = contentState(for: tour, currentStopIndex: currentStopIndex, distanceToCurrentStop: nil)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(tour: WalkingTour, currentStopIndex: Int, distanceToCurrentStop: Double?) {
        guard let activity else { return }
        let state = contentState(
            for: tour,
            currentStopIndex: currentStopIndex,
            distanceToCurrentStop: distanceToCurrentStop
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        let finalState = activity.content.state
        Task {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private func contentState(
        for tour: WalkingTour,
        currentStopIndex: Int,
        distanceToCurrentStop: Double?
    ) -> TourActivityAttributes.ContentState {
        let stops = tour.stops
        let clampedIndex = stops.isEmpty ? 0 : min(max(0, currentStopIndex), stops.count - 1)
        let current = stops.indices.contains(clampedIndex) ? stops[clampedIndex] : nil
        let next = stops.indices.contains(clampedIndex + 1) ? stops[clampedIndex + 1] : nil
        let previewStops = Array(stops.prefix(15))

        return TourActivityAttributes.ContentState(
            currentStopIndex: clampedIndex,
            totalStops: stops.count,
            currentStopName: current?.name ?? tour.preferences.startLocationName,
            currentStopCategoryIcon: current?.category.icon ?? "figure.walk",
            nextStopName: next?.name,
            distanceToCurrentStopMeters: distanceToCurrentStop,
            latitude: current?.latitude ?? tour.startLocation.latitude,
            longitude: current?.longitude ?? tour.startLocation.longitude,
            stopLatitudes: previewStops.map(\.latitude),
            stopLongitudes: previewStops.map(\.longitude),
            stopNames: previewStops.map(\.name),
            startLatitude: tour.startLocation.latitude,
            startLongitude: tour.startLocation.longitude,
            isArrived: (distanceToCurrentStop ?? .greatestFiniteMagnitude) <= NavigationManager.arrivalThresholdMeters
        )
    }
}
