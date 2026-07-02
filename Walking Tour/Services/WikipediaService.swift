import CoreLocation
import Foundation

struct WikipediaService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func nearbyArticles(
        coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        limit: Int = 15,
        themes: [TourTheme] = [.highlights]
    ) async throws -> [TourStop] {
        guard var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "geosearch"),
            URLQueryItem(name: "gscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "gsradius", value: "\(min(radiusMeters, 10_000))"),
            URLQueryItem(name: "gslimit", value: "\(limit)"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(WikipediaGeoSearchResponse.self, from: data)

        return await withTaskGroup(of: TourStop?.self) { group in
            for article in response.query.geosearch {
                group.addTask {
                    try? await self.enrichedStop(from: article)
                }
            }

            var stops: [TourStop] = []
            for await stop in group {
                if let stop { stops.append(stop) }
            }
            return stops
                .filter { themes.matches(stop: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func enrichedStop(from article: WikipediaGeoArticle) async throws -> TourStop {
        let summary = try await fetchSummary(pageID: article.pageid)
        let category = categorize(title: article.title, summary: summary.extract)

        return TourStop(
            name: article.title,
            coordinate: CLLocationCoordinate2D(latitude: article.lat, longitude: article.lon),
            category: category,
            summary: summary.extract,
            wikipediaURL: summary.contentURLs?.desktop?.page.flatMap(URL.init(string:)),
            imageURL: summary.thumbnailURL
        )
    }

    private func fetchSummary(pageID: Int) async throws -> WikipediaSummary {
        guard var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts|info|pageimages"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "pageids", value: "\(pageID)"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(WikipediaPageResponse.self, from: data)
        guard let page = response.query.pages.values.first else {
            throw URLError(.badServerResponse)
        }

        return WikipediaSummary(
            extract: page.extract ?? "No description available.",
            contentURLs: WikipediaContentURLs(desktop: WikipediaDesktopURL(page: page.fullurl)),
            thumbnailURL: page.thumbnail?.source
        )
    }

    private func categorize(title: String, summary: String) -> StopCategory {
        let text = (title + " " + summary).lowercased()
        if text.contains("museum") || text.contains("gallery") { return .museum }
        if text.contains("park") || text.contains("garden") { return .park }
        if text.contains("church") || text.contains("cathedral") || text.contains("historic") { return .historic }
        if text.contains("monument") || text.contains("memorial") || text.contains("tower") { return .landmark }
        return .other
    }

    func summaryForTitle(_ title: String) async -> WikipediaArticleSummary? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts|info|pageimages"),
            URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "titles", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(WikipediaPageResponse.self, from: data)
            guard let page = response.query.pages.values.first,
                  page.missing == nil,
                  let extract = page.extract,
                  !extract.isEmpty else {
                return nil
            }

            return WikipediaArticleSummary(
                extract: extract,
                url: page.fullurl.flatMap(URL.init(string:)),
                thumbnailURL: page.thumbnail?.source
            )
        } catch {
            return nil
        }
    }

    func mobilePageURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if components.host == "en.wikipedia.org" {
            components.host = "en.m.wikipedia.org"
        }
        return components.url ?? url
    }

    func mobilePageURL(title: String) -> URL? {
        let pathTitle = title.replacingOccurrences(of: " ", with: "_")
        var components = URLComponents()
        components.scheme = "https"
        components.host = "en.m.wikipedia.org"
        components.path = "/wiki/\(pathTitle)"
        return components.url
    }
}

// MARK: - API Models

private struct WikipediaGeoSearchResponse: Decodable {
    let query: WikipediaGeoQuery
}

private struct WikipediaGeoQuery: Decodable {
    let geosearch: [WikipediaGeoArticle]
}

private struct WikipediaGeoArticle: Decodable {
    let pageid: Int
    let title: String
    let lat: Double
    let lon: Double
}

private struct WikipediaPageResponse: Decodable {
    let query: WikipediaPageQuery
}

private struct WikipediaPageQuery: Decodable {
    let pages: [String: WikipediaPage]
}

struct WikipediaArticleSummary {
    let extract: String
    let url: URL?
    let thumbnailURL: URL?
}

private struct WikipediaPage: Decodable {
    let extract: String?
    let fullurl: String?
    let thumbnail: WikipediaThumbnail?
    let missing: String?
}

private struct WikipediaThumbnail: Decodable {
    let source: URL
}

private struct WikipediaSummary {
    let extract: String
    let contentURLs: WikipediaContentURLs?
    let thumbnailURL: URL?
}

private struct WikipediaContentURLs: Decodable {
    let desktop: WikipediaDesktopURL?
}

private struct WikipediaDesktopURL: Decodable {
    let page: String?
}
