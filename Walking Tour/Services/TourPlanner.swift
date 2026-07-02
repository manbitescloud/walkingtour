import CoreLocation
import Foundation

struct TourPlanner {
    private let wikipediaService = WikipediaService()
    private let wikivoyageService = WikivoyageService()
    private let placesService = PlacesService()
    private let attractionService = TouristAttractionService()
    private let directionsService = DirectionsService()
    private let imageService = StopImageService()
    private let detailService = StopDetailEnrichmentService()

    func generateTour(
        from start: CLLocationCoordinate2D,
        preferences: TourPreferences
    ) async throws -> WalkingTour {
        let radius = preferences.searchRadiusMeters
        let themes = preferences.themes

        async let wikiStopsTask = wikipediaService.nearbyArticles(
            coordinate: start,
            radiusMeters: radius,
            limit: 20,
            themes: themes
        )
        async let placeStopsTask = placesService.nearbyPlaces(
            coordinate: start,
            radiusMeters: radius,
            categories: themes.combinedPreferredCategories
        )
        async let attractionStopsTask = attractionService.topAttractions(
            near: start,
            radiusMeters: radius,
            limit: 10
        )
        async let wikivoyageStopsTask = wikivoyageService.recommendedStops(
            near: start,
            radiusMeters: radius,
            includeSightseeing: true,
            includeFood: preferences.includeFoodStops || themes.contains(.foodie),
            includeCoffee: preferences.includeCoffeeStops || themes.contains(.foodie),
            limit: 24
        )

        let wiki = (try? await wikiStopsTask) ?? []
        let places = await placeStopsTask
        let attractions = await attractionStopsTask
        let wikivoyage = await wikivoyageStopsTask
        let candidates = mergeCandidates(
            wikivoyage: wikivoyage,
            attractions: attractions,
            wiki: wiki,
            places: places,
            themes: themes
        )
        var selected = selectStops(
            candidates: candidates,
            start: start,
            targetDistance: preferences.targetDistanceMeters,
            routeShape: preferences.routeShape,
            themes: themes,
            reserveDwellTime: preferences.lengthMode == .time
        )

        let wantsRefreshments = preferences.includeFoodStops || preferences.includeCoffeeStops
        if wantsRefreshments, !selected.isEmpty {
            let midpoint = selected[selected.count / 2].coordinate
            async let mapRefreshmentsTask = placesService.foodAndCoffeeStops(
                near: midpoint,
                includeFood: preferences.includeFoodStops,
                includeCoffee: preferences.includeCoffeeStops
            )
            async let guideRefreshmentsTask = wikivoyageService.recommendedStops(
                near: midpoint,
                radiusMeters: 1_500,
                includeSightseeing: false,
                includeFood: preferences.includeFoodStops,
                includeCoffee: preferences.includeCoffeeStops,
                limit: 12
            )
            let mapRefreshments = await mapRefreshmentsTask
            let guideRefreshments = await guideRefreshmentsTask
            let refreshmentStops = mapRefreshments + guideRefreshments
            if let bestRefreshment = pickBestRefreshment(from: refreshmentStops, near: midpoint) {
                let insertIndex = min(selected.count / 2 + 1, selected.count)
                selected.insert(bestRefreshment, at: insertIndex)
            }
        }

        selected = reorderNearestNeighbor(
            stops: selected,
            start: start,
            routeShape: preferences.routeShape
        )

        var totalDistance: Double = 0
        var orderedStops: [TourStop] = []
        var previous = start

        for var stop in selected {
            let segmentDistance = directionsService.straightLineDistance(from: previous, to: stop.coordinate)
            stop.distanceFromPrevious = segmentDistance
            totalDistance += segmentDistance
            orderedStops.append(stop)
            previous = stop.coordinate
        }

        orderedStops = await imageService.enrichStops(orderedStops)
        orderedStops = await detailService.enrichStops(orderedStops)

        if preferences.routeShape == .loop, let last = orderedStops.last {
            totalDistance += directionsService.straightLineDistance(from: last.coordinate, to: start)
        }

        let duration = totalDistance / TourPreferences.walkingSpeedMetersPerMinute

        return WalkingTour(
            preferences: preferences,
            startLocation: start,
            stops: orderedStops,
            totalDistanceMeters: totalDistance,
            estimatedDurationMinutes: duration
        )
    }

    /// Finds nearby candidates to append to an existing tour, excluding stops already included.
    func findAdditionalStops(
        near coordinate: CLLocationCoordinate2D,
        excluding existingNames: Set<String>,
        themes: [TourTheme],
        limit: Int = 8
    ) async -> [TourStop] {
        async let attractionsTask = attractionService.topAttractions(
            near: coordinate,
            radiusMeters: 1_200,
            limit: 10
        )
        async let placesTask = placesService.nearbyPlaces(
            coordinate: coordinate,
            radiusMeters: 1_200,
            categories: themes.combinedPreferredCategories
        )
        async let wikivoyageTask = wikivoyageService.recommendedStops(
            near: coordinate,
            radiusMeters: 1_200,
            includeSightseeing: true,
            includeFood: themes.contains(.foodie),
            includeCoffee: themes.contains(.foodie),
            limit: 12
        )

        let attractions = await attractionsTask
        let places = await placesTask
        let wikivoyage = await wikivoyageTask
        let merged = mergeCandidates(
            wikivoyage: wikivoyage,
            attractions: attractions,
            wiki: [],
            places: places,
            themes: themes
        )

        let filtered = merged
            .filter { !existingNames.contains($0.name.lowercased()) }
            .sorted { lhs, rhs in
                let lhsRank = lhs.touristAttractionRank ?? Int.max
                let rhsRank = rhs.touristAttractionRank ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return themes.score(for: lhs) > themes.score(for: rhs)
            }

        let top = Array(filtered.prefix(limit))
        let withImages = await imageService.enrichStops(top)
        return await detailService.enrichStops(withImages)
    }

    private func mergeCandidates(
        wikivoyage: [TourStop],
        attractions: [TourStop],
        wiki: [TourStop],
        places: [TourStop],
        themes: [TourTheme]
    ) -> [TourStop] {
        var mergedByName: [String: TourStop] = [:]

        // Wikivoyage and ranked attractions win dedupe ties and keep curation metadata.
        for stop in wikivoyage + attractions + wiki + places {
            let key = stop.name.lowercased()
            if let existing = mergedByName[key] {
                mergedByName[key] = mergeStop(existing, with: stop)
            } else {
                mergedByName[key] = stop
            }
        }

        return mergedByName.values.sorted { lhs, rhs in
            let lhsRank = lhs.touristAttractionRank ?? Int.max
            let rhsRank = rhs.touristAttractionRank ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return themes.score(for: lhs) > themes.score(for: rhs)
        }
    }

    private func mergeStop(_ primary: TourStop, with other: TourStop) -> TourStop {
        var merged = primary

        if merged.wikipediaURL == nil {
            merged.wikipediaURL = other.wikipediaURL
        }

        if !StopDetailQuality.hasSubstantiveWikipediaDetail(merged),
           StopDetailQuality.isSubstantiveSummary(other.summary, name: other.name) {
            merged.summary = other.summary
        }

        if merged.mapItemIdentifier == nil {
            merged.mapItemIdentifier = other.mapItemIdentifier
        }

        if merged.appleMapsRelevanceRank == nil {
            merged.appleMapsRelevanceRank = other.appleMapsRelevanceRank
        }

        if merged.imageURL == nil {
            merged.imageURL = other.imageURL
        }

        if merged.rating == nil {
            merged.rating = other.rating
        }

        if let otherRank = other.touristAttractionRank {
            if let current = merged.touristAttractionRank {
                merged.touristAttractionRank = min(current, otherRank)
            } else {
                merged.touristAttractionRank = otherRank
            }
        }

        return merged
    }

    private func selectStops(
        candidates: [TourStop],
        start: CLLocationCoordinate2D,
        targetDistance: Double,
        routeShape: RouteShape,
        themes: [TourTheme],
        reserveDwellTime: Bool
    ) -> [TourStop] {
        var selected: [TourStop] = []
        var traveled: Double = 0
        var current = start
        var remaining = candidates

        let budget: Double
        switch routeShape {
        case .loop:
            budget = targetDistance * 0.7
        case .oneWay:
            budget = targetDistance * 0.85
        }

        let maxStops = min(max(3, Int(targetDistance / 400)), 20)

        while traveled < budget, selected.count < maxStops, !remaining.isEmpty {
            remaining.sort {
                selectionScore(
                    for: $0,
                    from: current,
                    budgetRemaining: budget - traveled,
                    themes: themes
                ) > selectionScore(
                    for: $1,
                    from: current,
                    budgetRemaining: budget - traveled,
                    themes: themes
                )
            }

            guard let next = remaining.first else { break }
            let leg = directionsService.straightLineDistance(from: current, to: next.coordinate)

            // When the tour length is a hard time budget, treat dwell time as consuming
            // part of that budget too (converted to an equivalent walking distance),
            // otherwise a "45 minute" request would need 45 minutes of pure walking.
            let dwellDistanceEquivalent = reserveDwellTime
                ? next.category.dwellMinutes * TourPreferences.walkingSpeedMetersPerMinute
                : 0

            if traveled + leg + dwellDistanceEquivalent > budget { break }

            selected.append(next)
            traveled += leg + dwellDistanceEquivalent
            current = next.coordinate
            remaining.removeFirst()
        }

        return selected
    }

    private func selectionScore(
        for stop: TourStop,
        from current: CLLocationCoordinate2D,
        budgetRemaining: Double,
        themes: [TourTheme]
    ) -> Double {
        let distance = directionsService.straightLineDistance(from: current, to: stop.coordinate)
        guard distance <= budgetRemaining else { return -.infinity }

        var score = themes.score(for: stop)
        if let rank = stop.touristAttractionRank {
            score += Double(11 - min(rank, 10)) * 2.5
        }
        score -= distance / 600
        return score
    }

    private func pickBestRefreshment(from stops: [TourStop], near coordinate: CLLocationCoordinate2D) -> TourStop? {
        stops.max { a, b in
            refreshmentScore(a, near: coordinate) < refreshmentScore(b, near: coordinate)
        }
    }

    private func refreshmentScore(_ stop: TourStop, near coordinate: CLLocationCoordinate2D) -> Double {
        let distance = directionsService.straightLineDistance(from: coordinate, to: stop.coordinate)
        let relevanceBonus = Double(12 - min(stop.appleMapsRelevanceRank ?? 11, 11)) * 0.4
        let guideBonus = stop.touristAttractionRank.map { Double(11 - min($0, 10)) * 1.5 } ?? 0
        let ratingBonus = (stop.rating ?? 0) * 2
        return relevanceBonus + guideBonus + ratingBonus - distance / 900
    }

    private func reorderNearestNeighbor(
        stops: [TourStop],
        start: CLLocationCoordinate2D,
        routeShape: RouteShape
    ) -> [TourStop] {
        guard !stops.isEmpty else { return [] }

        var unvisited = stops
        var ordered: [TourStop] = []
        var current = start

        while !unvisited.isEmpty {
            if routeShape == .oneWay, ordered.isEmpty {
                unvisited.sort {
                    directionsService.straightLineDistance(from: current, to: $1.coordinate) <
                        directionsService.straightLineDistance(from: current, to: $0.coordinate)
                }
            } else {
                unvisited.sort {
                    directionsService.straightLineDistance(from: current, to: $0.coordinate) <
                        directionsService.straightLineDistance(from: current, to: $1.coordinate)
                }
            }
            let next = unvisited.removeFirst()
            ordered.append(next)
            current = next.coordinate
        }

        return ordered
    }
}
