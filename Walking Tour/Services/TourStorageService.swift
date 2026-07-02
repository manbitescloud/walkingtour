import Foundation

struct TourStorageService {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storageDirectory: URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("WalkingTour", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var savedToursFile: URL? {
        storageDirectory?.appendingPathComponent("saved_tours.json")
    }

    func loadSavedTours() -> [SavedTour] {
        guard let savedToursFile, let data = try? Data(contentsOf: savedToursFile) else { return [] }
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SavedTour].self, from: data)) ?? []
    }

    func saveTour(_ tour: SavedTour) throws {
        guard savedToursFile != nil else { return }
        var tours = loadSavedTours()
        if let index = tours.firstIndex(where: { $0.id == tour.id }) {
            tours[index] = tour
        } else {
            tours.insert(tour, at: 0)
        }
        try persist(tours)
    }

    func deleteTour(id: UUID) throws {
        guard savedToursFile != nil else { return }
        var tours = loadSavedTours()
        tours.removeAll { $0.id == id }
        try persist(tours)
    }

    func cacheLatestTour(_ tour: WalkingTour) throws {
        guard savedToursFile != nil else { return }
        let cached = SavedTour(from: tour, name: "Last Tour")
        var tours = loadSavedTours()
        tours.removeAll { $0.name == "Last Tour" }
        tours.insert(cached, at: 0)
        try persist(Array(tours.prefix(20)))
    }

    private func persist(_ tours: [SavedTour]) throws {
        guard let savedToursFile else { return }
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tours)
        try data.write(to: savedToursFile, options: .atomic)
    }
}
