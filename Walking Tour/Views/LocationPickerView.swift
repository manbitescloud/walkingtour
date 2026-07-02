import CoreLocation
import MapKit
import SwiftUI

struct LocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let suggestedCenter: CLLocationCoordinate2D?
    let onComplete: (CLLocationCoordinate2D?, String) -> Void

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var placeName: String

    init(
        coordinate: CLLocationCoordinate2D?,
        placeName: String,
        suggestedCenter: CLLocationCoordinate2D? = nil,
        onComplete: @escaping (CLLocationCoordinate2D?, String) -> Void
    ) {
        _coordinate = State(initialValue: coordinate)
        _placeName = State(initialValue: placeName)
        self.suggestedCenter = suggestedCenter ?? coordinate
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LocationPickerView(
                    coordinate: $coordinate,
                    placeName: $placeName,
                    suggestedCenter: suggestedCenter,
                    mapHeight: 300
                )
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Pick Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if let coordinate {
                            AppSettings.shared.addRecentLocation(coordinate: coordinate, name: placeName)
                        }
                        onComplete(coordinate, placeName)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct LocationPickerView: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var placeName: String
    var suggestedCenter: CLLocationCoordinate2D?
    var mapHeight: CGFloat = 220
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var mapRecenterToken = 0

    var body: some View {
        VStack(spacing: 12) {
            LocationSearchField(
                coordinate: $coordinate,
                placeName: $placeName,
                searchRegionCenter: coordinate ?? suggestedCenter,
                onSearchSelection: { mapRecenterToken += 1 }
            )

            LocationPickerMapView(
                coordinate: $coordinate,
                placeName: $placeName,
                suggestedCenter: suggestedCenter,
                mapHeight: mapHeight,
                recenterToken: mapRecenterToken
            )

            Text("Tap the map to set your starting point")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(coordinateLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(AppTheme.accentText(for: colorScheme).opacity(coordinate == nil ? 0.45 : 0.7))
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)

            recentLocationsSection
        }
    }

    private var recentLocationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accentText(for: colorScheme))

            if appSettings.recentLocations.isEmpty {
                Text("No recent locations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(appSettings.recentLocations) { location in
                        Button {
                            coordinate = location.coordinate
                            placeName = location.name
                            mapRecenterToken += 1
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.primary(for: colorScheme))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.accentText(for: colorScheme))
                                        .lineLimit(1)

                                    Text(
                                        String(
                                            format: "%.4f, %.4f",
                                            location.latitude,
                                            location.longitude
                                        )
                                    )
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if location.id != appSettings.recentLocations.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(AppTheme.fieldBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.cardBorder(for: colorScheme), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coordinateLabel: String {
        if let coordinate {
            return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        return "No point selected yet"
    }
}

// MARK: - Search (isolated so keystrokes don't rebuild the map)

private struct LocationSearchField: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var placeName: String
    let searchRegionCenter: CLLocationCoordinate2D?
    let onSearchSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchError: String?

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Search address or place", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { Task { await searchLocation() } }

                Button {
                    Task { await searchLocation() }
                } label: {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary(for: colorScheme))
                .disabled(trimmedQuery.isEmpty || isSearching)
            }

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func searchLocation() async {
        let query = trimmedQuery
        guard !query.isEmpty else { return }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let searchRegionCenter {
            request.region = MKCoordinateRegion(
                center: searchRegionCenter,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                searchError = "No results found."
                return
            }
            coordinate = item.location.coordinate
            placeName = item.name ?? query
            onSearchSelection()
        } catch {
            searchError = error.localizedDescription
        }
    }
}

// MARK: - Map

private struct LocationPickerMapView: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var placeName: String
    let suggestedCenter: CLLocationCoordinate2D?
    let mapHeight: CGFloat
    let recenterToken: Int

    @Environment(\.colorScheme) private var colorScheme
    @State private var position: MapCameraPosition = .automatic
    @State private var geocodeTask: Task<Void, Never>?
    @State private var didInitializeCamera = false

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                if let coordinate {
                    Marker(displayName, coordinate: coordinate)
                        .tint(AppTheme.primary(for: colorScheme))
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.secondary(for: colorScheme).opacity(0.5), lineWidth: 2)
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleMapTap(at: value.location, proxy: proxy)
                    }
            )
        }
        .frame(height: mapHeight)
        .onAppear {
            initializeCameraIfNeeded()
        }
        .onChange(of: recenterToken) { _, _ in
            guard let coordinate else { return }
            setCamera(center: coordinate, animated: true)
        }
        .onDisappear {
            geocodeTask?.cancel()
        }
    }

    private var displayName: String {
        placeName.isEmpty ? "Start Here" : placeName
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard let tapped = proxy.convert(point, from: .local) else { return }

        coordinate = tapped

        if shouldReplacePlaceName {
            placeName = "Selected Location"
        }

        reverseGeocode(tapped)
    }

    private var shouldReplacePlaceName: Bool {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Custom Location" || trimmed == "Selected Location"
    }

    private func initializeCameraIfNeeded() {
        guard !didInitializeCamera else { return }
        didInitializeCamera = true

        if let coordinate {
            setCamera(center: coordinate, animated: false)
        } else if let suggestedCenter {
            setCamera(center: suggestedCenter, animated: false)
        } else {
            setCamera(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                animated: false
            )
        }
    }

    private func setCamera(center: CLLocationCoordinate2D, animated: Bool) {
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 1_500,
            longitudinalMeters: 1_500
        )

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                position = .region(region)
            }
        } else {
            position = .region(region)
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { return }

            do {
                let mapItems = try await request.mapItems
                guard !Task.isCancelled,
                      let resolvedName = mapItems.first.flatMap(resolvedPlaceName(from:)),
                      !resolvedName.isEmpty else { return }

                await MainActor.run {
                    let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.isEmpty
                        || trimmed == "Custom Location"
                        || trimmed == "Selected Location" else { return }
                    placeName = resolvedName
                }
            } catch {
                // Ignore cancellation and lookup failures.
            }
        }
    }

    private func resolvedPlaceName(from item: MKMapItem) -> String? {
        if let name = item.name, !name.isEmpty {
            return name
        }
        if let shortAddress = item.address?.shortAddress, !shortAddress.isEmpty {
            return shortAddress
        }
        if let fullAddress = item.address?.fullAddress, !fullAddress.isEmpty {
            return fullAddress
        }
        return item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
    }
}
