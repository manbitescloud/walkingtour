import CoreLocation
import Foundation
import MapKit

struct StopDetailEnrichmentService {
    private let wikipediaService = WikipediaService()

    func enrichStops(_ stops: [TourStop]) async -> [TourStop] {
        var updated = stops
        for index in updated.indices {
            updated[index] = await enrichStop(updated[index])
        }
        return updated
    }

    func enrichStop(_ stop: TourStop) async -> TourStop {
        var updated = stop

        if StopDetailQuality.hasSubstantiveWikipediaDetail(stop) {
            if updated.mapItemIdentifier == nil,
               let item = await MapItemResolver.search(named: stop.name, near: stop.coordinate) {
                updated.mapItemIdentifier = item.identifier?.rawValue
            }
            return updated
        }

        if stop.wikipediaURL == nil,
           let article = await wikipediaService.summaryForTitle(stop.name),
           StopDetailQuality.isSubstantiveSummary(article.extract, name: stop.name) {
            updated.summary = article.extract
            updated.wikipediaURL = article.url
            if updated.imageURL == nil {
                updated.imageURL = article.thumbnailURL
            }
            if updated.mapItemIdentifier == nil,
               let item = await MapItemResolver.search(named: stop.name, near: stop.coordinate) {
                updated.mapItemIdentifier = item.identifier?.rawValue
            }
            return updated
        }

        if let mapItem = await resolveMapItem(for: stop) {
            updated.summary = MapItemDetailBuilder.summary(for: mapItem, category: stop.category)
            if updated.mapItemIdentifier == nil {
                updated.mapItemIdentifier = mapItem.identifier?.rawValue
            }
            return updated
        }

        if let geocoded = await reverseGeocodeSummary(for: stop),
           StopDetailQuality.isSubstantiveSummary(geocoded, name: stop.name) {
            updated.summary = geocoded
        }

        return updated
    }

    private func resolveMapItem(for stop: TourStop) async -> MKMapItem? {
        if let identifier = stop.mapItemIdentifier,
           let item = await MapItemResolver.mapItem(identifier: identifier) {
            return item
        }
        return await MapItemResolver.search(named: stop.name, near: stop.coordinate)
    }

    private func reverseGeocodeSummary(for stop: TourStop) async -> String? {
        let location = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }

        guard let mapItems = try? await request.mapItems,
              let item = mapItems.first else {
            return nil
        }

        let placeName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = MapItemDetailBuilder.formattedAddress(for: item)
        let categoryLabel = stop.category.label.lowercased()

        if let placeName, !placeName.isEmpty, placeName.caseInsensitiveCompare(stop.name) != .orderedSame {
            if let address, !address.isEmpty {
                return "\(stop.name) is a \(categoryLabel) near \(placeName).\n\n\(address)"
            }
            return "\(stop.name) is a \(categoryLabel) near \(placeName)."
        }

        if let address, !address.isEmpty {
            return "\(stop.name) is a nearby \(categoryLabel).\n\n\(address)"
        }

        return nil
    }
}

enum StopDetailQuality {
    static func hasSubstantiveWikipediaDetail(_ stop: TourStop) -> Bool {
        guard stop.wikipediaURL != nil else { return false }
        return isSubstantiveSummary(stop.summary, name: stop.name)
    }

    static func isSubstantiveSummary(_ summary: String, name: String) -> Bool {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != "No description available." else { return false }
        guard trimmed.caseInsensitiveCompare(name) != .orderedSame else { return false }
        return trimmed.count >= 40 || trimmed.contains(".")
    }
}

enum MapItemDetailBuilder {
    static func summary(for item: MKMapItem, category: StopCategory) -> String {
        var lines: [String] = []

        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let categoryLabel = poiLabel(for: item) ?? category.label.lowercased()

        if !name.isEmpty {
            lines.append("\(name) is a \(categoryLabel) listed on Apple Maps.")
        } else {
            lines.append("A \(categoryLabel) listed on Apple Maps.")
        }

        if let address = formattedAddress(for: item), !address.isEmpty {
            lines.append(address)
        }

        if let phone = item.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            lines.append(phone)
        }

        if let url = item.url?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            lines.append(url)
        }

        lines.append("Open place details for Apple Maps reviews and photos.")

        return lines.joined(separator: "\n\n")
    }

    static func formattedAddress(for item: MKMapItem) -> String? {
        if let fullAddress = item.address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }
        if let shortAddress = item.address?.shortAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shortAddress.isEmpty {
            return shortAddress
        }
        if let formatted = item.addressRepresentations?
            .fullAddress(includingRegion: false, singleLine: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !formatted.isEmpty {
            return formatted
        }
        return nil
    }

    private static func poiLabel(for item: MKMapItem) -> String? {
        guard let category = item.pointOfInterestCategory else { return nil }
        switch category {
        case .museum: return "museum"
        case .park, .nationalPark: return "park"
        case .landmark: return "landmark"
        case .restaurant, .foodMarket, .bakery: return "restaurant"
        case .cafe: return "café"
        case .library: return "library"
        case .theater: return "theater"
        case .beach: return "beach"
        default: return category.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }
}

enum MapItemResolver {
    static func mapItem(identifier: String) async -> MKMapItem? {
        guard let mapItemID = MKMapItem.Identifier(rawValue: identifier) else { return nil }
        let request = MKMapItemRequest(mapItemIdentifier: mapItemID)
        return try? await request.mapItem
    }

    static func search(named name: String, near coordinate: CLLocationCoordinate2D) async -> MKMapItem? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedName
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 350,
            longitudinalMeters: 350
        )
        request.resultTypes = [.pointOfInterest, .address]

        guard let response = try? await MKLocalSearch(request: request).start() else {
            return nil
        }

        return bestMatch(in: response.mapItems, named: trimmedName, near: coordinate)
    }

    private static func bestMatch(
        in items: [MKMapItem],
        named name: String,
        near coordinate: CLLocationCoordinate2D
    ) -> MKMapItem? {
        let target = name.lowercased()
        let scored = items.compactMap { item -> (MKMapItem, Double)? in
            guard let itemName = item.name?.lowercased(), !itemName.isEmpty else { return nil }

            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: item.location)
            let distanceScore = max(0, 350 - distance) / 350

            let nameScore: Double
            if itemName == target {
                nameScore = 1
            } else if itemName.contains(target) || target.contains(itemName) {
                nameScore = 0.75
            } else {
                nameScore = 0.2
            }

            return (item, nameScore * 0.7 + distanceScore * 0.3)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }
}
