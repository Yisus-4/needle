import Foundation

public protocol MediaPlayerProvider: Sendable {
    var playerName: String { get }
    func startObserving(_ onChange: @escaping @Sendable () -> Void)
    func stopObserving()
    func fetchSnapshot() async -> PlaybackSnapshot
}

public enum SpotifyOutputParser {
    public static let delimiter = "\u{1F}"

    public static func parse(delimitedOutput: String, sampledAt: TimeInterval) -> PlaybackSnapshot {
        let trimmed = delimitedOutput.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return .stopped(at: sampledAt) }

        let parts = trimmed.components(separatedBy: delimiter)
        guard parts.count >= 8 else { return .stopped(at: sampledAt) }

        let stateStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let state: PlaybackState
        switch stateStr {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .stopped
        }

        // AppleScript may format decimals with comma in some locales
        let posRaw = parts[1].replacingOccurrences(of: ",", with: ".")
        let positionSeconds = Double(posRaw) ?? 0

        let trackID = parts[2]
        let name = parts[3]
        let artist = parts[4]
        let album = parts[5]
        let durRaw = parts[6].replacingOccurrences(of: ",", with: ".")
        let durationMs = Double(durRaw) ?? 0
        let durationSeconds = durationMs > 1000 ? durationMs / 1000.0 : durationMs
        let artworkURL = URL(string: parts[7].trimmingCharacters(in: .whitespacesAndNewlines))

        guard !trackID.isEmpty, !name.isEmpty else {
            return PlaybackSnapshot(state: state, positionSeconds: positionSeconds, track: nil, sampledAt: sampledAt)
        }

        let track = TrackInfo(
            id: trackID,
            name: name,
            artist: artist,
            album: album,
            durationSeconds: durationSeconds,
            artworkURL: artworkURL
        )
        return PlaybackSnapshot(
            state: state,
            positionSeconds: positionSeconds,
            track: track,
            sampledAt: sampledAt
        )
    }
}
