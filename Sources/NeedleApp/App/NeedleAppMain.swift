import AppKit
import Foundation
import NeedleCore

@MainActor
final class NeedleAppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = LockScreenCoordinator()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var toggleMenuItem: NSMenuItem?
    private var awakeItems: [(mode: KeepAwakeMode, item: NSMenuItem)] = []
    private var onlyACMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        coordinator.onStatusChanged = { [weak self] text in
            self?.statusMenuItem?.title = text
        }
        coordinator.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            coordinator.openPreviewWindow()
        }
        return true
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

        // Display keep-awake submenu (never prevents lid-close sleep)
        let awakeParent = NSMenuItem(title: "Mantener pantalla encendida", action: nil, keyEquivalent: "")
        let awakeMenu = NSMenu()
        let options: [(String, KeepAwakeMode)] = [
            ("Apagado normal de macOS", .systemDefault),
            ("2 minutos", .minutes(2)),
            ("5 minutos", .minutes(5)),
            ("10 minutos", .minutes(10)),
            ("Mientras suene música", .whilePlaying)
        ]
        for (idx, opt) in options.enumerated() {
            let mi = NSMenuItem(title: opt.0, action: #selector(selectKeepAwakeMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = idx
            mi.state = (opt.1 == coordinator.keepAwakeMode) ? .on : .off
            awakeMenu.addItem(mi)
            awakeItems.append((opt.1, mi))
        }
        awakeMenu.addItem(.separator())
        let onlyAC = NSMenuItem(title: "Solo conectado a la corriente", action: #selector(toggleOnlyAC), keyEquivalent: "")
        onlyAC.target = self
        onlyAC.state = coordinator.keepAwakeOnlyOnAC ? .on : .off
        awakeMenu.addItem(onlyAC)
        onlyACMenuItem = onlyAC
        awakeParent.submenu = awakeMenu
        menu.addItem(awakeParent)

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

    @objc private func selectKeepAwakeMode(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < awakeItems.count else { return }
        let selected = awakeItems[sender.tag].mode
        coordinator.keepAwakeMode = selected
        for entry in awakeItems {
            entry.item.state = (entry.mode == selected) ? .on : .off
        }
    }

    @objc private func toggleOnlyAC() {
        coordinator.keepAwakeOnlyOnAC.toggle()
        onlyACMenuItem?.state = coordinator.keepAwakeOnlyOnAC ? .on : .off
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
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
