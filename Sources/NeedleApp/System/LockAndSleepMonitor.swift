import AppKit
import Foundation

@MainActor
final class LockAndSleepMonitor {
    private var dncObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func start(
        onLockChanged: @escaping @MainActor (Bool) -> Void,
        onSleepChanged: @escaping @MainActor (Bool) -> Void
    ) {
        stop()

        let dnc = DistributedNotificationCenter.default()
        dncObservers.append(
            dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
                Task { @MainActor in onLockChanged(true) }
            }
        )
        dncObservers.append(
            dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
                Task { @MainActor in onLockChanged(false) }
            }
        )

        let wnc = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onSleepChanged(true) }
            }
        )
        workspaceObservers.append(
            wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in onSleepChanged(false) }
            }
        )
    }

    func stop() {
        let dnc = DistributedNotificationCenter.default()
        for token in dncObservers { dnc.removeObserver(token) }
        dncObservers.removeAll()

        let wnc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { wnc.removeObserver(token) }
        workspaceObservers.removeAll()
    }
}
