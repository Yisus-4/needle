import Foundation

public struct OverlayInputs: Sendable, Equatable {
    public var isEnabled: Bool
    public var isScreenLocked: Bool
    public var isDisplayAsleep: Bool
    public var isPreviewOpen: Bool
    public var playbackState: PlaybackState

    public init(
        isEnabled: Bool,
        isScreenLocked: Bool,
        isDisplayAsleep: Bool,
        isPreviewOpen: Bool,
        playbackState: PlaybackState
    ) {
        self.isEnabled = isEnabled
        self.isScreenLocked = isScreenLocked
        self.isDisplayAsleep = isDisplayAsleep
        self.isPreviewOpen = isPreviewOpen
        self.playbackState = playbackState
    }
}

public struct OverlayDecision: Sendable, Equatable {
    public let showLockScreenOverlay: Bool
    public let shouldPollPlayer: Bool
    public let shouldAnimate: Bool

    public init(showLockScreenOverlay: Bool, shouldPollPlayer: Bool, shouldAnimate: Bool) {
        self.showLockScreenOverlay = showLockScreenOverlay
        self.shouldPollPlayer = shouldPollPlayer
        self.shouldAnimate = shouldAnimate
    }
}

public enum OverlayVisibilityPolicy {
    public static func evaluate(_ inputs: OverlayInputs) -> OverlayDecision {
        let isPlaying = inputs.playbackState == .playing
        let showLockScreen = inputs.isEnabled && inputs.isScreenLocked && !inputs.isDisplayAsleep && isPlaying
        let activePreview = inputs.isPreviewOpen && !inputs.isDisplayAsleep && isPlaying
        let shouldPoll = showLockScreen || activePreview
        let shouldAnimate = showLockScreen || activePreview
        return OverlayDecision(
            showLockScreenOverlay: showLockScreen,
            shouldPollPlayer: shouldPoll,
            shouldAnimate: shouldAnimate
        )
    }
}

public enum KeepAwakeMode: Sendable, Equatable {
    case systemDefault
    case minutes(Int)
    case whilePlaying

    public var timeoutSeconds: TimeInterval? {
        switch self {
        case .systemDefault: return 0
        case .minutes(let m): return TimeInterval(max(1, m) * 60)
        case .whilePlaying: return nil
        }
    }
}

public enum DisplayAwakePolicy {
    public static func shouldKeepDisplayAwake(
        mode: KeepAwakeMode,
        isShowingLockOverlay: Bool,
        elapsedLockedSeconds: TimeInterval,
        isOnACPower: Bool,
        onlyOnACPower: Bool
    ) -> Bool {
        guard isShowingLockOverlay else { return false }
        if onlyOnACPower && !isOnACPower { return false }
        switch mode {
        case .systemDefault:
            return false
        case .minutes(let m):
            return elapsedLockedSeconds < TimeInterval(max(1, m) * 60)
        case .whilePlaying:
            return true
        }
    }
}
