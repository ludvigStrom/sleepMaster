import XCTest

@MainActor
final class FakePowerMonitor: PowerMonitoring {
    var isOnAC = true
    var batteryPercent: Int? = 80
    private var changeHandlers: [() -> Void] = []

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    func start() {}

    func notify() {
        changeHandlers.forEach { $0() }
    }
}

final class LidClosedSafetyTests: XCTestCase {
    func testCutoffIsStrictlyBelowThreshold() {
        XCTAssertFalse(LidClosedSafety.shouldDisableLidClosed(isOnAC: false, batteryPercent: 80, cutoff: 79))
        XCTAssertTrue(LidClosedSafety.shouldDisableLidClosed(isOnAC: false, batteryPercent: 78, cutoff: 79))
    }

    func testIgnoresBatteryWhileOnAC() {
        XCTAssertFalse(LidClosedSafety.shouldDisableLidClosed(isOnAC: true, batteryPercent: 5, cutoff: 10))
    }

    func testIgnoresMissingPercent() {
        XCTAssertFalse(LidClosedSafety.shouldDisableLidClosed(isOnAC: false, batteryPercent: nil, cutoff: 10))
    }
}

final class BatteryFloorTests: XCTestCase {
    func testFloorIsStrictlyBelowThreshold() {
        XCTAssertFalse(BatteryFloor.shouldAllowSleep(isOnAC: false, batteryPercent: 20, floor: 20))
        XCTAssertTrue(BatteryFloor.shouldAllowSleep(isOnAC: false, batteryPercent: 19, floor: 20))
    }

    func testIgnoresBatteryWhileOnAC() {
        XCTAssertFalse(BatteryFloor.shouldAllowSleep(isOnAC: true, batteryPercent: 5, floor: 20))
    }

    func testIgnoresMissingPercent() {
        XCTAssertFalse(BatteryFloor.shouldAllowSleep(isOnAC: false, batteryPercent: nil, floor: 20))
    }
}

@MainActor
final class BatteryCutoffTests: XCTestCase {
    func testUnplugThenPercentDropClearsLidClosedKeepsAssertion() {
        let assertion = FakeSleepController()
        let lid = FakeLidClosedBackend()
        let power = FakePowerMonitor()
        power.isOnAC = true
        power.batteryPercent = 80
        let defaults = UserDefaults(suiteName: "SleepMasterTests.Battery")!
        defaults.removePersistentDomain(forName: "SleepMasterTests.Battery")

        let preventer = SleepPreventer(
            controller: assertion,
            lidClosed: lid,
            powerMonitor: power,
            lidClosedBatteryCutoff: 79,
            defaults: defaults
        )
        preventer.toggle()
        XCTAssertEqual(lid.setTrueCount, 1)

        power.isOnAC = false
        power.batteryPercent = 80
        power.notify()
        XCTAssertEqual(lid.setFalseCount, 0)

        power.batteryPercent = 78
        power.notify()
        XCTAssertEqual(lid.setFalseCount, 1)
        XCTAssertTrue(preventer.isSleepDisabled)
        XCTAssertTrue(assertion.isActive)
    }
}
