import ActivityKit
import MapKit
import SwiftUI
import WidgetKit

struct TourLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TourActivityAttributes.self) { context in
            LockScreenTourView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(red: 0.07, green: 0.09, blue: 0.14))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.currentStopCategoryIcon)
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progressLabel)
                        .font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentStopName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TourMiniMap(state: context.state)
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } compactLeading: {
                Image(systemName: context.state.currentStopCategoryIcon)
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(context.state.currentStopIndex + 1)/\(context.state.totalStops)")
                    .font(.caption2.bold())
            } minimal: {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct LockScreenTourView: View {
    let attributes: TourActivityAttributes
    let state: TourActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            TourMiniMap(state: state)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.tourName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 6) {
                    Image(systemName: state.currentStopCategoryIcon)
                        .foregroundStyle(.blue)
                    Text(state.currentStopName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(state.progressLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.85))

                if let distance = state.distanceToCurrentStopMeters {
                    Text(distanceLabel(distance))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                } else if let nextStop = state.nextStopName {
                    Text("Next: \(nextStop)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer()
        }
        .padding(14)
    }

    private func distanceLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km away", meters / 1_000)
        }
        return String(format: "%.0f m away", meters)
    }
}

private struct TourMiniMap: View {
    let state: TourActivityAttributes.ContentState

    private var currentCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: state.latitude, longitude: state.longitude)
    }

    private var cameraPosition: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: currentCoordinate,
                latitudinalMeters: 400,
                longitudinalMeters: 400
            )
        )
    }

    var body: some View {
        Map(initialPosition: cameraPosition, interactionModes: []) {
            ForEach(Array(zip(state.stopLatitudes.indices, state.stopLatitudes)), id: \.0) { index, latitude in
                let longitude = state.stopLongitudes[index]
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if index == state.currentStopIndex {
                    Marker(state.currentStopName, coordinate: coordinate)
                        .tint(.blue)
                } else {
                    Annotation("", coordinate: coordinate) {
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}
