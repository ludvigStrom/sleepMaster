import IOKit.pwr_mgt

@MainActor
final class AssertionSleepController: SleepController {
    static let assertionName = "Sleepmaster"

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false

    var isActive: Bool { hasAssertion }

    func start() throws {
        guard !hasAssertion else { return }

        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            throw SleepControlError.assertionFailed(result)
        }

        assertionID = newID
        hasAssertion = true
    }

    func stop() throws {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        hasAssertion = false
    }
}
