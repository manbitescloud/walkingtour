import SwiftUI

struct LiveNavigationBar: View {
    @Bindable var viewModel: TourViewModel
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.navigationManager.progressLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    if let stop = viewModel.navigationManager.currentStop {
                        Text(stop.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let distance = viewModel.navigationManager.distanceToCurrentStop {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(DistanceFormatter.format(distance, unit: appSettings.distanceUnit))
                            .font(.headline.bold())
                        Text("to stop")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if viewModel.navigationManager.status == .arrived {
                Button {
                    viewModel.confirmArrivalAndAdvance()
                } label: {
                    Label(
                        viewModel.navigationManager.currentStopIndex + 1 >= (viewModel.tour?.stops.count ?? 0)
                            ? "Finish Tour"
                            : "Arrived — Next Stop",
                        systemImage: "checkmark.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else if viewModel.navigationManager.status == .completed {
                Label("Tour complete!", systemImage: "flag.checkered")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(AppTheme.summaryBarBackground(for: colorScheme))
    }
}
