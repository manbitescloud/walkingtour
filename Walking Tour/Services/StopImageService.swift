import CoreLocation
import Foundation

struct StopImageService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func imageURL(for stop: TourStop) async -> URL? {
        if let imageURL = stop.imageURL {
            return imageURL
        }

        if let wikipediaURL = stop.wikipediaURL {
            if let title = wikipediaTitle(from: wikipediaURL),
               let thumbnail = await fetchThumbnail(title: title) {
                return thumbnail
            }
        }

        return await fetchThumbnail(title: stop.name)
    }

    func enrichStops(_ stops: [TourStop]) async -> [TourStop] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, stop) in stops.enumerated() where stop.imageURL == nil {
                group.addTask {
                    (index, await self.imageURL(for: stop))
                }
            }

            var updated = stops
            for await (index, url) in group {
                guard let url else { continue }
                updated[index].imageURL = url
            }
            return updated
        }
    }

    private func wikipediaTitle(from url: URL) -> String? {
        guard url.host?.contains("wikipedia.org") == true else { return nil }
        let slug = url.path.split(separator: "/").last.map(String.init) ?? ""
        guard !slug.isEmpty else { return nil }
        return slug.replacingOccurrences(of: "_", with: " ")
    }

    private func fetchThumbnail(title: String) async -> URL? {
        guard var components = URLComponents(string: "https://en.wikipedia.org/w/api.php") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "640"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(WikipediaThumbnailResponse.self, from: data)
            return response.query.pages.values.compactMap(\.thumbnail?.source).first
        } catch {
            return nil
        }
    }
}

private struct WikipediaThumbnailResponse: Decodable {
    let query: WikipediaThumbnailQuery
}

private struct WikipediaThumbnailQuery: Decodable {
    let pages: [String: WikipediaThumbnailPage]
}

private struct WikipediaThumbnailPage: Decodable {
    let thumbnail: WikipediaThumbnail?
}

private struct WikipediaThumbnail: Decodable {
    let source: URL
}
