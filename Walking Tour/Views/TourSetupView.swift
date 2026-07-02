import CoreLocation
import SwiftUI

struct TourSetupView: View {
    @Bindable var viewModel: TourViewModel
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLocationPicker = false

    var body: some View {
        ZStack {
            ThemedBackground()

            VStack(spacing: 10) {
                if viewModel.isOffline {
                    Label("Offline — saved tours still work", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                compactSection(title: "Start", icon: "location.fill") {
                    Picker("Location", selection: $viewModel.locationSource) {
                        ForEach(LocationSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch viewModel.locationSource {
                    case .current:
                        CompactLocationStatusRow(locationService: viewModel.locationService)
                    case .manual:
                        manualLocationRow
                    }
                }

                compactSection(title: "Theme", icon: "sparkles") {
                    ThemeMultiSelectMenu(themes: $viewModel.preferences.themes)
                        .onChange(of: viewModel.preferences.themes) { _, newThemes in
                            if newThemes.contains(.foodie) {
                                viewModel.preferences.includeFoodStops = true
                                viewModel.preferences.includeCoffeeStops = true
                            }
                        }
                }

                compactSection(title: "Length", icon: "clock") {
                    Picker("Measure", selection: $viewModel.preferences.lengthMode) {
                        ForEach(TourLengthMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(viewModel.preferences.lengthMode == .distance ? "Distance" : "Duration")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentText(for: colorScheme))
                        Spacer()
                        Text(lengthValueLabel)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.primary(for: colorScheme))
                    }

                    Slider(
                        value: lengthSliderValue,
                        in: lengthSliderRange,
                        step: lengthSliderStep
                    )
                    .tint(AppTheme.primary(for: colorScheme))

                    HStack(spacing: 16) {
                        Toggle("Food", isOn: $viewModel.preferences.includeFoodStops)
                            .font(.caption)
                        Toggle("Coffee", isOn: $viewModel.preferences.includeCoffeeStops)
                            .font(.caption)
                    }
                    .tint(AppTheme.primary(for: colorScheme))
                }

                Spacer(minLength: 0)

                if case .failure(let message) = viewModel.state {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                PrimaryActionButton(
                    title: viewModel.state == .loading ? "Planning…" : "Create Walking Tour",
                    isLoading: viewModel.state == .loading,
                    isEnabled: viewModel.canGenerateTour
                ) {
                    Task { await viewModel.generateTour() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerSheet(
                coordinate: viewModel.manualLocation,
                placeName: viewModel.manualLocationName,
                suggestedCenter: viewModel.locationService.currentLocation?.coordinate
            ) { coordinate, name in
                viewModel.manualLocation = coordinate
                viewModel.manualLocationName = name
            }
        }
    }

    private var manualLocationRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.manualLocation == nil ? "No location selected" : viewModel.manualLocationName)
                    .font(.caption.bold())
                    .lineLimit(1)
                if let coord = viewModel.manualLocation {
                    Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Choose") { showLocationPicker = true }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary(for: colorScheme))
                .controlSize(.small)
        }
    }

    private var lengthSliderValue: Binding<Double> {
        switch viewModel.preferences.lengthMode {
        case .distance:
            $viewModel.preferences.distanceMeters
        case .time:
            $viewModel.preferences.durationMinutes
        }
    }

    private var lengthSliderRange: ClosedRange<Double> {
        switch viewModel.preferences.lengthMode {
        case .distance:
            DistanceFormatter.sliderRange(unit: appSettings.distanceUnit)
        case .time:
            TourPreferences.minDurationMinutes...TourPreferences.maxDurationMinutes
        }
    }

    private var lengthSliderStep: Double {
        switch viewModel.preferences.lengthMode {
        case .distance:
            DistanceFormatter.sliderStep(unit: appSettings.distanceUnit)
        case .time:
            15
        }
    }

    private var lengthValueLabel: String {
        switch viewModel.preferences.lengthMode {
        case .distance:
            DistanceFormatter.displayValue(viewModel.preferences.distanceMeters, unit: appSettings.distanceUnit)
        case .time:
            formatDurationMinutes(viewModel.preferences.durationMinutes)
        }
    }

    private func formatDurationMinutes(_ minutes: Double) -> String {
        let total = Int(minutes)
        if total >= 60 {
            let hours = total / 60
            let remainder = total % 60
            return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
        }
        return "\(total) min"
    }

    @ViewBuilder
    private func compactSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: 8) {
                ThemedSectionHeader(title: title, icon: icon)
                content()
            }
        }
    }
}

private struct CompactLocationStatusRow: View {
    let locationService: LocationService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(statusTitle)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accentText(for: colorScheme))
            Spacer()
            if let location = locationService.currentLocation {
                Text(String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusIcon: String {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "location.fill"
        case .denied, .restricted: "location.slash"
        default: "location"
        }
    }

    private var statusColor: Color {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: AppTheme.primary(for: colorScheme)
        case .denied, .restricted: .red
        default: .orange
        }
    }

    private var statusTitle: String {
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationService.currentLocation == nil ? "Locating…" : "Ready"
        case .denied, .restricted: "Access denied"
        case .notDetermined: "Permission needed"
        @unknown default: "Unknown"
        }
    }
}
