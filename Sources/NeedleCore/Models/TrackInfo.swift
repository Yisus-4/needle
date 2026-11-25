import Foundation

public enum PlaybackState: String, Sendable, Equatable {
    case playing
    case paused
    case stopped
}

public struct TrackInfo: Sendable, Equatable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String
    public let durationSeconds: Double
    public let artworkURL: URL?

    public init(
        id: String,
        name: String,
        artist: String,
        album: String,
        durationSeconds: Double,
        artworkURL: URL?
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.artworkURL = artworkURL
    }
}

public struct PlaybackSnapshot: Sendable, Equatable {
    public let state: PlaybackState
    public let positionSeconds: Double
    public let track: TrackInfo?
    public let sampledAt: TimeInterval

    public init(
        state: PlaybackState,
        positionSeconds: Double,
        track: TrackInfo?,
        sampledAt: TimeInterval
    ) {
        self.state = state
        self.positionSeconds = positionSeconds
        self.track = track
        self.sampledAt = sampledAt
    }

    public static func stopped(at sampledAt: TimeInterval) -> PlaybackSnapshot {
        PlaybackSnapshot(state: .stopped, positionSeconds: 0, track: nil, sampledAt: sampledAt)
    }
}
