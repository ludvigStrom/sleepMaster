import XCTest

@MainActor
final class RecordingNotificationClient: NotificationPosting {
    private(set) var permissionRequestCount = 0
    private(set) var scheduledWarning: Date?
    private(set) var cancelCount = 0
    private(set) var pauseCount = 0
    private var hasRequested = false

    func requestPermissionIfNeeded() {
        guard !hasRequested else { return }
        hasRequested = true
        permissionRequestCount += 1
    }

    func scheduleTimerWarning(at date: Date, minutesBeforeEnd: Int) {
        scheduledWarning = date
    }

    func cancelTimerWarning() {
        cancelCount += 1
        scheduledWarning = nil
    }

    func notifyPausedOnBattery() {
        pauseCount += 1
    }
}

@MainActor
final class DeferredDelay {
    private var work: (() -> Void)?

    func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) -> () -> Void {
        work = block
        return { [weak self] in
            self?.work = nil
        }
    }

    func fire() {
        let block = work
        work = nil
        block?()
    }
}

@MainActor
final class NotificationTests: XCTestCase {
    func testIndefinitelyDoesNotRequestPermission() {
        let notifications = RecordingNotificationClient()
        let state = makeState(notifications: notifications)

        state.isActive = true

        XCTAssertEqual(notifications.permissionRequestCount, 0)
        XCTAssertNil(notifications.scheduledWarning)
    }

    func testFirstTimerRequestsPermissionOnce() {
        let notifications = RecordingNotificationClient()
        let clock = TestClock(Date(timeIntervalSince1970: 100_000))
        let state = makeState(notifications: notifications, clock: clock)

        state.selectDuration(6 * 60)
        state.selectDuration(30 * 60)

        XCTAssertEqual(notifications.permissionRequestCount, 1)
    }

    func testSixMinuteTimerSchedulesWarningAtOneMinute() {
        let notifications = RecordingNotificationClient()
        let start = Date(timeIntervalSince1970: 200_000)
        let clock = TestClock(start)
        let state = makeState(notifications: notifications, clock: clock)
        state.timerWarningLead = 5 * 60

        state.selectDuration(6 * 60)

        XCTAssertEqual(notifications.scheduledWarning, start.addingTimeInterval(60))
    }

    func testExtendReplacesWarning() {
        let notifications = RecordingNotificationClient()
        let start = Date(timeIntervalSince1970: 300_000)
        let clock = TestClock(start)
        let state = makeState(notifications: notifications, clock: clock)
        state.timerWarningLead = 5 * 60

        state.selectDuration(6 * 60)
        state.extend(by: 30 * 60)

        XCTAssertEqual(notifications.scheduledWarning, start.addingTimeInterval(6 * 60 + 30 * 60 - 5 * 60))
    }

    func testOffAndIndefinitelyCancelWarning() {
        let notifications = RecordingNotificationClient()
        let clock = TestClock(Date(timeIntervalSince1970: 400_000))
        let state = makeState(notifications: notifications, clock: clock)

        state.selectDuration(30 * 60)
        XCTAssertNotNil(notifications.scheduledWarning)

        state.mode = .indefinitely
        XCTAssertNil(notifications.scheduledWarning)
        XCTAssertGreaterThanOrEqual(notifications.cancelCount, 1)

        state.mode = .timer
        state.selectDuration(30 * 60)
        state.isActive = false
        XCTAssertNil(notifications.scheduledWarning)
    }

    func testNotificationActions() {
        let notifications = RecordingNotificationClient()
        let start = Date(timeIntervalSince1970: 500_000)
        let clock = TestClock(start)
        let state = makeState(notifications: notifications, clock: clock)

        state.selectDuration(30 * 60)
        let original = state.endDate

        state.handleNotificationAction(NotificationAction.extend30)
        XCTAssertEqual(state.endDate?.timeIntervalSince(original!), 30 * 60)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .timer)

        state.handleNotificationAction(NotificationAction.keepAwake)
        XCTAssertEqual(state.mode, .indefinitely)
        XCTAssertTrue(state.isActive)
        XCTAssertNil(state.endDate)
        XCTAssertNil(notifications.scheduledWarning)

        state.selectDuration(30 * 60)
        state.handleNotificationAction(NotificationAction.letSleep)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.endDate)
    }

    func testPauseNotifiesOnceAndAgainAfterResume() {
        let notifications = RecordingNotificationClient()
        let power = FakePowerMonitor()
        let delay = DeferredDelay()
        let state = makeState(
            notifications: notifications,
            power: power,
            runAfter: { delay.schedule($0, $1) }
        )

        state.isActive = true
        power.isOnAC = false
        power.notify()
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(notifications.pauseCount, 0)

        delay.fire()
        XCTAssertEqual(notifications.pauseCount, 1)

        delay.fire()
        XCTAssertEqual(notifications.pauseCount, 1)

        power.isOnAC = true
        power.notify()
        XCTAssertFalse(state.isPaused)

        power.isOnAC = false
        power.notify()
        delay.fire()
        XCTAssertEqual(notifications.pauseCount, 2)
    }

    func testPauseBlipBeforeDebounceDoesNotNotify() {
        let notifications = RecordingNotificationClient()
        let power = FakePowerMonitor()
        let delay = DeferredDelay()
        let state = makeState(
            notifications: notifications,
            power: power,
            runAfter: { delay.schedule($0, $1) }
        )

        state.isActive = true
        power.isOnAC = false
        power.notify()
        power.isOnAC = true
        power.notify()
        delay.fire()

        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(notifications.pauseCount, 0)
    }

    func testShortTimerCancelsWarning() {
        let notifications = RecordingNotificationClient()
        let clock = TestClock(Date(timeIntervalSince1970: 600_000))
        let state = makeState(notifications: notifications, clock: clock)
        state.timerWarningLead = 5 * 60

        state.selectDuration(60)

        XCTAssertEqual(notifications.permissionRequestCount, 1)
        XCTAssertNil(notifications.scheduledWarning)
    }

    private func makeState(
        notifications: NotificationPosting,
        power: FakePowerMonitor? = nil,
        clock: TestClock? = nil,
        runAfter: ((TimeInterval, @escaping () -> Void) -> () -> Void)? = nil
    ) -> AppState {
        let suiteName = "SleepMasterTests.Notify.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let monitor = power ?? FakePowerMonitor()
        return AppState(
            preventer: SleepPreventer(
                controller: FakeSleepController(),
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: monitor,
                defaults: defaults
            ),
            powerMonitor: monitor,
            notifications: notifications,
            defaults: defaults,
            now: { clock?.date ?? Date(timeIntervalSince1970: 1) },
            startsClock: false,
            pauseNotifyDelay: 2,
            runAfter: runAfter ?? { _, work in
                work()
                return {}
            }
        )
    }
}
