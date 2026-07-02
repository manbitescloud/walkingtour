import CoreLocation
import Foundation

/// NSObject delegate bridge — kept separate from @Observable/@MainActor types to avoid launch crashes.
final class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var onLocationUpdate: ((CLLocation) -> Void)?
    var onError: ((String) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }
}

@MainActor
final class LocationService {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var errorMessage: String?
    private(set) var locationRevision = 0

    private let manager = CLLocationManager()
    private let delegateHandler = LocationManagerDelegate()

    init() {
        delegateHandler.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in
                self?.handleAuthorizationChange(status)
            }
        }
        delegateHandler.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                self?.handleLocationUpdate(location)
            }
        }
        delegateHandler.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
            }
        }

        manager.delegate = delegateHandler
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        currentLocation = location
        errorMessage = nil
        locationRevision += 1
    }
}
