import CoreLocation
import Foundation

enum StopCategory: String, Codable, CaseIterable, Hashable {
    case landmark
    case museum
    case park
    case historic
    case food
    case coffee
    case other

    var icon: String {
        switch self {
        case .landmark: "building.columns"
        case .museum: "building.2"
        case .park: "leaf"
        case .historic: "clock"
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer"
        case .other: "mappin"
        }
    }

    var label: String {
        switch self {
        case .landmark: "Landmark"
        case .museum: "Museum"
        case .park: "Park"
        case .historic: "Historic"
        case .food: "Food"
        case .coffee: "Coffee"
        case .other: "Point of Interest"
        }
    }

    /// Estimated minutes a visitor lingers at this stop, used to make tour duration
    /// estimates reflect actual visit time rather than just walking time.
    var dwellMinutes: Double {
        switch self {
        case .museum: 20
        case .food: 20
        case .historic: 18
        case .landmark: 15
        case .park: 15
        case .coffee: 15
        case .other: 15
        }
    }
}

struct TourStop: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let category: StopCategory
    var summary: String
    var wikipediaURL: URL?
    var imageURL: URL?
    var mapItemIdentifier: String?
    var appleMapsRelevanceRank: Int?
    var rating: Double?
    var touristAttractionRank: Int?
    var distanceFromPrevious: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var isAppleMapsPlace: Bool {
        mapItemIdentifier != nil
    }

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: CLLocationCoordinate2D,
        category: StopCategory = .other,
        summary: String = "",
        wikipediaURL: URL? = nil,
        imageURL: URL? = nil,
        mapItemIdentifier: String? = nil,
        appleMapsRelevanceRank: Int? = nil,
        rating: Double? = nil,
        touristAttractionRank: Int? = nil,
        distanceFromPrevious: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.category = category
        self.summary = summary
        self.wikipediaURL = wikipediaURL
        self.imageURL = imageURL
        self.mapItemIdentifier = mapItemIdentifier
        self.appleMapsRelevanceRank = appleMapsRelevanceRank
        self.rating = rating
        self.touristAttractionRank = touristAttractionRank
        self.distanceFromPrevious = distanceFromPrevious
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, category, summary
        case wikipediaURL, imageURL, mapItemIdentifier, appleMapsRelevanceRank
        case rating, touristAttractionRank, distanceFromPrevious
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        category = try container.decode(StopCategory.self, forKey: .category)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        wikipediaURL = try container.decodeIfPresent(URL.self, forKey: .wikipediaURL)
        imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        mapItemIdentifier = try container.decodeIfPresent(String.self, forKey: .mapItemIdentifier)
        appleMapsRelevanceRank = try container.decodeIfPresent(Int.self, forKey: .appleMapsRelevanceRank)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        touristAttractionRank = try container.decodeIfPresent(Int.self, forKey: .touristAttractionRank)
        distanceFromPrevious = try container.decodeIfPresent(Double.self, forKey: .distanceFromPrevious)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(category, forKey: .category)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(wikipediaURL, forKey: .wikipediaURL)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(mapItemIdentifier, forKey: .mapItemIdentifier)
        try container.encodeIfPresent(appleMapsRelevanceRank, forKey: .appleMapsRelevanceRank)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(touristAttractionRank, forKey: .touristAttractionRank)
        try container.encodeIfPresent(distanceFromPrevious, forKey: .distanceFromPrevious)
    }
}
