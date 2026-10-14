import XCTest

@MainActor
final class TestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
final class AppStateTests: XCTestCase {
    func testFlippingIsActiveCallsController() {
        let controller = FakeSleepController()
        let state = AppState(controller: controller)

        XCTAssertFalse(state.isActive)

        state.isActive = true

        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.statusTitle, "Staying awake")

        state.isActive = false

        XCTAssertEqual(controller.stopCallCount, 1)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.statusTitle, "Sleep allowed")
    }

    func testToggleFlipsIsActiveAndCallsController() {
        let controller = FakeSleepController()
        let state = AppState(controller: controller)

        state.toggle()
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(controller.startCallCount, 1)

        state.toggle()
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(controller.stopCallCount, 1)
    }

    func testCanceledStartLeavesIsActiveOff() {
        let controller = FakeSleepController()
        controller.startError = SleepControlError.userCanceled()
        let state = AppState(controller: controller)

        state.isActive = true

        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.errorMessage)
    }

    func testSwitchingModeWhileOnKeepsAssertion() {
        let controller = FakeSleepController()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let state = makeState(controller: controller, clock: clock)

        state.isActive = true
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertNil(state.endDate)

        state.mode = .timer
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertEqual(controller.stopCallCount, 0)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.endDate, clock.date.addingTimeInterval(state.selectedDuration))

        state.mode = .indefinitely
        XCTAssertEqual(controller.startCallCount, 1)
        XCTAssertEqual(controller.stopCallCount, 0)
        XCTAssertTrue(state.isActive)
        XCTAssertNil(state.endDate)
    }

    func testOneMinuteTimerExpiresOnTick() {
        let controller = FakeSleepController()
        let clock = TestClock(Date(timeIntervalSince1970: 5_000))
        let state = makeState(controller: controller, clock: clock)

        state.selectDuration(60)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(controller.startCallCount, 1)

        clock.date = clock.date.addingTimeInterval(60)
        state.tick()

        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.endDate)
        XCTAssertEqual(controller.stopCallCount, 1)
    }

    func testEachChipSetsExpectedEndDateAndTurnsOn() {
        let controller = FakeSleepController()
        let start = Date(timeIntervalSince1970: 10_000)
        let clock = TestClock(start)
        let state = makeState(controller: controller, clock: clock)

        for chip in TimerDurations.chips {
            clock.date = start
            state.isActive = false
            state.selectDuration(chip.seconds)
            XCTAssertTrue(state.isActive, chip.label)
            XCTAssertEqual(state.mode, .timer)
            XCTAssertEqual(state.selectedDuration, chip.seconds)
            XCTAssertEqual(state.endDate, start.addingTimeInterval(chip.seconds), chip.label)
            XCTAssertTrue(state.statusSubtitle.hasPrefix("Allows sleep at "))
        }
        XCTAssertEqual(controller.startCallCount, TimerDurations.chips.count)
    }

    func testExtendMovesEndDateByExactIntervals() {
        let controller = FakeSleepController()
        let clock = TestClock(Date(timeIntervalSince1970: 20_000))
        let state = makeState(controller: controller, clock: clock)

        state.selectDuration(30 * 60)
        let original = state.endDate
        XCTAssertNotNil(original)

        state.extend(by: 30 * 60)
        XCTAssertEqual(state.endDate?.timeIntervalSince(original!), 30 * 60)

        state.extend(by: 60 * 60)
        XCTAssertEqual(state.endDate?.timeIntervalSince(original!), 90 * 60)
    }

    func testUntil2300At2258IsSameDayTwoMinutesLater() {
        let controller = FakeSleepController()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = 2026
        parts.month = 10
        parts.day = 14
        parts.hour = 22
        parts.minute = 58
        parts.second = 0
        let now = calendar.date(from: parts)!
        let clock = TestClock(now)
        let state = makeState(controller: controller, clock: clock)

        state.setUntil(hour: 23, minute: 0, calendar: calendar)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .timer)
        XCTAssertEqual(state.endDate?.timeIntervalSince(now), 2 * 60)
        let endParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: state.endDate!)
        XCTAssertEqual(endParts.day, 14)
        XCTAssertEqual(endParts.hour, 23)
        XCTAssertEqual(endParts.minute, 0)
    }

    func testUntilEarlierThanNowMeansTomorrow() {
        let controller = FakeSleepController()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = 2026
        parts.month = 10
        parts.day = 14
        parts.hour = 23
        parts.minute = 0
        let now = calendar.date(from: parts)!
        let clock = TestClock(now)
        let state = makeState(controller: controller, clock: clock)

        state.setUntil(hour: 22, minute: 0, calendar: calendar)

        let endParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: state.endDate!)
        XCTAssertEqual(endParts.day, 15)
        XCTAssertEqual(endParts.hour, 22)
    }

    func testPersistsModeAndDurationAndStartsOff() {
        let suiteName = "SleepMasterTests.AppState.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let first = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        first.selectDuration(2 * 60 * 60)
        XCTAssertTrue(first.isActive)

        let second = AppState(
            preventer: SleepPreventer(controller: FakeSleepController()),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )
        XCTAssertEqual(second.mode, .timer)
        XCTAssertEqual(second.selectedDuration, 2 * 60 * 60)
        XCTAssertFalse(second.isActive)
        XCTAssertNil(second.endDate)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCountdownFormats() {
        XCTAssertEqual(AppState.formatHMS(3900), "1:05:00")
        XCTAssertEqual(AppState.formatHM(3900), "1:05")
        XCTAssertEqual(AppState.formatHMS(15 * 60), "0:15:00")
    }

    private func makeState(controller: SleepController, clock: TestClock) -> AppState {
        let suiteName = "SleepMasterTests.AppState.case.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppState(
            preventer: SleepPreventer(controller: controller),
            defaults: defaults,
            now: { clock.date },
            startsClock: false
        )
    }
}
