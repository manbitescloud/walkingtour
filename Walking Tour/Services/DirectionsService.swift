import CoreLocation
import Foundation
import MapKit

struct WalkingRouteResult {
    let polyline: MKPolyline?
    /// Real routed distance in meters (falls back to straight-line per-leg if routing fails).
    let distanceMeters: Double
    /// Real routed walking time in minutes (falls back to distance/speed per-leg if routing fails).
    let travelTimeMinutes: Double
    /// True if every leg resolved to a real MapKit walking route (no straight-line fallbacks).
    let isFullyRouted: Bool
}

struct DirectionsService {
    func walkingRoute(
        through stops: [TourStop],
        start: CLLocationCoordinate2D,
        isLoop: Bool
    ) async -> WalkingRouteResult {
        guard CLLocationCoordinate2DIsValid(start) else {
            return WalkingRouteResult(polyline: nil, distanceMeters: 0, travelTimeMinutes: 0, isFullyRouted: false)
        }

        var waypoints: [CLLocationCoordinate2D] = [start]
        waypoints.append(contentsOf: stops.map(\.coordinate).filter { CLLocationCoordinate2DIsValid($0) })
        if isLoop {
            waypoints.append(start)
        }

        guard waypoints.count >= 2 else {
            return WalkingRouteResult(polyline: nil, distanceMeters: 0, travelTimeMinutes: 0, isFullyRouted: false)
        }

        var totalDistance: Double = 0
        var totalTravelTimeSeconds: Double = 0
        var coordinates: [CLLocationCoordinate2D] = []
        var isFullyRouted = true

        for index in 0..<(waypoints.count - 1) {
            let from = waypoints[index]
            let to = waypoints[index + 1]

            if let leg = await walkingLegCoordinates(from: from, to: to) {
                appendCoordinates(leg.coordinates, to: &coordinates)
                totalDistance += leg.distance
                totalTravelTimeSeconds += leg.travelTime
            } else {
                isFullyRouted = false
                appendStraightLine(from: from, to: to, to: &coordinates)
                let fallbackDistance = straightLineDistance(from: from, to: to)
                totalDistance += fallbackDistance
                totalTravelTimeSeconds += fallbackDistance / (TourPreferences.walkingSpeedMetersPerMinute / 60)
            }
        }

        let validCoordinates = coordinates.filter { CLLocationCoordinate2DIsValid($0) }
        let polyline = validCoordinates.count >= 2
            ? MKPolyline(coordinates: validCoordinates, count: validCoordinates.count)
            : nil

        return WalkingRouteResult(
            polyline: polyline,
            distanceMeters: totalDistance,
            travelTimeMinutes: totalTravelTimeSeconds / 60,
            isFullyRouted: isFullyRouted
        )
    }

    func straightLineDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    func walkingLeg(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> MKRoute {
        guard CLLocationCoordinate2DIsValid(origin), CLLocationCoordinate2DIsValid(destination) else {
            throw DirectionsError.invalidCoordinates
        }

        let request = MKDirections.Request()
        request.source = mapItem(at: origin)
        request.destination = mapItem(at: destination)
        request.transportType = .walking

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw DirectionsError.noRouteFound
        }
        return route
    }

    private func mapItem(at coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }

    private struct LegCoordinates {
        let coordinates: [CLLocationCoordinate2D]
        let distance: Double
        let travelTime: Double
    }

    private func walkingLegCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> LegCoordinates? {
        guard CLLocationCoordinate2DIsValid(origin), CLLocationCoordinate2DIsValid(destination) else {
            return nil
        }

        let request = MKDirections.Request()
        request.source = mapItem(at: origin)
        request.destination = mapItem(at: destination)
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }

            let pointCount = route.polyline.pointCount
            guard pointCount > 0 else { return nil }

            var routeCoords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
            route.polyline.getCoordinates(&routeCoords, range: NSRange(location: 0, length: pointCount))
            let validCoords = routeCoords.filter { CLLocationCoordinate2DIsValid($0) }
            guard validCoords.count >= 2 else { return nil }

            return LegCoordinates(coordinates: validCoords, distance: route.distance, travelTime: route.expectedTravelTime)
        } catch {
            return nil
        }
    }

    private func appendCoordinates(_ newCoordinates: [CLLocationCoordinate2D], to coordinates: inout [CLLocationCoordinate2D]) {
        guard !newCoordinates.isEmpty else { return }

        if coordinates.isEmpty {
            coordinates.append(contentsOf: newCoordinates)
            return
        }

        var segment = newCoordinates
        if let last = coordinates.last,
           let first = segment.first,
           last.latitude == first.latitude,
           last.longitude == first.longitude {
            segment.removeFirst()
        }
        coordinates.append(contentsOf: segment)
    }

    private func appendStraightLine(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        to coordinates: inout [CLLocationCoordinate2D]
    ) {
        if coordinates.isEmpty {
            coordinates.append(from)
        } else if let last = coordinates.last,
                  last.latitude != from.latitude || last.longitude != from.longitude {
            coordinates.append(from)
        }
        coordinates.append(to)
    }
}

enum DirectionsError: LocalizedError {
    case invalidCoordinates
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .invalidCoordinates: "Invalid map coordinates."
        case .noRouteFound: "No walking route found."
        }
    }
}
