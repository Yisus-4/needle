import AppKit

final class PassiveOverlayWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(Int32.max - 2))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
