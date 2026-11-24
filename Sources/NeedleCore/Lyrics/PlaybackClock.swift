import Foundation

public struct PlaybackClock: Sendable {
    private static let driftThresholdSeconds: TimeInterval = 0.35

    private var basePosition: TimeInterval = 0
    private var anchorTime: TimeInterval = 0
    private var state: PlaybackState = .stopped
    private var trackID: String?

    public init() {}

    public mutating func sync(with snapshot: PlaybackSnapshot) {
        let sameTrack = (snapshot.track?.id == trackID && trackID != nil)
        if sameTrack && state == .playing && snapshot.state == .playing {
            let predicted = currentPosition(at: snapshot.sampledAt)
            if abs(predicted - snapshot.positionSeconds) <= Self.driftThresholdSeconds {
                return
            }
        }
        basePosition = max(0, snapshot.positionSeconds)
        anchorTime = snapshot.sampledAt
        state = snapshot.state
        trackID = snapshot.track?.id
    }

    public func currentPosition(at now: TimeInterval) -> TimeInterval {
        guard state == .playing else { return basePosition }
        return max(0, basePosition + max(0, now - anchorTime))
    }
}
