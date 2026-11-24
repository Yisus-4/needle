import AppKit
import Foundation
import NeedleCore

public final class SpotifyProvider: MediaPlayerProvider, @unchecked Sendable {
    public let playerName = "Spotify"
    private let lock = NSLock()
    private let scriptQueue = DispatchQueue(label: "com.local.needle.spotify.applescript", qos: .userInitiated)
    private var observer: NSObjectProtocol?

    private static let appleScriptSource = """
    tell application "Spotify"
        set pState to player state as string
        if pState is "stopped" then
            return "stopped"
        end if
        set pPos to player position as string
        set tId to id of current track as string
        set tName to name of current track as string
        set tArtist to artist of current track as string
        set tAlbum to album of current track as string
        set tDur to duration of current track as string
        set tArt to artwork url of current track as string
        set sep to character id 31
        return pState & sep & pPos & sep & tId & sep & tName & sep & tArtist & sep & tAlbum & sep & tDur & sep & tArt
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

        // Serialize NSAppleScript execution on a dedicated queue (OpenScripting is not thread-safe)
        return await withCheckedContinuation { continuation in
            scriptQueue.async {
                guard let script = NSAppleScript(source: Self.appleScriptSource) else {
                    continuation.resume(returning: .stopped(at: ProcessInfo.processInfo.systemUptime))
                    return
                }
                var errorDict: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorDict)
                let sampleTime = ProcessInfo.processInfo.systemUptime
                guard errorDict == nil, let output = descriptor.stringValue else {
                    continuation.resume(returning: .stopped(at: sampleTime))
                    return
                }
                continuation.resume(returning: SpotifyOutputParser.parse(delimitedOutput: output, sampledAt: sampleTime))
            }
        }
    }
}
