import XCTest

@MainActor
final class FakeLidClosedBackend: LidClosedBackend {
    var setTrueCount = 0
    var setFalseCount = 0
    var setTrueError: Error?
    var setFalseError: Error?
    var lastValue: Bool?

    func setSleepDisabled(_ disabled: Bool) throws {
        lastValue = disabled
        if disabled {
            setTrueCount += 1
            if let setTrueError { throw setTrueError }
        } else {
            setFalseCount += 1
            if let setFalseError { throw setFalseError }
        }
    }
}

@MainActor
final class LayeredSleepTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SleepMasterTests.Layered")
        defaults.removePersistentDomain(forName: "SleepMasterTests.Layered")
    }

    func testStartWithLidClosedCallsAssertionAndPmset() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        let preventer = SleepPreventer(controller: assertion, lidClosed: lid, defaults: defaults)

        preventer.toggle()

        XCTAssertEqual(assertion.startCallCount, 1)
        XCTAssertEqual(lid.setTrueCount, 1)
        XCTAssertTrue(preventer.isSleepDisabled)
    }

    func testStartWithLidClosedOffSkipsPmset() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        let preventer = SleepPreventer(controller: assertion, lidClosed: lid, defaults: defaults)
        preventer.setLidClosedEnabled(false)

        preventer.toggle()

        XCTAssertEqual(assertion.startCallCount, 1)
        XCTAssertEqual(lid.setTrueCount, 0)
        XCTAssertTrue(preventer.isSleepDisabled)
    }

    func testStopClearsLidClosed() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        let preventer = SleepPreventer(controller: assertion, lidClosed: lid, defaults: defaults)
        preventer.toggle()

        preventer.stop()

        XCTAssertEqual(lid.setFalseCount, 1)
        XCTAssertEqual(assertion.stopCallCount, 1)
        XCTAssertFalse(preventer.isSleepDisabled)
    }

    func testCanceledLidClosedRollsBackAssertion() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        lid.setTrueError = SleepControlError.userCanceled()
        let preventer = SleepPreventer(controller: assertion, lidClosed: lid, defaults: defaults)

        preventer.toggle()

        XCTAssertEqual(assertion.startCallCount, 1)
        XCTAssertEqual(assertion.stopCallCount, 1)
        XCTAssertFalse(assertion.isActive)
        XCTAssertFalse(preventer.isSleepDisabled)
        XCTAssertNil(preventer.errorMessage)
    }

    func testTurningLidClosedOffWhileActiveClearsOnlyPmset() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        let preventer = SleepPreventer(controller: assertion, lidClosed: lid, defaults: defaults)
        preventer.toggle()

        preventer.setLidClosedEnabled(false)

        XCTAssertEqual(lid.setFalseCount, 1)
        XCTAssertTrue(preventer.isSleepDisabled)
        XCTAssertTrue(assertion.isActive)
    }
}
