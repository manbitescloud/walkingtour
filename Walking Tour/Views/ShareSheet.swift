import SwiftUI
import UIKit

struct SharePayload: Identifiable {
    let id: UUID
    let items: [Any]

    init(tour: WalkingTour) {
        id = tour.id
        items = [tour.shareText]
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
