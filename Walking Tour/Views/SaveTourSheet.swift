import SwiftUI

struct SaveTourSheet: View {
    @Bindable var viewModel: TourViewModel
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tour name", text: $viewModel.saveTourName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Saved tours are stored on your device and available offline.")
                }

                if let tour = viewModel.tour {
                    Section("Preview") {
                        LabeledContent("Themes", value: tour.preferences.themes.displayLabel)
                        LabeledContent("Stops", value: "\(tour.stops.count)")
                        LabeledContent("Route", value: tour.preferences.routeShape.label)
                        LabeledContent("Distance") {
                            Text(tour.formattedDistance(unit: appSettings.distanceUnit))
                        }
                    }
                }
            }
            .navigationTitle("Save Tour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveCurrentTour()
                        dismiss()
                    }
                    .disabled(viewModel.saveTourName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
