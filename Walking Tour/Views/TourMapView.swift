import MapKit
import SwiftUI

struct TourMapView: View {
    let tour: WalkingTour
    let routePolyline: MKPolyline?
    let selectedStopID: UUID?
    var currentStopIndex: Int?
    var followUser: Bool = false
    var showUserLocation: Bool = false
    var onSelectStop: (TourStop) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var position: MapCameraPosition = .automatic

    private var startTitle: String {
        let name = tour.preferences.startLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Start" : name
    }

    var body: some View {
        Map(position: $position) {
            Annotation(startTitle, coordinate: tour.startLocation) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 34, height: 34)
                    Image(systemName: "figure.walk")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .shadow(radius: 3)
            }

            ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Button {
                        onSelectStop(stop)
                    } label: {
                        StopMapMarker(
                            stop: stop,
                            stepNumber: index + 1,
                            isSelected: selectedStopID == stop.id,
                            isCurrent: currentStopIndex == index
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let routePolyline, routePolyline.pointCount >= 2 {
                MapPolyline(routePolyline)
                    .stroke(AppTheme.primary(for: colorScheme), lineWidth: 4)
            }

            if showUserLocation {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            if showUserLocation {
                MapUserLocationButton()
            }
            MapCompass()
        }
        .onAppear {
            position = .region(regionForTour())
        }
        .onChange(of: followUser) { _, isFollowing in
            if isFollowing, showUserLocation {
                position = .userLocation(followsHeading: true, fallback: .region(regionForTour()))
            } else {
                position = .region(regionForTour())
            }
        }
        .onChange(of: showUserLocation) { _, hasLocation in
            if followUser, hasLocation {
                position = .userLocation(followsHeading: true, fallback: .region(regionForTour()))
            }
        }
    }

    private func regionForTour() -> MKCoordinateRegion {
        var coordinates = tour.stops.map(\.coordinate)
        coordinates.append(tour.startLocation)

        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: tour.startLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        let minLat = coordinates.map(\.latitude).min() ?? tour.startLocation.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? tour.startLocation.latitude
        let minLon = coordinates.map(\.longitude).min() ?? tour.startLocation.longitude
        let maxLon = coordinates.map(\.longitude).max() ?? tour.startLocation.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct StopMapMarker: View {
    let stop: TourStop
    let stepNumber: Int
    let isSelected: Bool
    let isCurrent: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)
                Text("\(stepNumber)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
            .shadow(radius: 2)

            if isSelected || isCurrent {
                Text(stop.name)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }

    private var backgroundColor: Color {
        if isCurrent { .green }
        else if isSelected { .orange }
        else { AppTheme.primary(for: colorScheme) }
    }
}
