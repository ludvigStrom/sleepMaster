import XCTest

@MainActor
final class AppStatePauseTests: XCTestCase {
    func testUnplugPausesAndReplugResumes() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        let state = makeState(controller: controller, power: power)

        state.isActive = true
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(state.statusTitle, "Staying awake")
        XCTAssertEqual(state.plugInSubtitle, "Power adapter connected")

        power.isOnAC = false
        power.batteryPercent = 80
        power.notify()

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isPaused)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.stopCallCount, 1)
        XCTAssertEqual(state.statusTitle, "Paused on battery")
        XCTAssertEqual(state.statusSubtitle, "Resumes when the power adapter is connected.")
        XCTAssertEqual(state.menuBarLabel, "Paused")
        XCTAssertEqual(state.plugInSubtitle, "On battery now — sleep is allowed · 80%")

        power.isOnAC = true
        power.notify()

        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isPaused)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.startCallCount, 2)
        XCTAssertEqual(state.statusTitle, "Staying awake")
        XCTAssertEqual(state.plugInSubtitle, "Power adapter connected")
    }

    func testTimerKeepsRunningThroughPause() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        let clock = TestClock(Date(timeIntervalSince1970: 50_000))
        let state = makeState(controller: controller, power: power, clock: clock)

        state.selectDuration(30 * 60)
        let endDate = state.endDate
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertEqual(state.remaining, 30 * 60)

        power.isOnAC = false
        power.notify()
        XCTAssertTrue(state.isPaused)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(state.endDate, endDate)

        clock.date = clock.date.addingTimeInterval(10 * 60)
        state.tick()

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.endDate, endDate)
        XCTAssertEqual(state.remaining, 20 * 60)

        power.isOnAC = true
        power.notify()

        XCTAssertFalse(state.isPaused)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(state.endDate, endDate)
        XCTAssertEqual(state.remaining, 20 * 60)
        XCTAssertEqual(state.statusTitle, "Awake · 0:20:00")
    }

    func testBatteryFloorPausesWhenPlugOnlyIsOff() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        power.isOnAC = false
        power.batteryPercent = 80
        let state = makeState(
            controller: controller,
            power: power,
            onlyWhilePluggedIn: false,
            batteryFloor: 81
        )

        state.isActive = true

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isPaused)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.startCallCount, 0)
        XCTAssertEqual(state.statusTitle, "Paused on battery")
        XCTAssertEqual(state.statusSubtitle, "Allows sleep below 81%.")
    }

    func testFloorIgnoredOnAC() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        power.isOnAC = true
        power.batteryPercent = 5
        let state = makeState(
            controller: controller,
            power: power,
            onlyWhilePluggedIn: false,
            batteryFloor: 20
        )

        state.isActive = true

        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isPaused)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.startCallCount, 1)
    }

    func testTurningOnWhileUnpluggedStaysActiveWithoutAssertion() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        power.isOnAC = false
        let state = makeState(controller: controller, power: power)

        state.isActive = true

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(controller.startCallCount, 0)
        XCTAssertFalse(controller.isActive)
    }

    func testFlipDisplaySleepWhileOnDoesNotRestart() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        let state = makeState(controller: controller, power: power)

        state.isActive = true
        let starts = controller.startCallCount
        let stops = controller.stopCallCount
        let sets = controller.setAllowDisplaySleepCallCount

        state.allowDisplaySleep = true

        XCTAssertTrue(state.isActive)
        XCTAssertTrue(state.allowDisplaySleep)
        XCTAssertTrue(controller.allowDisplaySleep)
        XCTAssertEqual(controller.setAllowDisplaySleepCallCount, sets + 1)
        XCTAssertEqual(controller.startCallCount, starts)
        XCTAssertEqual(controller.stopCallCount, stops)
    }

    func testFlipDisplaySleepWhilePausedDoesNotTakeAssertion() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        let state = makeState(controller: controller, power: power)

        state.isActive = true
        power.isOnAC = false
        power.notify()
        XCTAssertTrue(state.isPaused)
        XCTAssertFalse(controller.isActive)
        let starts = controller.startCallCount

        state.allowDisplaySleep = true

        XCTAssertTrue(state.isPaused)
        XCTAssertTrue(controller.allowDisplaySleep)
        XCTAssertEqual(controller.startCallCount, starts)
        XCTAssertFalse(controller.isActive)
    }

    func testPersistsPlugOnlyAndFloor() {
        let suiteName = "SleepMasterTests.PausePersist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let power = FakePowerMonitor()
        let first = AppState(
            preventer: SleepPreventer(
                controller: FakeSleepController(),
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: power,
                defaults: defaults
            ),
            powerMonitor: power,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        first.onlyWhilePluggedIn = false
        first.batteryFloorPercent = 15
        first.allowDisplaySleep = true

        let secondPower = FakePowerMonitor()
        let second = AppState(
            preventer: SleepPreventer(
                controller: FakeSleepController(),
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: secondPower,
                defaults: defaults
            ),
            powerMonitor: secondPower,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        XCTAssertFalse(second.onlyWhilePluggedIn)
        XCTAssertEqual(second.batteryFloorPercent, 15)
        XCTAssertTrue(second.allowDisplaySleep)
        XCTAssertFalse(second.isActive)

        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeState(
        controller: SleepController,
        power: FakePowerMonitor,
        clock: TestClock? = nil,
        onlyWhilePluggedIn: Bool = true,
        batteryFloor: Int = BatteryFloor.defaultPercent
    ) -> AppState {
        let suiteName = "SleepMasterTests.Pause.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let now: () -> Date = {
            clock?.date ?? Date(timeIntervalSince1970: 1)
        }
        let state = AppState(
            preventer: SleepPreventer(
                controller: controller,
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: power,
                defaults: defaults
            ),
            powerMonitor: power,
            defaults: defaults,
            now: now,
            startsClock: false
        )
        state.onlyWhilePluggedIn = onlyWhilePluggedIn
        state.batteryFloorPercent = batteryFloor
        return state
    }
}
