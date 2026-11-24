import Foundation
@testable import NeedleCore

private actor MockHTTPTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(_ handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try await handler(request)
    }

    func requestCount() -> Int { requests.count }
    func recordedRequests() -> [URLRequest] { requests }
}

func registerLRCLIBClientTests(_ runner: TestRunner) {
    runner.add("LRCLIBClientTests", "exactGetReturnsParsedLyricsAndCachesByTrackID") {
        let transport = MockHTTPTransport { req in
            let body = #"{"syncedLyrics":"[00:05.00] Hello world\n[00:08.00] Second line"}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, resp)
        }
        let client = LRCLIBClient(transport: transport)
        let track = TrackInfo(
            id: "spotify:track:abc",
            name: "Hello",
            artist: "Artist",
            album: "Album",
            durationSeconds: 214.4,
            artworkURL: nil
        )

        let first = await client.fetchLyrics(for: track)
        let second = await client.fetchLyrics(for: track)

        try expect(first != nil, "expected synced lyrics")
        try expectEqual(first, second)
        try expectEqual(await transport.requestCount(), 1, "should cache by track id")

        let req = try expectUnwrap(await transport.recordedRequests().first)
        try expect(req.value(forHTTPHeaderField: "User-Agent")?.contains("Needle") == true, "User-Agent set")
        try expect(req.url?.absoluteString.contains("duration=214") == true, "duration in rounded seconds")
    }

    runner.add("LRCLIBClientTests", "fallsBackToSearchAndPicksClosestDurationWithin5Seconds") {
        let transport = MockHTTPTransport { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/api/get") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (Data(), resp)
            }
            let json = """
            [
              {"duration": 240, "syncedLyrics": "[00:01.00] Wrong version"},
              {"duration": 212, "syncedLyrics": "[00:02.00] Right version"}
            ]
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (json, resp)
        }
        let client = LRCLIBClient(transport: transport)
        let track = TrackInfo(
            id: "spotify:track:special",
            name: #"Rock & Roll "Live""#,
            artist: "AC/DC & Friends",
            album: "Álbum",
            durationSeconds: 214,
            artworkURL: nil
        )

        let lyrics = await client.fetchLyrics(for: track)
        try expectEqual(lyrics?.lines.first?.text, "Right version")
        try expectEqual(await transport.requestCount(), 2)
    }

    runner.add("LRCLIBClientTests", "returnsNilGracefullyOnNetworkFailure") {
        let transport = MockHTTPTransport { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = LRCLIBClient(transport: transport)
        let track = TrackInfo(id: "spotify:track:offline", name: "Offline", artist: "None", album: "None", durationSeconds: 180, artworkURL: nil)
        let lyrics = await client.fetchLyrics(for: track)
        try expect(lyrics == nil, "offline should return nil gracefully")
    }
}

private func expectUnwrap<T>(_ value: T?, file: String = #fileID, line: Int = #line) throws -> T {
    guard let value else {
        throw TestFailure(description: "\(file):\(line): unexpected nil")
    }
    return value
}
