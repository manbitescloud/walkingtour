import MapKit
import SwiftUI

struct StopDetailView: View {
    let stop: TourStop
    let stepNumber: Int
    let distanceUnit: DistanceUnit
    let onShowDirections: () -> Void
    let onShowWikipedia: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayStop: TourStop?
    @State private var appleMapsItem: MKMapItem?
    @State private var showAppleMapsDetail = false

    private let detailService = StopDetailEnrichmentService()

    private var resolvedStop: TourStop {
        displayStop ?? stop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stopHeroImage

            headerSection
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if resolvedStop.summary.isEmpty {
                        ProgressView("Loading details…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(resolvedStop.summary)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if resolvedStop.wikipediaURL == nil, appleMapsItem != nil {
                        Label("Details from Apple Maps", systemImage: "applelogo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.visible)

            actionButtons
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(AppTheme.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .task(id: stop.id) {
            await loadStopDetails()
        }
        .mapItemDetailSheet(isPresented: $showAppleMapsDetail, item: appleMapsItem, displaysMap: false)
    }

    private func loadStopDetails() async {
        displayStop = nil
        appleMapsItem = nil

        let enriched = await detailService.enrichStop(stop)
        displayStop = enriched
        appleMapsItem = await resolveAppleMapsItem(for: enriched)
    }

    private func resolveAppleMapsItem(for stop: TourStop) async -> MKMapItem? {
        if let identifier = stop.mapItemIdentifier,
           let item = await MapItemResolver.mapItem(identifier: identifier) {
            return item
        }
        return await MapItemResolver.search(named: stop.name, near: stop.coordinate)
    }

    private var stopHeroImage: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let imageURL = resolvedStop.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            categoryPlaceholder
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(AppTheme.summaryBarBackground(for: colorScheme))
                        }
                    }
                } else {
                    categoryPlaceholder
                }
            }
            .frame(height: 118)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.45), .clear],
                startPoint: .bottom,
                endPoint: .center
            )
            .frame(height: 118)

            Text(resolvedStop.name)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(10)
        }
    }

    private var categoryPlaceholder: some View {
        ZStack {
            AppTheme.summaryBarBackground(for: colorScheme)
            Image(systemName: resolvedStop.category.icon)
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.primary(for: colorScheme).opacity(0.55))
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Stop \(stepNumber)", systemImage: "figure.walk")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Label(resolvedStop.category.label, systemImage: resolvedStop.category.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary(for: colorScheme).opacity(0.18), in: Capsule())
            }

            if resolvedStop.isAppleMapsPlace, let rank = resolvedStop.appleMapsRelevanceRank, rank < 3 {
                Label("Popular on Apple Maps", systemImage: "star.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.primary(for: colorScheme))
            }

            if let rating = resolvedStop.rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline.bold())
                    Text("rating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let distance = resolvedStop.distanceFromPrevious {
                Label(
                    DistanceFormatter.format(distance, unit: distanceUnit, suffix: "from previous stop"),
                    systemImage: "arrow.triangle.turn.up.right.diamond"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if appleMapsItem != nil {
                Button {
                    showAppleMapsDetail = true
                } label: {
                    Label("Apple Maps reviews & photos", systemImage: "applelogo")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
                .tint(AppTheme.primary(for: colorScheme))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: onShowDirections) {
                Label("Directions", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primary(for: colorScheme))

            if resolvedStop.wikipediaURL != nil {
                Button(action: onShowWikipedia) {
                    Label("Read More", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary(for: colorScheme))
            } else if appleMapsItem != nil {
                Button {
                    showAppleMapsDetail = true
                } label: {
                    Label("Place Details", systemImage: "applelogo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primary(for: colorScheme))
            }
        }
    }
}
