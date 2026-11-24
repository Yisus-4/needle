import AppKit
import Foundation

@MainActor
final class NeedleAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = LockScreenCoordinator()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        coordinator.onStatusChanged = { [weak self] text in
            self?.statusMenuItem?.title = text
        }
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Needle")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let status = NSMenuItem(title: "Spotify: esperando…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Activar en pantalla de bloqueo", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = .on
        menu.addItem(toggle)
        toggleMenuItem = toggle

        let preview = NSMenuItem(title: "Vista previa", action: #selector(openPreview), keyEquivalent: "p")
        preview.target = self
        menu.addItem(preview)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Salir de Needle", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled() {
        coordinator.isEnabled.toggle()
        toggleMenuItem?.state = coordinator.isEnabled ? .on : .off
    }

    @objc private func openPreview() {
        coordinator.openPreviewWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct NeedleAppEntry {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = NeedleAppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
