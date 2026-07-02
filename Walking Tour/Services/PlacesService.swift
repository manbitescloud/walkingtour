import CoreLocation
import Foundation
import MapKit

struct PlacesService {
    private let imageService = StopImageService()

    func nearbyPlaces(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        categories: [StopCategory] = [.landmark, .museum, .park, .historic]
    ) async -> [TourStop] {
        let stops = await mapKitSearch(coordinate: coordinate, categories: categories)
        return await imageService.enrichStops(stops)
    }

    func foodAndCoffeeStops(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int = 400,
        includeFood: Bool,
        includeCoffee: Bool
    ) async -> [TourStop] {
        var stops: [TourStop] = []

        if includeFood {
            let restaurants = await pointsOfInterestSearch(
                near: coordinate,
                radiusMeters: radiusMeters,
                poiCategories: [.restaurant, .bakery, .foodMarket],
                stopCategory: .food
            )
            stops.append(contentsOf: restaurants)
        }

        if includeCoffee {
            let cafes = await pointsOfInterestSearch(
                near: coordinate,
                radiusMeters: radiusMeters,
                poiCategories: [.cafe],
                stopCategory: .coffee
            )
            stops.append(contentsOf: cafes)
        }

        let enriched = await imageService.enrichStops(stops)
        return enriched.sorted { lhs, rhs in
            refreshmentScore(lhs) > refreshmentScore(rhs)
        }
    }

    private func mapKitSearch(
        coordinate: CLLocationCoordinate2D,
        categories: [StopCategory]
    ) async -> [TourStop] {
        var stops: [TourStop] = []

        for category in categories {
            if let poiCategories = poiCategories(for: category) {
                let poiStops = await pointsOfInterestSearch(
                    near: coordinate,
                    radiusMeters: 1_500,
                    poiCategories: poiCategories,
                    stopCategory: category
                )
                stops.append(contentsOf: poiStops.prefix(4))
                continue
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = mapKitQuery(for: category)
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            )
            request.resultTypes = .pointOfInterest

            guard let response = await performLocalSearch(request) else { continue }

            let categoryStops = response.mapItems.prefix(4).enumerated().map { index, item in
                makeStop(from: item, category: category, relevanceRank: index)
            }
            stops.append(contentsOf: categoryStops)
        }

        return stops
    }

    private func pointsOfInterestSearch(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        poiCategories: [MKPointOfInterestCategory],
        stopCategory: StopCategory
    ) async -> [TourStop] {
        let radius = min(Double(radiusMeters), MKLocalPointsOfInterestRequest.maxRadius)
        let poiRequest = MKLocalPointsOfInterestRequest(
            center: coordinate,
            radius: radius
        )
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)

        guard let response = await performPOISearch(poiRequest) else { return [] }

        return response.mapItems.enumerated().map { index, item in
            makeStop(from: item, category: stopCategory, relevanceRank: index)
        }
    }

    private func performLocalSearch(_ request: MKLocalSearch.Request) async -> MKLocalSearch.Response? {
        do {
            return try await MKLocalSearch(request: request).start()
        } catch {
            return nil
        }
    }

    private func performPOISearch(_ request: MKLocalPointsOfInterestRequest) async -> MKLocalSearch.Response? {
        do {
            return try await MKLocalSearch(request: request).start()
        } catch {
            return nil
        }
    }

    private func makeStop(
        from item: MKMapItem,
        category: StopCategory,
        relevanceRank: Int
    ) -> TourStop {
        TourStop(
            name: item.name ?? "Unknown",
            coordinate: item.location.coordinate,
            category: category,
            summary: MapItemDetailBuilder.summary(for: item, category: category),
            mapItemIdentifier: item.identifier?.rawValue,
            appleMapsRelevanceRank: relevanceRank
        )
    }

    private func refreshmentScore(_ stop: TourStop) -> Double {
        let relevanceBonus = Double(12 - min(stop.appleMapsRelevanceRank ?? 11, 11)) * 0.35
        let ratingBonus = (stop.rating ?? 0) * 2
        return relevanceBonus + ratingBonus
    }

    private func poiCategories(for category: StopCategory) -> [MKPointOfInterestCategory]? {
        switch category {
        case .museum: [.museum]
        case .park: [.park, .nationalPark]
        case .landmark, .historic: [.landmark, .museum]
        case .food: [.restaurant, .bakery, .foodMarket]
        case .coffee: [.cafe]
        case .other: nil
        }
    }

    private func mapKitQuery(for category: StopCategory) -> String {
        switch category {
        case .landmark: "landmarks"
        case .museum: "museums"
        case .park: "parks"
        case .historic: "historic sites"
        case .food: "restaurants"
        case .coffee: "coffee shops"
        case .other: "points of interest"
        }
    }
}
