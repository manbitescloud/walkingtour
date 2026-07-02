import CoreLocation
import Foundation
import MapKit

/// Loads curated See / Eat / Drink listings from Wikivoyage district guides near a coordinate.
struct WikivoyageService {
    private let session: URLSession
    private let apiBase = "https://en.wikivoyage.org/w/api.php"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func recommendedStops(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        includeSightseeing: Bool = true,
        includeFood: Bool = false,
        includeCoffee: Bool = false,
        limit: Int = 20
    ) async -> [TourStop] {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return [] }

        let pages = await nearbyGuidePages(coordinate: coordinate, radiusMeters: radiusMeters, limit: 8)
        guard !pages.isEmpty else { return [] }

        var listings: [ParsedListing] = []
        for page in pages {
            guard let wikitext = await fetchWikitext(title: page.title) else { continue }
            listings.append(contentsOf: parseListings(from: wikitext, pageTitle: page.title))
        }

        let allowedSections = allowedSections(
            includeSightseeing: includeSightseeing,
            includeFood: includeFood,
            includeCoffee: includeCoffee
        )
        listings = listings.filter { allowedSections.contains($0.section) }
        if includeCoffee, !includeFood {
            listings = listings.filter { listing in
                listing.section != .eat || isCoffeeRelated(listing)
            }
        }
        if includeCoffee {
            listings = listings.filter { listing in
                listing.section != .drink || isCoffeeRelated(listing)
            }
        }

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var stops: [TourStop] = []
        var usedNames: Set<String> = []

        for (index, listing) in listings.enumerated() {
            guard let name = listing.displayName,
                  !WikipediaNotabilityFilter.isJunkName(name) else { continue }

            let key = name.lowercased()
            guard !usedNames.contains(key) else { continue }

            let resolvedCoordinate: CLLocationCoordinate2D?
            if let lat = listing.latitude, let lon = listing.longitude, CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                resolvedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                resolvedCoordinate = await geocodeListing(listing, near: coordinate)
            }

            guard let stopCoordinate = resolvedCoordinate else { continue }
            let distance = origin.distance(from: CLLocation(latitude: stopCoordinate.latitude, longitude: stopCoordinate.longitude))
            guard distance <= Double(radiusMeters) + 750 else { continue }

            let category = category(for: listing)
            if listing.section == .drink, category == .other { continue }

            let summary = listing.content.isEmpty
                ? "Featured in the Wikivoyage guide for \(pageLabel(listing.pageTitle))."
                : listing.content

            var wikipediaURL: URL?
            if let wikiTitle = listing.wikipediaTitle {
                wikipediaURL = URL(string: "https://en.wikipedia.org/wiki/\(wikiTitle.replacingOccurrences(of: " ", with: "_"))")
            }

            let rank = min(index + 1, 10)
            stops.append(
                TourStop(
                    name: name,
                    coordinate: stopCoordinate,
                    category: category,
                    summary: summary,
                    wikipediaURL: wikipediaURL,
                    touristAttractionRank: rank,
                    distanceFromPrevious: nil
                )
            )
            usedNames.insert(key)
            if stops.count >= limit { break }
        }

        return stops
    }

    // MARK: - Page discovery

    private struct GuidePage {
        let title: String
        let distanceMeters: Double
    }

    private func nearbyGuidePages(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int
    ) async -> [GuidePage] {
        guard var components = URLComponents(string: apiBase) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "geosearch"),
            URLQueryItem(name: "gscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "gsradius", value: "\(min(max(radiusMeters, 500), 10_000))"),
            URLQueryItem(name: "gslimit", value: "\(max(limit, 10))"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let results = query["geosearch"] as? [[String: Any]] else {
            return []
        }

        let pages = results.compactMap { item -> GuidePage? in
            guard let title = item["title"] as? String else { return nil }
            let distance = item["dist"] as? Double ?? .greatestFiniteMagnitude
            return GuidePage(title: title, distanceMeters: distance)
        }

        return pages
            .sorted { lhs, rhs in
                let lhsDistrict = lhs.title.contains("/")
                let rhsDistrict = rhs.title.contains("/")
                if lhsDistrict != rhsDistrict { return lhsDistrict && !rhsDistrict }
                return lhs.distanceMeters < rhs.distanceMeters
            }
            .prefix(limit)
            .map { $0 }
    }

    private func fetchWikitext(title: String) async -> String? {
        guard var components = URLComponents(string: apiBase) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "prop", value: "wikitext"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parse = json["parse"] as? [String: Any],
              let wikitext = parse["wikitext"] as? [String: Any],
              let text = wikitext["*"] as? String else {
            return nil
        }

        return text
    }

    // MARK: - Wikitext parsing

    private enum ListingSection: String {
        case see
        case doActivity = "do"
        case eat
        case drink

        var isSightseeing: Bool {
            self == .see || self == .doActivity
        }
    }

    private struct ParsedListing {
        let pageTitle: String
        let section: ListingSection
        let displayName: String?
        let latitude: Double?
        let longitude: Double?
        let content: String
        let wikipediaTitle: String?
        let address: String?
    }

    private func parseListings(from wikitext: String, pageTitle: String) -> [ParsedListing] {
        let templatePattern = #"\{\{(see|do|eat|drink|listing)\b([\s\S]*?)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: templatePattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(wikitext.startIndex..<wikitext.endIndex, in: wikitext)
        let matches = regex.matches(in: wikitext, options: [], range: range)

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let typeRange = Range(match.range(at: 1), in: wikitext),
                  let bodyRange = Range(match.range(at: 2), in: wikitext) else {
                return nil
            }

            let templateType = wikitext[typeRange].lowercased()
            let body = String(wikitext[bodyRange])
            let params = parseTemplateParameters(body)

            let section: ListingSection?
            if templateType == "listing" {
                switch params["type"]?.lowercased() {
                case "see": section = .see
                case "do": section = .doActivity
                case "eat": section = .eat
                case "drink": section = .drink
                default: section = nil
                }
            } else if templateType == "do" {
                section = .doActivity
            } else {
                section = ListingSection(rawValue: templateType)
            }

            guard let section else { return nil }

            let name = params["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let alt = params["alt"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name : alt)

            return ParsedListing(
                pageTitle: pageTitle,
                section: section,
                displayName: displayName,
                latitude: parseCoordinate(params["lat"] ?? params["latitude"]),
                longitude: parseCoordinate(params["long"] ?? params["lon"] ?? params["longitude"]),
                content: cleanWikiText(params["content"] ?? ""),
                wikipediaTitle: params["wikipedia"],
                address: params["address"]
            )
        }
    }

    private func parseTemplateParameters(_ body: String) -> [String: String] {
        var params: [String: String] = [:]

        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)

            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            params[key] = value
        }

        // Handle single-line templates: {{see | name=X | lat=Y | long=Z }}
        if params.isEmpty, body.contains("|") {
            let inline = body.split(separator: "|", omittingEmptySubsequences: false)
            for part in inline {
                let segment = part.trimmingCharacters(in: .whitespaces)
                guard let equalsIndex = segment.firstIndex(of: "=") else { continue }
                let key = String(segment[..<equalsIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(segment[segment.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
                params[key] = value
            }
        }

        return params
    }

    private func parseCoordinate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private func cleanWikiText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "'''", with: "")
            .replacingOccurrences(of: "''", with: "")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\[\[([^|\]]+)\|([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{[^}]+\}\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Categorization & geocoding

    private func allowedSections(
        includeSightseeing: Bool,
        includeFood: Bool,
        includeCoffee: Bool
    ) -> Set<ListingSection> {
        var sections = Set<ListingSection>()
        if includeSightseeing {
            sections.formUnion([.see, .doActivity])
        }
        if includeFood {
            sections.insert(.eat)
        }
        if includeCoffee {
            sections.formUnion([.drink, .eat])
        }
        return sections
    }

    private func category(for listing: ParsedListing) -> StopCategory {
        let text = ((listing.displayName ?? "") + " " + listing.content).lowercased()

        switch listing.section {
        case .eat:
            if text.contains("coffee") || text.contains("café") || text.contains("cafe") || text.contains("espresso") {
                return .coffee
            }
            return .food
        case .drink:
            if isCoffeeRelated(listing) { return .coffee }
            return .other
        case .see, .doActivity:
            if text.contains("museum") || text.contains("gallery") { return .museum }
            if text.contains("park") || text.contains("garden") { return .park }
            if text.contains("church") || text.contains("cathedral") || text.contains("historic") { return .historic }
            if text.contains("monument") || text.contains("memorial") || text.contains("tower") { return .landmark }
            return .landmark
        }
    }

    private func geocodeListing(_ listing: ParsedListing, near coordinate: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        guard let name = listing.displayName else { return nil }

        var query = name
        if let address = listing.address, !address.isEmpty {
            query = "\(name), \(address)"
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 8_000,
            longitudinalMeters: 8_000
        )

        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else {
            return nil
        }

        let resolved = item.location.coordinate
        return CLLocationCoordinate2DIsValid(resolved) ? resolved : nil
    }

    private func pageLabel(_ title: String) -> String {
        title.split(separator: "/").last.map(String.init) ?? title
    }

    private func isCoffeeRelated(_ listing: ParsedListing) -> Bool {
        let text = ((listing.displayName ?? "") + " " + listing.content).lowercased()
        return text.contains("coffee") || text.contains("café") || text.contains("cafe")
            || text.contains("espresso") || text.contains("roaster") || text.contains("bakery")
    }
}
