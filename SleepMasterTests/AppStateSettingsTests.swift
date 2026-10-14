import XCTest

@MainActor
final class AppStateSettingsTests: XCTestCase {
    func testRememberOffRelaunchUsesDefaults() {
        let suiteName = "SleepMasterTests.Settings.Remember.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        first.rememberLastChoice = false
        first.defaultMode = .timer
        first.defaultDuration = 15 * 60
        first.selectDuration(8 * 60 * 60)
        XCTAssertTrue(first.isActive)
        XCTAssertEqual(first.selectedDuration, 8 * 60 * 60)

        let second = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        XCTAssertFalse(second.rememberLastChoice)
        XCTAssertEqual(second.defaultMode, .timer)
        XCTAssertEqual(second.defaultDuration, 15 * 60)
        XCTAssertEqual(second.mode, .timer)
        XCTAssertEqual(second.selectedDuration, 15 * 60)
        XCTAssertFalse(second.isActive)
        XCTAssertNil(second.endDate)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testShowTimeOffHidesTimerMenuLabel() {
        let controller = FakeSleepController()
        let suiteName = "SleepMasterTests.Settings.Time.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let clock = TestClock(Date(timeIntervalSince1970: 80_000))
        let state = AppState(
            preventer: SleepPreventer(controller: controller),
            defaults: defaults,
            now: { clock.date },
            startsClock: false
        )

        state.selectDuration(30 * 60)
        XCTAssertEqual(state.menuBarLabel, "0:30")

        state.showTimeInMenuBar = false
        XCTAssertNil(state.menuBarLabel)
        XCTAssertEqual(state.countdownMenuLabel, "0:30")

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMirroredTogglesShareOneAppState() {
        let controller = FakeSleepController()
        let suiteName = "SleepMasterTests.Settings.Mirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let state = AppState(
            preventer: SleepPreventer(controller: controller),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )

        state.onlyWhilePluggedIn = false
        state.allowDisplaySleep = true
        state.lidClosedEnabled = false
        state.batteryFloorPercent = 25

        XCTAssertFalse(state.onlyWhilePluggedIn)
        XCTAssertTrue(state.allowDisplaySleep)
        XCTAssertFalse(state.lidClosedEnabled)
        XCTAssertEqual(state.batteryFloorPercent, 25)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
