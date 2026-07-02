import SwiftUI

struct SettingsView: View {
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            ThemedBackground()

            Form {
                Section {
                    Picker("Appearance", selection: $appSettings.appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.cardBackground(for: colorScheme))
                } header: {
                    ThemedSectionHeader(title: "Appearance", icon: "moon.fill")
                }

                Section {
                    Picker("Distance unit", selection: $appSettings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.cardBackground(for: colorScheme))
                } header: {
                    ThemedSectionHeader(title: "Units", icon: "ruler")
                }

                Section {
                    Picker("Route type", selection: $appSettings.routeShape) {
                        ForEach(RouteShape.allCases) { shape in
                            Text(shape.label).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.cardBackground(for: colorScheme))

                    Text(appSettings.routeShape.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(AppTheme.cardBackground(for: colorScheme))
                } header: {
                    ThemedSectionHeader(title: "Route", icon: "arrow.trianglehead.counterclockwise")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                        .listRowBackground(AppTheme.cardBackground(for: colorScheme))
                } header: {
                    ThemedSectionHeader(title: "About", icon: "info.circle")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
