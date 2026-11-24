import AppKit
import Foundation
import NeedleCore

public final class SpotifyProvider: MediaPlayerProvider, @unchecked Sendable {
    public let playerName = "Spotify"
    private let lock = NSLock()
    private var observer: NSObjectProtocol?

    private static let appleScriptSource = """
    tell application "Spotify"
        set st to player state as string
        set pos to player position as string
        if st is "stopped" then
            return "stopped"
        end if
        set tId to id of current track as string
        set tName to name of current track as string
        set tArtist to artist of current track as string
        set tAlbum to album of current track as string
        set tDur to duration of current track as string
        set tArt to artwork url of current track as string
        set sep to character id 31
        return st & sep & pos & sep & tId & sep & tName & sep & tArtist & sep & tAlbum & sep & tDur & sep & tArt
    end tell
    """

    public init() {}

    public func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        stopObserving()
        let token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: nil
        ) { _ in
            onChange()
        }
        lock.withLock {
            observer = token
        }
    }

    public func stopObserving() {
        let token: NSObjectProtocol? = lock.withLock {
            defer { observer = nil }
            return observer
        }
        if let token {
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }

    public func fetchSnapshot() async -> PlaybackSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
        guard isRunning else {
            return .stopped(at: now)
        }

        return await Task.detached(priority: .userInitiated) {
            let sampleTime = ProcessInfo.processInfo.systemUptime
            guard let script = NSAppleScript(source: Self.appleScriptSource) else {
                return .stopped(at: sampleTime)
            }
            var errorDict: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorDict)
            guard errorDict == nil, let output = descriptor.stringValue else {
                return .stopped(at: sampleTime)
            }
            return SpotifyOutputParser.parse(delimitedOutput: output, sampledAt: sampleTime)
        }.value
    }
}
