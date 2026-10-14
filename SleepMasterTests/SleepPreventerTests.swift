import XCTest

@MainActor
final class FakeSleepController: SleepController {
    var isActive = false
    var startCallCount = 0
    var stopCallCount = 0
    var setAllowDisplaySleepCallCount = 0
    var allowDisplaySleep = false
    var startError: Error?
    var stopError: Error?

    func start() throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
        isActive = true
    }

    func stop() throws {
        stopCallCount += 1
        if let stopError {
            throw stopError
        }
        isActive = false
    }

    func setAllowDisplaySleep(_ allow: Bool) throws {
        setAllowDisplaySleepCallCount += 1
        allowDisplaySleep = allow
    }
}

@MainActor
final class SleepPreventerTests: XCTestCase {
    func testToggleOnCallsStartAndPublishesActive() {
        let controller = FakeSleepController()
        let preventer = SleepPreventer(controller: controller)

        XCTAssertFalse(preventer.isSleepDisabled)

        preventer.toggle()

        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertEqual(controller.stopCallCount, 0)
        XCTAssertTrue(preventer.isSleepDisabled)
        XCTAssertEqual(preventer.statusText, "Sleep disabled")
        XCTAssertNil(preventer.errorMessage)
    }

    func testToggleOffCallsStopAndPublishesInactive() {
        let controller = FakeSleepController()
        controller.isActive = true
        let preventer = SleepPreventer(controller: controller)

        XCTAssertTrue(preventer.isSleepDisabled)

        preventer.toggle()

        XCTAssertEqual(controller.stopCallCount, 1)
        XCTAssertFalse(preventer.isSleepDisabled)
        XCTAssertEqual(preventer.statusText, "Sleep allowed")
    }

    func testCanceledPasswordLeavesToggleUnchangedAndShowsNoError() {
        let controller = FakeSleepController()
        controller.startError = SleepControlError.userCanceled()
        let preventer = SleepPreventer(controller: controller)

        preventer.toggle()

        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(preventer.isSleepDisabled)
        XCTAssertNil(preventer.errorMessage)
    }

    func testOtherErrorsSurfaceAMessage() {
        let controller = FakeSleepController()
        controller.startError = SleepControlError.couldNotCreateScript
        let preventer = SleepPreventer(controller: controller)

        preventer.toggle()

        XCTAssertFalse(preventer.isSleepDisabled)
        XCTAssertEqual(preventer.errorMessage, SleepControlError.couldNotCreateScript.errorDescription)
    }
}

final class PmsetStatusTests: XCTestCase {
    func testParseSleepDisabledOne() {
        let output = """
        System-wide power settings:
         SleepDisabled          1
        """
        XCTAssertTrue(PmsetStatus.parseSleepDisabled(output))
    }

    func testParseSleepDisabledZero() {
        let output = """
        System-wide power settings:
         SleepDisabled          0
        """
        XCTAssertFalse(PmsetStatus.parseSleepDisabled(output))
    }

    func testParseSleepDisabledMissing() {
        XCTAssertFalse(PmsetStatus.parseSleepDisabled("Currently in use:"))
    }
}
