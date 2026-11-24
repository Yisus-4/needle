import Foundation
@testable import NeedleCore

func registerOverlayVisibilityPolicyTests(_ runner: TestRunner) {
    runner.add("OverlayVisibilityPolicyTests", "showsOverlayOnlyWhenEnabledLockedAwakeAndPlaying") {
        let decision = OverlayVisibilityPolicy.evaluate(OverlayInputs(
            isEnabled: true,
            isScreenLocked: true,
            isDisplayAsleep: false,
            isPreviewOpen: false,
            playbackState: .playing
        ))
        try expectEqual(decision, OverlayDecision(showLockScreenOverlay: true, shouldPollPlayer: true, shouldAnimate: true))
    }

    runner.add("OverlayVisibilityPolicyTests", "hidesAndSuspendsWhenDisplaySleepsOrPausedOrUnlocked") {
        let asleep = OverlayVisibilityPolicy.evaluate(OverlayInputs(
            isEnabled: true,
            isScreenLocked: true,
            isDisplayAsleep: true,
            isPreviewOpen: false,
            playbackState: .playing
        ))
        try expectEqual(asleep, OverlayDecision(showLockScreenOverlay: false, shouldPollPlayer: false, shouldAnimate: false))

        let paused = OverlayVisibilityPolicy.evaluate(OverlayInputs(
            isEnabled: true,
            isScreenLocked: true,
            isDisplayAsleep: false,
            isPreviewOpen: false,
            playbackState: .paused
        ))
        try expectEqual(paused, OverlayDecision(showLockScreenOverlay: false, shouldPollPlayer: false, shouldAnimate: false))

        let unlocked = OverlayVisibilityPolicy.evaluate(OverlayInputs(
            isEnabled: true,
            isScreenLocked: false,
            isDisplayAsleep: false,
            isPreviewOpen: false,
            playbackState: .playing
        ))
        try expectEqual(unlocked, OverlayDecision(showLockScreenOverlay: false, shouldPollPlayer: false, shouldAnimate: false))

        let preview = OverlayVisibilityPolicy.evaluate(OverlayInputs(
            isEnabled: false,
            isScreenLocked: false,
            isDisplayAsleep: false,
            isPreviewOpen: true,
            playbackState: .playing
        ))
        try expectEqual(preview, OverlayDecision(showLockScreenOverlay: false, shouldPollPlayer: true, shouldAnimate: true))
    }

    runner.add("OverlayVisibilityPolicyTests", "spotifyOutputParserConvertsDurationMsToSecondsAndHandlesSpecialChars") {
        let sep = "\u{1F}"
        let raw = [
            "playing",
            "42.5",
            "spotify:track:1",
            #"Rock & Roll "Live""#,
            "AC/DC",
            "Álbum",
            "214000",
            "https://i.scdn.co/image/abc"
        ].joined(separator: sep)

        let snap = SpotifyOutputParser.parse(delimitedOutput: raw, sampledAt: 1000.0)
        try expectEqual(snap.state, .playing)
        try expectClose(snap.positionSeconds, 42.5, accuracy: 0.001)
        try expectEqual(snap.track?.id, "spotify:track:1")
        try expectEqual(snap.track?.name, #"Rock & Roll "Live""#)
        try expectEqual(snap.track?.artist, "AC/DC")
        try expectEqual(snap.track?.album, "Álbum")
        try expectClose(snap.track?.durationSeconds ?? 0, 214.0, accuracy: 0.001)
        try expectEqual(snap.track?.artworkURL?.absoluteString, "https://i.scdn.co/image/abc")
    }

    runner.add("OverlayVisibilityPolicyTests", "spotifyOutputParserRejectsMissingValueAndNonHTTPSArtworkURL") {
        let sep = "\u{1F}"
        let missingRaw = ["playing", "10.0", "id1", "Song", "Art", "Alb", "180000", "missing value"].joined(separator: sep)
        let missingSnap = SpotifyOutputParser.parse(delimitedOutput: missingRaw, sampledAt: 1.0)
        try expect(missingSnap.track?.artworkURL == nil, "missing value must parse as nil")

        let httpRaw = ["playing", "10.0", "id2", "Song", "Art", "Alb", "180000", "http://insecure.example/cover.jpg"].joined(separator: sep)
        let httpSnap = SpotifyOutputParser.parse(delimitedOutput: httpRaw, sampledAt: 1.0)
        try expect(httpSnap.track?.artworkURL == nil, "non-https artwork URL must be rejected")
    }
}
