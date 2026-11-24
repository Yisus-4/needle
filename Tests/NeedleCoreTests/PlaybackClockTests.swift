import Foundation
@testable import NeedleCore

func registerPlaybackClockTests(_ runner: TestRunner) {
    let sampleTrack = TrackInfo(
        id: "spotify:track:1",
        name: "Instant Crush",
        artist: "Daft Punk",
        album: "RAM",
        durationSeconds: 337,
        artworkURL: nil
    )

    runner.add("PlaybackClockTests", "advancesSmoothlyWhilePlaying") {
        var clock = PlaybackClock()
        clock.sync(with: PlaybackSnapshot(state: .playing, positionSeconds: 10.0, track: sampleTrack, sampledAt: 100.0))
        try expectClose(clock.currentPosition(at: 101.25), 11.25, accuracy: 0.001)
    }

    runner.add("PlaybackClockTests", "freezesPositionWhilePaused") {
        var clock = PlaybackClock()
        clock.sync(with: PlaybackSnapshot(state: .paused, positionSeconds: 10.0, track: sampleTrack, sampledAt: 100.0))
        try expectClose(clock.currentPosition(at: 105.0), 10.0, accuracy: 0.001)
    }

    runner.add("PlaybackClockTests", "smallDriftPreservesSmoothClockLargeDriftSnaps") {
        var clock = PlaybackClock()
        clock.sync(with: PlaybackSnapshot(state: .playing, positionSeconds: 10.0, track: sampleTrack, sampledAt: 100.0))
        // Predicted at t=102 is 12.0; sample says 12.15 (drift 0.15 <= 0.35) -> preserve smooth anchor
        clock.sync(with: PlaybackSnapshot(state: .playing, positionSeconds: 12.15, track: sampleTrack, sampledAt: 102.0))
        try expectClose(clock.currentPosition(at: 102.0), 12.0, accuracy: 0.001)

        // Scrub to 45.0 (drift > 0.35) -> snap immediately
        clock.sync(with: PlaybackSnapshot(state: .playing, positionSeconds: 45.0, track: sampleTrack, sampledAt: 103.0))
        try expectClose(clock.currentPosition(at: 103.5), 45.5, accuracy: 0.001)
    }
}
