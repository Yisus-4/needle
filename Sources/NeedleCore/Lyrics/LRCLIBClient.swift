import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

public actor LRCLIBClient {
    private enum CacheEntry {
        case hit(SyncedLyrics)
        case miss
    }

    private enum FetchOutcome {
        case found(SyncedLyrics)
        case notFound
        case transientError
    }

    private struct LRCLIBRecord: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let syncedLyrics: String?
    }

    private static let userAgent = "Needle/1.0 (https://github.com/local/needle)"
    private static let primaryDurationTolerance: Double = 15.0
    private static let relaxedDurationTolerance: Double = 30.0

    private let transport: any HTTPTransport
    private var cache: [String: CacheEntry] = [:]

    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    public func fetchLyrics(for track: TrackInfo) async -> SyncedLyrics? {
        if let cached = cache[track.id] {
            switch cached {
            case .hit(let lyrics): return lyrics
            case .miss: return nil
            }
        }

        let exact = await fetchExact(track: track)
        if case .found(let lyrics) = exact {
            cache[track.id] = .hit(lyrics)
            return lyrics
        }

        let strictSearch = await fetchViaSearch(
            queryItems: [
                URLQueryItem(name: "track_name", value: track.name),
                URLQueryItem(name: "artist_name", value: track.artist)
            ],
            track: track
        )
        if case .found(let lyrics) = strictSearch {
            cache[track.id] = .hit(lyrics)
            return lyrics
        }

        let cleanedName = Self.cleanTitle(track.name)
        let broadSearch = await fetchViaSearch(
            queryItems: [
                URLQueryItem(name: "q", value: "\(cleanedName) \(track.artist)")
            ],
            track: track
        )
        if case .found(let lyrics) = broadSearch {
            cache[track.id] = .hit(lyrics)
            return lyrics
        }

        // Only cache definitive misses, never transient network/cancellation errors
        if case .notFound = exact, case .notFound = strictSearch, case .notFound = broadSearch {
            cache[track.id] = .miss
        }
        return nil
    }

    private func fetchExact(track: TrackInfo) async -> FetchOutcome {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.durationSeconds.rounded())))
        ]
        guard let url = components.url else { return .notFound }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await transport.data(for: request)
            if response.statusCode == 404 { return .notFound }
            guard response.statusCode == 200 else { return .transientError }
            let record = try JSONDecoder().decode(LRCLIBRecord.self, from: data)
            guard let raw = record.syncedLyrics, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .notFound
            }
            let parsed = LRCParser.parse(raw, trackDuration: track.durationSeconds)
            return parsed.lines.isEmpty ? .notFound : .found(parsed)
        } catch {
            return .transientError
        }
    }

    private func fetchViaSearch(queryItems: [URLQueryItem], track: TrackInfo) async -> FetchOutcome {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = queryItems
        guard let url = components.url else { return .notFound }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await transport.data(for: request)
            if response.statusCode == 404 { return .notFound }
            guard response.statusCode == 200 else { return .transientError }
            let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
            let best = Self.selectBestMatch(from: records, for: track)
            guard let best else { return .notFound }
            let parsed = LRCParser.parse(best, trackDuration: track.durationSeconds)
            return parsed.lines.isEmpty ? .notFound : .found(parsed)
        } catch {
            return .transientError
        }
    }

    private static func selectBestMatch(from records: [LRCLIBRecord], for track: TrackInfo) -> String? {
        let targetAlbum = track.album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetName = cleanTitle(track.name).lowercased()
        let targetArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let candidates = records.compactMap { record -> (score: Double, raw: String)? in
            guard let raw = record.syncedLyrics, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let diff = abs((record.duration ?? track.durationSeconds) - track.durationSeconds)
            let recordName = cleanTitle(record.trackName ?? "").lowercased()
            let recordArtist = (record.artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let nameAndArtistMatch = !recordName.isEmpty && recordName == targetName && recordArtist.contains(targetArtist)

            let maxAllowed = nameAndArtistMatch ? relaxedDurationTolerance : primaryDurationTolerance
            guard diff <= maxAllowed else { return nil }

            let albumBonus: Double
            if let recAlbum = record.albumName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !targetAlbum.isEmpty, recAlbum == targetAlbum {
                albumBonus = -2.0
            } else {
                albumBonus = 0.0
            }
            return (diff + albumBonus, raw)
        }

        return candidates.min(by: { $0.score < $1.score })?.raw
    }

    private static func cleanTitle(_ title: String) -> String {
        var cleaned = title
        if let range = cleaned.range(of: #"\s*[\(\[].*?[\)\]]"#, options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let dashRange = cleaned.range(of: #"\s+-\s+.*$"#, options: .regularExpression) {
            cleaned.removeSubrange(dashRange)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
