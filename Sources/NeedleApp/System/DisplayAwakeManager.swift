import Foundation
import IOKit.ps
import IOKit.pwr_mgt

@MainActor
final class DisplayAwakeManager {
    private var assertionID: IOPMAssertionID = 0
    private var isHoldingAssertion = false

    func setActive(_ active: Bool) {
        if active {
            acquireIfNeeded()
        } else {
            releaseIfNeeded()
        }
    }

    func isOnACPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        else {
            return true
        }
        return type == kIOPSACPowerValue
    }

    private func acquireIfNeeded() {
        guard !isHoldingAssertion else { return }
        var id: IOPMAssertionID = 0
        let reason = "Needle displaying synchronized lyrics on Lock Screen" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            isHoldingAssertion = true
        }
    }

    private func releaseIfNeeded() {
        guard isHoldingAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHoldingAssertion = false
    }

    deinit {
        if isHoldingAssertion {
            IOPMAssertionRelease(assertionID)
        }
    }
}
