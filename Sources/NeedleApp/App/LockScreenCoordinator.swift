import AppKit
import Foundation
import NeedleCore
import SwiftUI

@MainActor
final class LockScreenCoordinator {
    var onStatusChanged: ((String) -> Void)?

    private let player: any MediaPlayerProvider
    private let lyricsClient: LRCLIBClient
    private let lockMonitor = LockAndSleepMonitor()
    private let skyLight: SkyLightBridge?
    private let viewModel = OverlayViewModel()

    private var inputs = OverlayInputs(
        isEnabled: true,
        isScreenLocked: false,
        isDisplayAsleep: false,
        isPreviewOpen: false,
        playbackState: .stopped
    )

    private var overlayWindows: [PassiveOverlayWindow] = []
    private var previewWindow: NSWindow?
    private var pollTask: Task<Void, Never>?
    private var trackFetchTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var paletteCache: [String: AlbumPalette] = [:]
    private var loadedTrackID: String?
    private var playbackRefreshGeneration: UInt64 = 0

    var isEnabled: Bool {
        get { inputs.isEnabled }
        set {
            inputs.isEnabled = newValue
            applyPolicy()
        }
    }

    init(player: any MediaPlayerProvider = SpotifyProvider(), lyricsClient: LRCLIBClient = LRCLIBClient()) {
        self.player = player
        self.lyricsClient = lyricsClient
        self.skyLight = SkyLightBridge()
    }

    func start() {
        rebuildOverlayWindows()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildOverlayWindows()
                self?.applyPolicy()
            }
        }

        lockMonitor.start(
            onLockChanged: { [weak self] locked in
                guard let self else { return }
                self.inputs.isScreenLocked = locked
                // Apply immediately so unlock hides overlays in zero frames even if Spotify stalls
                self.applyPolicy()
                if locked && !self.inputs.isDisplayAsleep {
                    Task { @MainActor in
                        await self.refreshPlayback()
                    }
                }
            },
            onSleepChanged: { [weak self] asleep in
                guard let self else { return }
                self.inputs.isDisplayAsleep = asleep
                if !asleep && self.inputs.isScreenLocked {
                    Task { @MainActor in await self.refreshPlayback() }
                } else {
                    self.applyPolicy()
                }
            }
        )

        player.startObserving { [weak self] in
            Task { @MainActor in
                await self?.refreshPlayback()
            }
        }

        Task { @MainActor in
            await refreshPlayback()
        }
    }

    func stop() {
        pollTask?.cancel()
        trackFetchTask?.cancel()
        player.stopObserving()
        lockMonitor.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        for win in overlayWindows { win.orderOut(nil) }
        previewWindow?.close()
    }

    func openPreviewWindow() {
        if let existing = previewWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 960, height: 600)
        let win = PreviewWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Needle — Vista previa (Esc para cerrar)"
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.moveToActiveSpace]
        win.contentViewController = NSHostingController(
            rootView: ConstellationLyricsView(model: viewModel)
                .frame(minWidth: 720, idealWidth: 960, minHeight: 450, idealHeight: 600)
        )
        win.setContentSize(NSSize(width: 960, height: 600))
        win.center()
        win.onClose = { [weak self] in
            Task { @MainActor in
                self?.previewWindow = nil
                self?.inputs.isPreviewOpen = false
                self?.applyPolicy()
            }
        }

        previewWindow = win
        inputs.isPreviewOpen = true
        applyPolicy()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            await refreshPlayback()
        }
    }

    private func rebuildOverlayWindows() {
        for win in overlayWindows {
            win.orderOut(nil)
        }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let win = PassiveOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = NSHostingController(rootView: ConstellationLyricsView(model: viewModel))
            win.setFrame(screen.frame, display: true)
            skyLight?.attach(window: win)
            overlayWindows.append(win)
        }
    }

    private func refreshPlayback() async {
        playbackRefreshGeneration &+= 1
        let generation = playbackRefreshGeneration
        let snapshot = await player.fetchSnapshot()
        guard generation == playbackRefreshGeneration else { return }

        inputs.playbackState = snapshot.state
        viewModel.updateClock(with: snapshot)
        viewModel.track = snapshot.track

        if let track = snapshot.track {
            let stateLabel = snapshot.state == .playing ? "Reproduciendo" : "En pausa"
            onStatusChanged?("\(player.playerName): \(stateLabel) — \(track.name)")
            if loadedTrackID != track.id {
                loadedTrackID = track.id
                loadTrackAssets(for: track)
            }
        } else {
            onStatusChanged?("\(player.playerName): detenido")
        }

        applyPolicy()
    }

    private func loadTrackAssets(for track: TrackInfo) {
        trackFetchTask?.cancel()
        viewModel.syncedLyrics = nil
        if let cachedPalette = paletteCache[track.id] {
            viewModel.palette = cachedPalette
        } else {
            viewModel.palette = .fallback
        }

        let client = lyricsClient
        trackFetchTask = Task { [weak self] in
            async let lyricsResult = client.fetchLyrics(for: track)
            async let paletteResult = Self.fetchPalette(for: track)

            let (lyrics, palette) = await (lyricsResult, paletteResult)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.loadedTrackID == track.id else { return }
                self.viewModel.syncedLyrics = lyrics
                if let palette {
                    self.paletteCache[track.id] = palette
                    self.viewModel.palette = palette
                } else if self.paletteCache[track.id] == nil {
                    self.viewModel.palette = .fallback
                }
            }
        }
    }

    private static func fetchPalette(for track: TrackInfo) async -> AlbumPalette? {
        guard let url = track.artworkURL, url.scheme?.lowercased() == "https" else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return PaletteExtractor.extract(from: data)
        } catch {
            return nil
        }
    }

    private func applyPolicy() {
        let decision = OverlayVisibilityPolicy.evaluate(inputs)
        viewModel.shouldAnimate = decision.shouldAnimate
        viewModel.isVisible = decision.showLockScreenOverlay || inputs.isPreviewOpen

        if decision.showLockScreenOverlay {
            for win in overlayWindows {
                skyLight?.attach(window: win)
                win.orderFrontRegardless()
            }
        } else {
            for win in overlayWindows {
                win.orderOut(nil)
            }
        }

        if decision.shouldPollPlayer {
            startPollingIfNeeded()
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { break }
                await self?.refreshPlayback()
            }
        }
    }
}

private final class PreviewWindow: NSWindow, NSWindowDelegate {
    var onClose: (() -> Void)?

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        self.delegate = self
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
