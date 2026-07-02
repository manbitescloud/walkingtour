import CoreLocation
import Foundation
import MapKit

struct TouristAttractionService {
    private let wikipediaService = WikipediaService()

    func topAttractions(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int = 10
    ) async -> [TourStop] {
        let areaName = await resolveAreaName(for: coordinate)
        async let searchStops = curatedMapKitSearch(
            near: coordinate,
            radiusMeters: radiusMeters,
            areaName: areaName
        )
        async let poiStops = landmarkPOISearch(near: coordinate, radiusMeters: radiusMeters)
        async let wikiStops = notableWikipediaStops(
            near: coordinate,
            radiusMeters: radiusMeters
        )

        let combined = await searchStops + poiStops + wikiStops
        let ranked = rankAndDedupe(combined, near: coordinate, limit: limit)
        return ranked
    }

    // MARK: - Area context

    private func resolveAreaName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }

        guard let mapItems = try? await request.mapItems,
              let item = mapItems.first else {
            return nil
        }

        if let locality = item.address?.shortAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !locality.isEmpty {
            return locality
        }
        if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: false)?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - MapKit curated queries

    private func curatedMapKitSearch(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        areaName: String?
    ) async -> [TourStop] {
        var queries = [
            "top tourist attractions",
            "must see sights",
            "famous landmarks",
            "popular museums",
            "historic monuments",
        ]

        if let areaName, !areaName.isEmpty {
            queries.append(contentsOf: [
                "top tourist attractions in \(areaName)",
                "must see \(areaName)",
                "best things to do in \(areaName)",
            ])
        }

        var results: [TourStop] = []
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Double(min(radiusMeters * 2, 12_000)),
            longitudinalMeters: Double(min(radiusMeters * 2, 12_000))
        )

        for (queryIndex, query) in queries.enumerated() {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = [.pointOfInterest, .address]

            guard let response = await performSearch(request) else { continue }

            for (itemIndex, item) in response.mapItems.prefix(6).enumerated() {
                guard let stop = makeStop(
                    from: item,
                    near: coordinate,
                    radiusMeters: radiusMeters,
                    queryRank: queryIndex,
                    itemRank: itemIndex,
                    source: .curatedSearch
                ) else { continue }
                results.append(stop)
            }
        }

        return results
    }

    private func landmarkPOISearch(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int
    ) async -> [TourStop] {
        let radius = min(Double(radiusMeters), MKLocalPointsOfInterestRequest.maxRadius)
        let poiRequest = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .landmark, .museum, .nationalPark, .park, .theater, .library,
        ])

        guard let response = await performPOISearch(poiRequest) else { return [] }

        return response.mapItems.enumerated().compactMap { index, item in
            makeStop(
                from: item,
                near: coordinate,
                radiusMeters: radiusMeters,
                queryRank: 0,
                itemRank: index,
                source: .applePOI
            )
        }
    }

    // MARK: - Wikipedia notability filter

    private func notableWikipediaStops(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int
    ) async -> [TourStop] {
        let articles = (try? await wikipediaService.nearbyArticles(
            coordinate: coordinate,
            radiusMeters: radiusMeters,
            limit: 25,
            themes: [.highlights]
        )) ?? []

        return articles.enumerated().compactMap { index, stop in
            guard WikipediaNotabilityFilter.isNotable(stop) else { return nil }
            var ranked = stop
            ranked.touristAttractionRank = min(index + 1, 10)
            if ranked.category == .other {
                ranked = TourStop(
                    id: ranked.id,
                    name: ranked.name,
                    coordinate: ranked.coordinate,
                    category: WikipediaNotabilityFilter.inferredCategory(for: ranked),
                    summary: ranked.summary,
                    wikipediaURL: ranked.wikipediaURL,
                    imageURL: ranked.imageURL,
                    mapItemIdentifier: ranked.mapItemIdentifier,
                    appleMapsRelevanceRank: ranked.appleMapsRelevanceRank,
                    rating: ranked.rating,
                    touristAttractionRank: ranked.touristAttractionRank,
                    distanceFromPrevious: ranked.distanceFromPrevious
                )
            }
            return ranked
        }
    }

    // MARK: - Ranking & dedupe

    private func rankAndDedupe(
        _ stops: [TourStop],
        near coordinate: CLLocationCoordinate2D,
        limit: Int
    ) -> [TourStop] {
        var merged: [String: TourStop] = [:]
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        for stop in stops {
            let key = dedupeKey(for: stop)
            if var existing = merged[key] {
                existing = mergeAttraction(existing, with: stop)
                merged[key] = existing
            } else if let nearKey = merged.keys.first(where: { existingKey in
                guard let other = merged[existingKey] else { return false }
                return stop.location.distance(from: other.location) < 120
                    && namesSimilar(stop.name, other.name)
            }) {
                merged[nearKey] = mergeAttraction(merged[nearKey]!, with: stop)
            } else {
                merged[key] = stop
            }
        }

        let sorted = merged.values.sorted { lhs, rhs in
            attractionScore(lhs, near: origin) > attractionScore(rhs, near: origin)
        }

        return Array(sorted.prefix(limit)).enumerated().map { index, stop in
            var ranked = stop
            if ranked.touristAttractionRank == nil || ranked.touristAttractionRank! > index + 1 {
                ranked.touristAttractionRank = index + 1
            }
            return ranked
        }
    }

    private func attractionScore(_ stop: TourStop, near origin: CLLocation) -> Double {
        var score = 0.0
        if let rank = stop.touristAttractionRank {
            score += Double(11 - min(rank, 10)) * 2
        }
        if stop.wikipediaURL != nil { score += 3 }
        if stop.imageURL != nil { score += 2 }
        if stop.isAppleMapsPlace { score += 1.5 }
        switch stop.category {
        case .landmark, .historic, .museum: score += 3
        case .park: score += 2
        case .food, .coffee, .other: score -= 1
        }
        let distance = origin.distance(from: stop.location)
        score -= distance / 2_000
        return score
    }

    private func dedupeKey(for stop: TourStop) -> String {
        stop.name
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func namesSimilar(_ a: String, _ b: String) -> Bool {
        let lhs = a.lowercased()
        let rhs = b.lowercased()
        if lhs == rhs { return true }
        if lhs.contains(rhs) || rhs.contains(lhs) { return true }
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        let overlap = lhsTokens.intersection(rhsTokens).count
        return overlap >= max(1, min(lhsTokens.count, rhsTokens.count) / 2)
    }

    private func mergeAttraction(_ primary: TourStop, with other: TourStop) -> TourStop {
        var merged = primary

        if let otherRank = other.touristAttractionRank {
            if let current = merged.touristAttractionRank {
                merged.touristAttractionRank = min(current, otherRank)
            } else {
                merged.touristAttractionRank = otherRank
            }
        }

        if merged.wikipediaURL == nil { merged.wikipediaURL = other.wikipediaURL }
        if merged.imageURL == nil { merged.imageURL = other.imageURL }
        if merged.mapItemIdentifier == nil { merged.mapItemIdentifier = other.mapItemIdentifier }
        if merged.summary.isEmpty || merged.summary == merged.name {
            merged.summary = other.summary
        }
        if merged.category == .other, other.category != .other {
            merged = TourStop(
                id: merged.id,
                name: merged.name,
                coordinate: merged.coordinate,
                category: other.category,
                summary: merged.summary,
                wikipediaURL: merged.wikipediaURL,
                imageURL: merged.imageURL,
                mapItemIdentifier: merged.mapItemIdentifier,
                appleMapsRelevanceRank: merged.appleMapsRelevanceRank ?? other.appleMapsRelevanceRank,
                rating: merged.rating ?? other.rating,
                touristAttractionRank: merged.touristAttractionRank,
                distanceFromPrevious: merged.distanceFromPrevious
            )
        }

        return merged
    }

    // MARK: - MapKit helpers

    private enum AttractionSource {
        case curatedSearch
        case applePOI
    }

    private func makeStop(
        from item: MKMapItem,
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        queryRank: Int,
        itemRank: Int,
        source: AttractionSource
    ) -> TourStop? {
        guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              !WikipediaNotabilityFilter.isJunkName(name) else {
            return nil
        }

        let itemCoord = item.location.coordinate
        guard CLLocationCoordinate2DIsValid(itemCoord) else { return nil }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distance = origin.distance(from: item.location)
        guard distance <= Double(radiusMeters) + 500 else { return nil }

        let category = categoryForMapItem(item)
        let rank = min(10, queryRank + itemRank + 1)

        return TourStop(
            name: name,
            coordinate: itemCoord,
            category: category,
            summary: MapItemDetailBuilder.summary(for: item, category: category),
            mapItemIdentifier: item.identifier?.rawValue,
            appleMapsRelevanceRank: itemRank,
            touristAttractionRank: source == .curatedSearch ? rank : itemRank + 1
        )
    }

    private func categoryForMapItem(_ item: MKMapItem) -> StopCategory {
        guard let poi = item.pointOfInterestCategory else { return .landmark }
        switch poi {
        case .museum, .library: return .museum
        case .park, .nationalPark, .beach: return .park
        case .landmark, .theater: return .landmark
        default: return .landmark
        }
    }

    private func performSearch(_ request: MKLocalSearch.Request) async -> MKLocalSearch.Response? {
        try? await MKLocalSearch(request: request).start()
    }

    private func performPOISearch(_ request: MKLocalPointsOfInterestRequest) async -> MKLocalSearch.Response? {
        try? await MKLocalSearch(request: request).start()
    }
}

enum WikipediaNotabilityFilter {
    private static let junkKeywords = [
        "street", "avenue", "road", "boulevard", "lane", "drive", "highway",
        "building", "apartment", "residence", "house", "station", "parking",
        "interchange", "bridge approach", "block of", "district council",
    ]

    private static let notableKeywords = [
        "museum", "monument", "memorial", "cathedral", "church", "palace",
        "castle", "fort", "park", "garden", "tower", "bridge", "statue",
        "historic", "heritage", "landmark", "gallery", "theater", "theatre",
        "university", "capitol", "square", "plaza", "market", "zoo", "aquarium",
    ]

    static func isNotable(_ stop: TourStop) -> Bool {
        if isJunkName(stop.name) { return false }

        let text = (stop.name + " " + stop.summary).lowercased()
        if junkKeywords.contains(where: { text.contains($0) }) {
            let hasNotableSignal = notableKeywords.contains { text.contains($0) }
            if !hasNotableSignal { return false }
        }

        if stop.name.count < 4 { return false }

        if stop.wikipediaURL != nil, stop.imageURL != nil { return true }
        if stop.wikipediaURL != nil,
           StopDetailQuality.isSubstantiveSummary(stop.summary, name: stop.name) {
            return notableKeywords.contains { text.contains($0) }
        }

        return notableKeywords.contains { text.contains($0) }
    }

    static func isJunkName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.count < 3 { return true }
        if junkKeywords.contains(where: { lower.contains($0) }) {
            return !notableKeywords.contains { lower.contains($0) }
        }
        return false
    }

    static func inferredCategory(for stop: TourStop) -> StopCategory {
        let text = (stop.name + " " + stop.summary).lowercased()
        if text.contains("museum") || text.contains("gallery") { return .museum }
        if text.contains("park") || text.contains("garden") { return .park }
        if text.contains("church") || text.contains("cathedral") || text.contains("historic") {
            return .historic
        }
        if text.contains("monument") || text.contains("memorial") || text.contains("tower") {
            return .landmark
        }
        return .landmark
    }
}
