import SwiftUI

struct WikipediaArticleView: View {
    let stop: TourStop
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let wikipediaService = WikipediaService()

    var body: some View {
        NavigationStack {
            Group {
                if NetworkMonitor.shared.isConnected, let url = articleURL {
                    EmbeddedWebView(url: url)
                } else {
                    offlineContent
                }
            }
            .navigationTitle(stop.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var articleURL: URL? {
        if let url = stop.wikipediaURL {
            return wikipediaService.mobilePageURL(for: url)
        }
        return wikipediaService.mobilePageURL(title: stop.name)
    }

    private var offlineContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    stop.wikipediaURL == nil ? "Offline — showing saved details" : "Offline — showing saved summary",
                    systemImage: "wifi.slash"
                )
                    .font(.caption)
                    .foregroundStyle(.orange)

                Text(stop.name)
                    .font(.title2.bold())

                Text(stop.summary.isEmpty ? "No saved details for this stop." : stop.summary)
                    .font(.body)

                if stop.isAppleMapsPlace {
                    Label("Apple Maps details are available when you're back online.", systemImage: "applelogo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(AppTheme.backgroundGradient(for: colorScheme))
    }
}
