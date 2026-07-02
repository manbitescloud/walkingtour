import Foundation

enum TourTheme: String, CaseIterable, Identifiable, Codable {
    case highlights
    case history
    case architecture
    case nature
    case foodie
    case culture

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highlights: "Highlights"
        case .history: "History"
        case .architecture: "Architecture"
        case .nature: "Nature"
        case .foodie: "Foodie"
        case .culture: "Culture"
        }
    }

    var icon: String {
        switch self {
        case .highlights: "star.fill"
        case .history: "clock.arrow.circlepath"
        case .architecture: "building.columns.fill"
        case .nature: "leaf.fill"
        case .foodie: "fork.knife"
        case .culture: "theatermasks.fill"
        }
    }

    var description: String {
        switch self {
        case .highlights: "A balanced mix of notable local spots"
        case .history: "Historic sites, monuments, and stories"
        case .architecture: "Landmarks and distinctive buildings"
        case .nature: "Parks, gardens, and green spaces"
        case .foodie: "Culinary highlights with food and coffee stops"
        case .culture: "Museums, galleries, and cultural venues"
        }
    }

    var preferredCategories: [StopCategory] {
        switch self {
        case .highlights: [.landmark, .museum, .historic, .park]
        case .history: [.historic, .landmark, .museum]
        case .architecture: [.landmark, .historic]
        case .nature: [.park]
        case .foodie: [.food, .coffee, .landmark]
        case .culture: [.museum, .historic, .landmark]
        }
    }

    var keywordBoosts: [String] {
        switch self {
        case .highlights: ["monument", "famous", "historic", "park"]
        case .history: ["historic", "war", "century", "memorial", "heritage", "revolution"]
        case .architecture: ["building", "cathedral", "church", "tower", "bridge", "palace", "architecture"]
        case .nature: ["park", "garden", "trail", "river", "lake", "forest", "nature"]
        case .foodie: ["market", "restaurant", "cafe", "food", "bakery", "brewery"]
        case .culture: ["museum", "gallery", "art", "theater", "theatre", "cultural", "exhibit"]
        }
    }

    var defaultIncludeFood: Bool {
        self == .foodie
    }

    var defaultIncludeCoffee: Bool {
        self == .foodie
    }
}

extension Array where Element == TourTheme {
    var displayLabel: String {
        let sorted = map(\.label).sorted()
        if sorted.isEmpty { return TourTheme.highlights.label }
        if sorted.count == 1 { return sorted[0] }
        if sorted.count == 2 { return sorted.joined(separator: " & ") }
        return "\(sorted.prefix(2).joined(separator: ", ")) +\(sorted.count - 2)"
    }

    var combinedPreferredCategories: [StopCategory] {
        if isEmpty { return TourTheme.highlights.preferredCategories }
        var categories: [StopCategory] = []
        for theme in self {
            for category in theme.preferredCategories where !categories.contains(category) {
                categories.append(category)
            }
        }
        return categories
    }

    func matches(stop: TourStop) -> Bool {
        let active = Set(self)
        if active.isEmpty || active == [.highlights] { return true }
        let focused = active.filter { $0 != .highlights }
        if focused.isEmpty { return true }
        let text = (stop.name + " " + stop.summary).lowercased()
        return focused.contains { theme in
            theme.preferredCategories.contains(stop.category)
                || theme.keywordBoosts.contains { text.contains($0) }
        }
    }

    func score(for stop: TourStop) -> Double {
        let themes = isEmpty ? [TourTheme.highlights] : self
        return themes.map { theme in
            var value: Double = 1
            if let attractionRank = stop.touristAttractionRank {
                value += Double(11 - Swift.min(attractionRank, 10)) * 2.5
            }
            if stop.wikipediaURL != nil { value += 2 }
            if stop.imageURL != nil { value += 1 }
            if let rating = stop.rating { value += rating }
            if theme.preferredCategories.contains(stop.category) { value += 2 }
            let text = (stop.name + " " + stop.summary).lowercased()
            for keyword in theme.keywordBoosts where text.contains(keyword) {
                value += 1.5
            }
            if WikipediaNotabilityFilter.isJunkName(stop.name) {
                value -= 4
            }
            switch stop.category {
            case .landmark, .historic, .museum: value += 1
            case .park: value += theme == .nature ? 2 : 0.5
            case .food, .coffee: value += theme == .foodie ? 2 : 0
            default: break
            }
            return value
        }.max() ?? 1
    }
}
