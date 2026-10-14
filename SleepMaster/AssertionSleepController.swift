import IOKit.pwr_mgt

@MainActor
final class AssertionSleepController: SleepController {
    static let assertionName = "Sleepmaster"

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var allowDisplaySleep = false

    var isActive: Bool { hasAssertion }

    func start() throws {
        guard !hasAssertion else { return }
        assertionID = try createAssertion()
        hasAssertion = true
    }

    func stop() throws {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        hasAssertion = false
    }

    func setAllowDisplaySleep(_ allow: Bool) throws {
        guard allow != allowDisplaySleep else { return }
        allowDisplaySleep = allow
        guard hasAssertion else { return }

        let newID = try createAssertion()
        IOPMAssertionRelease(assertionID)
        assertionID = newID
    }

    private var assertionType: CFString {
        if allowDisplaySleep {
            return kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        }
        return kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
    }

    private func createAssertion() throws -> IOPMAssertionID {
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            throw SleepControlError.assertionFailed(result)
        }
        return newID
    }
}
