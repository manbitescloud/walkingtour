import CoreLocation
import Foundation
import MapKit

enum TourGenerationState: Equatable {
    case idle
    case loading
    case success
    case failure(String)
}

@MainActor
@Observable
final class TourViewModel {
    var preferences = TourPreferences()
    var tour: WalkingTour?
    var routePolyline: MKPolyline?
    var selectedStop: TourStop?
    var state: TourGenerationState = .idle
    var savedTours: [SavedTour] = []
    var showSaveSheet = false
    var saveTourName = ""
    private(set) var networkRevision = 0
    var locationSource: LocationSource = .current
    var manualLocation: CLLocationCoordinate2D?
    var manualLocationName = "Custom Location"
    var directionsStop: TourStop?
    var wikipediaStop: TourStop?
    var showAddStopSheet = false
    var addStopCandidates: [TourStop] = []
    var isLoadingAddStopCandidates = false
    var isUpdatingStops = false

    let locationService = LocationService()
    let navigationManager = NavigationManager()
    let liveActivityManager = TourLiveActivityManager()

    private let tourPlanner = TourPlanner()
    private let directionsService = DirectionsService()
    private let storageService = TourStorageService()
    private var generationToken = UUID()

    var isOffline: Bool {
        _ = networkRevision
        return !NetworkMonitor.shared.isConnected
    }

    var canGenerateTour: Bool {
        guard !isOffline else { return false }
        switch locationSource {
        case .current:
            return locationService.currentLocation != nil &&
                (locationService.authorizationStatus == .authorizedWhenInUse ||
                 locationService.authorizationStatus == .authorizedAlways)
        case .manual:
            return manualLocation != nil
        }
    }

    var tourOriginCoordinate: CLLocationCoordinate2D? {
        switch locationSource {
        case .current:
            locationService.currentLocation?.coordinate
        case .manual:
            manualLocation
        }
    }

    init() {
        NetworkMonitor.shared.onStatusChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.networkRevision += 1
            }
        }
    }

    func onAppear() {
        locationService.requestPermission()
        locationService.startUpdating()
        reloadSavedTours()
        networkRevision += 1
    }

    func reloadSavedTours() {
        savedTours = storageService.loadSavedTours().filter { $0.name != "Last Tour" }
    }

    func generateTour() async {
        guard !isOffline else {
            state = .failure("You're offline. Open a saved tour or connect to the internet to plan a new one.")
            return
        }

        guard let location = tourOriginCoordinate else {
            state = .failure(locationSource == .manual
                ? "Pick a starting location on the map."
                : "Location unavailable. Enable location services and try again.")
            return
        }

        let token = UUID()
        generationToken = token

        state = .loading
        tour = nil
        routePolyline = nil
        selectedStop = nil
        navigationManager.stop()

        do {
            var prefs = preferences
            prefs.routeShape = AppSettings.shared.routeShape
            prefs.startLocationSource = locationSource
            prefs.startLocationName = locationSource == .manual
                ? manualLocationName
                : "Current Location"
            prefs.applyThemeDefaults()

            let generated = try await tourPlanner.generateTour(
                from: location,
                preferences: prefs
            )

            guard generationToken == token else { return }

            guard !generated.stops.isEmpty else {
                state = .failure("No stops found nearby. Try a different theme or starting location.")
                return
            }

            preferences = prefs

            var finalTour = generated
            let routeResult = await directionsService.walkingRoute(
                through: finalTour.stops,
                start: finalTour.startLocation,
                isLoop: finalTour.preferences.routeShape == .loop
            )

            guard generationToken == token else { return }

            applyRouteResult(routeResult, to: &finalTour)

            tour = finalTour
            routePolyline = routeResult.polyline
            try? storageService.cacheLatestTour(finalTour)
            state = .success
        } catch {
            guard generationToken == token else { return }
            tour = nil
            routePolyline = nil
            state = .failure(error.friendlyTourPlanningMessage)
        }
    }

    func loadSavedTour(_ saved: SavedTour) async {
        state = .loading
        navigationManager.stop()
        selectedStop = nil

        let loaded = saved.asWalkingTour()
        tour = loaded

        let routeResult = await directionsService.walkingRoute(
            through: loaded.stops,
            start: loaded.startLocation,
            isLoop: loaded.preferences.routeShape == .loop
        )
        routePolyline = routeResult.polyline
        state = .success
    }

    private func applyRouteResult(_ result: WalkingRouteResult, to tour: inout WalkingTour) {
        let dwellMinutes = tour.stops.reduce(0.0) { $0 + $1.category.dwellMinutes }

        if result.distanceMeters > 0 {
            tour.totalDistanceMeters = result.distanceMeters
        }
        tour.estimatedDurationMinutes = (result.travelTimeMinutes > 0
            ? result.travelTimeMinutes
            : tour.totalDistanceMeters / TourPreferences.walkingSpeedMetersPerMinute) + dwellMinutes
    }

    private func recalculateRoute(for tour: inout WalkingTour) async {
        var previous = tour.startLocation
        for index in tour.stops.indices {
            tour.stops[index].distanceFromPrevious = directionsService.straightLineDistance(
                from: previous,
                to: tour.stops[index].coordinate
            )
            previous = tour.stops[index].coordinate
        }

        let routeResult = await directionsService.walkingRoute(
            through: tour.stops,
            start: tour.startLocation,
            isLoop: tour.preferences.routeShape == .loop
        )
        applyRouteResult(routeResult, to: &tour)
        routePolyline = routeResult.polyline
    }

    func removeStop(_ stop: TourStop) async {
        guard var updatedTour = tour,
              updatedTour.stops.count > 1,
              let index = updatedTour.stops.firstIndex(where: { $0.id == stop.id }) else { return }

        isUpdatingStops = true
        defer { isUpdatingStops = false }

        updatedTour.stops.remove(at: index)
        await recalculateRoute(for: &updatedTour)
        tour = updatedTour
        try? storageService.cacheLatestTour(updatedTour)

        if selectedStop?.id == stop.id {
            let newIndex = min(index, updatedTour.stops.count - 1)
            selectedStop = updatedTour.stops.indices.contains(newIndex) ? updatedTour.stops[newIndex] : nil
        }

        if navigationManager.isActive {
            navigationManager.stop()
        }
    }

    func presentAddStopOptions() {
        showAddStopSheet = true
        Task { await loadAddStopCandidates() }
    }

    func loadAddStopCandidates() async {
        guard let tour else { return }
        isLoadingAddStopCandidates = true
        defer { isLoadingAddStopCandidates = false }

        let center = tour.stops.last?.coordinate ?? tour.startLocation
        let existingNames = Set(tour.stops.map { $0.name.lowercased() })
        addStopCandidates = await tourPlanner.findAdditionalStops(
            near: center,
            excluding: existingNames,
            themes: tour.preferences.themes
        )
    }

    func addStop(_ candidate: TourStop) async {
        guard var updatedTour = tour else { return }

        isUpdatingStops = true
        defer { isUpdatingStops = false }

        var newStop = candidate
        newStop.distanceFromPrevious = nil
        updatedTour.stops.append(newStop)
        await recalculateRoute(for: &updatedTour)
        tour = updatedTour
        try? storageService.cacheLatestTour(updatedTour)

        showAddStopSheet = false
        addStopCandidates = []
    }

    func saveCurrentTour() {
        guard let tour else { return }
        let name = saveTourName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let saved = SavedTour(from: tour, name: name)
        try? storageService.saveTour(saved)
        reloadSavedTours()
        saveTourName = ""
        showSaveSheet = false
    }

    func deleteSavedTour(_ saved: SavedTour) {
        try? storageService.deleteTour(id: saved.id)
        reloadSavedTours()
    }

    func startNavigation() {
        guard let tour else { return }
        navigationManager.start(tour: tour)
        if let stop = navigationManager.currentStop {
            selectedStop = stop
        }
        liveActivityManager.start(tour: tour, currentStopIndex: navigationManager.currentStopIndex)
    }

    func stopNavigation() {
        navigationManager.stop()
        liveActivityManager.end()
    }

    func handleLocationUpdate() {
        guard navigationManager.isActive,
              let location = locationService.currentLocation else { return }
        navigationManager.update(location: location)

        if navigationManager.status == .arrived,
           let stop = navigationManager.currentStop {
            selectedStop = stop
        }

        if let tour {
            liveActivityManager.update(
                tour: tour,
                currentStopIndex: navigationManager.currentStopIndex,
                distanceToCurrentStop: navigationManager.distanceToCurrentStop
            )
        }

        if navigationManager.status == .completed {
            liveActivityManager.end()
        }
    }

    func jumpToStop(index: Int) {
        navigationManager.goToStop(index: index)
        if let tour, navigationManager.isActive {
            liveActivityManager.update(
                tour: tour,
                currentStopIndex: navigationManager.currentStopIndex,
                distanceToCurrentStop: navigationManager.distanceToCurrentStop
            )
        }
    }

    func confirmArrivalAndAdvance() {
        navigationManager.advanceToNextStop()
        selectedStop = navigationManager.currentStop
        if let tour {
            liveActivityManager.update(
                tour: tour,
                currentStopIndex: navigationManager.currentStopIndex,
                distanceToCurrentStop: navigationManager.distanceToCurrentStop
            )
        }
        if !navigationManager.isActive {
            liveActivityManager.end()
        }
    }

    func resetTour() {
        generationToken = UUID()
        navigationManager.stop()
        liveActivityManager.end()
        tour = nil
        routePolyline = nil
        selectedStop = nil
        directionsStop = nil
        wikipediaStop = nil
        state = .idle
    }

    func originCoordinate(for stop: TourStop, in tour: WalkingTour) -> CLLocationCoordinate2D {
        guard let index = tour.stops.firstIndex(where: { $0.id == stop.id }) else {
            return tour.startLocation
        }
        if index == 0 {
            return tour.startLocation
        }
        return tour.stops[index - 1].coordinate
    }

    func showDirections(for stop: TourStop) {
        directionsStop = stop
    }

    func showWikipedia(for stop: TourStop) {
        wikipediaStop = stop
    }
}
