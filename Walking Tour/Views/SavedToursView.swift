import SwiftUI

struct SavedToursView: View {
    @Bindable var viewModel: TourViewModel
    var onTourSelected: (() -> Void)?

    var body: some View {
        ZStack {
            ThemedBackground()

            Group {
                if viewModel.savedTours.isEmpty {
                    ContentUnavailableView(
                        "No Saved Tours",
                        systemImage: "bookmark",
                        description: Text("Save a tour from the Plan tab to access it offline.")
                    )
                } else {
                    List {
                        ForEach(viewModel.savedTours) { saved in
                            Button {
                                Task {
                                    await viewModel.loadSavedTour(saved)
                                    onTourSelected?()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(saved.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    HStack {
                                        Label(saved.preferences.themes.displayLabel, systemImage: "sparkles")
                                        Text("·")
                                        Text("\(saved.stops.count) stops")
                                        Text("·")
                                        Text(saved.preferences.routeShape.label)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    Text(saved.createdAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteSavedTour(viewModel.savedTours[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Saved Tours")
    }
}

#Preview {
    NavigationStack {
        SavedToursView(viewModel: TourViewModel())
    }
}
