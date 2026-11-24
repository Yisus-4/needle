import AppKit
import Foundation

final class SkyLightBridge {
    private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let notificationCenterAtScreenLockLevel: Int32 = 400

    private let connection: Int32
    private let space: Int32
    private let addWindows: F_SLSSpaceAddWindowsAndRemoveFromSpaces

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else {
            return nil
        }
        guard
            let pMain = dlsym(handle, "SLSMainConnectionID"),
            let pCreate = dlsym(handle, "SLSSpaceCreate"),
            let pSetLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let pShow = dlsym(handle, "SLSShowSpaces"),
            let pAdd = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            return nil
        }

        let mainConn = unsafeBitCast(pMain, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(pCreate, to: F_SLSSpaceCreate.self)
        let setLevel = unsafeBitCast(pSetLevel, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(pShow, to: F_SLSShowSpaces.self)
        self.addWindows = unsafeBitCast(pAdd, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)

        self.connection = mainConn()
        self.space = spaceCreate(connection, 1, 0)
        _ = setLevel(connection, space, Self.notificationCenterAtScreenLockLevel)
        _ = showSpaces(connection, [space] as CFArray)
    }

    @MainActor
    func attach(window: NSWindow) {
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
