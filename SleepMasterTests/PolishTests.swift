import XCTest

@MainActor
final class PolishTests: XCTestCase {
    func testDisplaySleepSuffixOnManualSubtitle() {
        let state = makeState()
        state.isActive = true
        XCTAssertEqual(state.statusSubtitle, "Until you turn it off")
        state.allowDisplaySleep = true
        XCTAssertEqual(state.statusSubtitle, "Until you turn it off · display may sleep")
        XCTAssertEqual(state.powerAccessibilityValue, "On")
    }

    func testDisplaySleepSuffixOnTimerSubtitle() {
        let clock = TestClock(Date(timeIntervalSince1970: 80_000))
        let state = makeState(clock: clock)
        state.selectDuration(30 * 60)
        XCTAssertTrue(state.statusSubtitle.hasPrefix("Allows sleep at "))
        XCTAssertFalse(state.statusSubtitle.contains("display may sleep"))
        state.allowDisplaySleep = true
        XCTAssertTrue(state.statusSubtitle.hasSuffix(" · display may sleep"))
    }

    func testPausedHasNoDisplaySleepSuffix() {
        let power = FakePowerMonitor()
        let state = makeState(power: power)
        state.allowDisplaySleep = true
        state.isActive = true
        power.isOnAC = false
        power.notify()
        XCTAssertEqual(state.statusTitle, "Paused on battery")
        XCTAssertEqual(state.statusSubtitle, "Resumes when the power adapter is connected.")
        XCTAssertEqual(state.powerAccessibilityValue, "Paused")
        XCTAssertEqual(state.menuBarLabel, "Paused")
    }

    func testOnboardingCompletesOnce() {
        let suiteName = "SleepMasterTests.Polish.Onboard.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        XCTAssertTrue(first.needsOnboarding)
        first.completeOnboarding()
        XCTAssertFalse(first.needsOnboarding)

        let second = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        XCTAssertFalse(second.needsOnboarding)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testScheduleSummaryWeekdays() {
        let state = makeState()
        state.scheduleDays = [2, 3, 4, 5, 6]
        state.scheduleStartMinutes = 9 * 60
        state.scheduleEndMinutes = 17 * 60
        XCTAssertEqual(state.scheduleSummary, "Weekdays 09:00–17:00")
    }

    private func makeState(
        power: FakePowerMonitor? = nil,
        clock: TestClock? = nil
    ) -> AppState {
        let power = power ?? FakePowerMonitor()
        let suiteName = "SleepMasterTests.Polish.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppState(
            preventer: SleepPreventer(
                controller: FakeSleepController(),
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: power,
                defaults: defaults
            ),
            powerMonitor: power,
            defaults: defaults,
            now: { clock?.date ?? Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
    }
}
