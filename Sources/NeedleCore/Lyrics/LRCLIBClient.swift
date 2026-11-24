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
        let duration: Double?
        let syncedLyrics: String?
    }

    private static let userAgent = "Needle/1.0 (https://github.com/local/needle)"
    private static let searchDurationTolerance: Double = 5.0

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
        switch exact {
        case .found(let lyrics):
            cache[track.id] = .hit(lyrics)
            return lyrics
        case .notFound, .transientError:
            break
        }

        let searched = await fetchViaSearch(track: track)
        switch searched {
        case .found(let lyrics):
            cache[track.id] = .hit(lyrics)
            return lyrics
        case .notFound:
            // Only cache definitive misses, never transient network/cancellation errors
            if case .notFound = exact {
                cache[track.id] = .miss
            }
            return nil
        case .transientError:
            return nil
        }
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

    private func fetchViaSearch(track: TrackInfo) async -> FetchOutcome {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        guard let url = components.url else { return .notFound }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await transport.data(for: request)
            if response.statusCode == 404 { return .notFound }
            guard response.statusCode == 200 else { return .transientError }
            let records = try JSONDecoder().decode([LRCLIBRecord].self, from: data)
            let best = records
                .compactMap { record -> (diff: Double, raw: String)? in
                    guard let raw = record.syncedLyrics, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    let diff = abs((record.duration ?? track.durationSeconds) - track.durationSeconds)
                    guard diff <= Self.searchDurationTolerance else { return nil }
                    return (diff, raw)
                }
                .min(by: { $0.diff < $1.diff })

            guard let best else { return .notFound }
            let parsed = LRCParser.parse(best.raw, trackDuration: track.durationSeconds)
            return parsed.lines.isEmpty ? .notFound : .found(parsed)
        } catch {
            return .transientError
        }
    }
}
