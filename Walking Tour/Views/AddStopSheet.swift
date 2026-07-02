import SwiftUI

struct AddStopSheet: View {
    @Bindable var viewModel: TourViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingAddStopCandidates {
                    ProgressView("Finding nearby spots…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.addStopCandidates.isEmpty {
                    ContentUnavailableView(
                        "No Suggestions Found",
                        systemImage: "mappin.slash",
                        description: Text("Try again later or from a different part of the route.")
                    )
                } else {
                    List(viewModel.addStopCandidates) { candidate in
                        candidateRow(candidate)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add a Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await viewModel.loadAddStopCandidates() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingAddStopCandidates)
                }
            }
        }
    }

    private func candidateRow(_ candidate: TourStop) -> some View {
        Button {
            Task { await viewModel.addStop(candidate) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primary(for: colorScheme).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: candidate.category.icon)
                        .foregroundStyle(AppTheme.primary(for: colorScheme))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(candidate.category.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary(for: colorScheme))
            }
            .padding(.vertical, 4)
        }
        .disabled(viewModel.isUpdatingStops)
    }
}
