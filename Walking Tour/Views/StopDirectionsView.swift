import CoreLocation
import MapKit
import SwiftUI

struct StopDirectionsView: View {
    let stop: TourStop
    let tour: WalkingTour
    let origin: CLLocationCoordinate2D
    let distanceUnit: DistanceUnit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var route: MKRoute?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let directionsService = DirectionsService()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Calculating route…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Route Unavailable",
                        systemImage: "map",
                        description: Text(errorMessage)
                    )
                } else if let route {
                    directionsContent(route)
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadRoute()
            }
        }
    }

    @ViewBuilder
    private func directionsContent(_ route: MKRoute) -> some View {
        VStack(spacing: 0) {
            Map(initialPosition: .region(region(for: route))) {
                MapPolyline(route.polyline)
                    .stroke(AppTheme.primary(for: colorScheme), lineWidth: 5)

                Annotation(stop.name, coordinate: stop.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(AppTheme.primary(for: colorScheme))
                }

                Annotation("Start", coordinate: origin) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.secondary(for: colorScheme))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 240)

            HStack(spacing: 20) {
                Label(
                    DistanceFormatter.format(route.distance, unit: distanceUnit),
                    systemImage: "arrow.left.and.right"
                )
                Label(formatDuration(route.expectedTravelTime), systemImage: "clock")
            }
            .font(.subheadline.bold())
            .foregroundStyle(AppTheme.accentText(for: colorScheme))
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppTheme.summaryBarBackground(for: colorScheme))

            List {
                Section("Steps to \(stop.name)") {
                    ForEach(Array(route.steps.enumerated()), id: \.offset) { index, step in
                        if !step.instructions.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(AppTheme.primary(for: colorScheme), in: Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.instructions)
                                        .font(.subheadline)
                                    Text(DistanceFormatter.format(step.distance, unit: distanceUnit))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func loadRoute() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            route = try await directionsService.walkingLeg(from: origin, to: stop.coordinate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func region(for route: MKRoute) -> MKCoordinateRegion {
        MKCoordinateRegion(route.polyline.boundingMapRect)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(1, minutes)) min"
    }
}
