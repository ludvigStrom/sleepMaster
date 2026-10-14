import XCTest

@MainActor
final class FakeWorkspace: WorkspaceWatching {
    var runningBundleIDs: Set<String> = []
    var names: [String: String] = [:]
    private var changeHandlers: [() -> Void] = []

    func displayName(for bundleID: String) -> String {
        names[bundleID] ?? bundleID
    }

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    func start() {}

    func launch(_ bundleID: String) {
        runningBundleIDs.insert(bundleID)
        changeHandlers.forEach { $0() }
    }

    func terminate(_ bundleID: String) {
        runningBundleIDs.remove(bundleID)
        changeHandlers.forEach { $0() }
    }
}

@MainActor
final class FakeUsage: ProcessUsageSampling {
    var percents: [String: Double] = [:]

    func cpuPercent(for bundleID: String) -> Double {
        percents[bundleID] ?? 0
    }

    func sample(bundleIDs: [String]) {}
}

@MainActor
final class AutomationTests: XCTestCase {
    private let textEditID = "com.apple.TextEdit"

    func testManualOffLatchesUntilReasonFiresAgain() {
        let power = FakePowerMonitor()
        let workspace = FakeWorkspace()
        workspace.names[textEditID] = "TextEdit"
        let state = makeState(power: power, workspace: workspace)

        state.addWatchedApp(bundleID: textEditID)
        workspace.launch(textEditID)
        state.autoOnWhenPluggedIn = true
        XCTAssertTrue(state.isActive)

        state.isActive = false
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)

        workspace.terminate(textEditID)
        XCTAssertFalse(state.isActive)

        workspace.launch(textEditID)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activationReason, .app(bundleID: textEditID, name: "TextEdit"))
        XCTAssertEqual(state.statusSubtitle, "Awake while TextEdit runs")
    }

    func testAutoOnWhenPluggedInStartsIndefinitelyAndStopsOnBattery() {
        let controller = FakeSleepController()
        let power = FakePowerMonitor()
        power.isOnAC = true
        let state = makeState(controller: controller, power: power)

        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.autoOnWhenPluggedIn)

        state.autoOnWhenPluggedIn = true
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .indefinitely)
        XCTAssertEqual(state.activationReason, .power)
        XCTAssertFalse(state.isPaused)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(state.statusTitle, "Staying awake")
        XCTAssertEqual(state.statusSubtitle, "Awake while plugged in")

        power.isOnAC = false
        power.notify()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)
        XCTAssertFalse(controller.isActive)
    }

    func testWatchedAppLaunchTurnsOnAndQuitTurnsOff() {
        let workspace = FakeWorkspace()
        workspace.names[textEditID] = "TextEdit"
        let state = makeState(workspace: workspace)

        state.addWatchedApp(bundleID: textEditID)
        XCTAssertFalse(state.isActive)

        workspace.launch(textEditID)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .indefinitely)
        XCTAssertEqual(state.activationReason, .app(bundleID: textEditID, name: "TextEdit"))
        XCTAssertEqual(state.statusSubtitle, "Awake while TextEdit runs")

        workspace.terminate(textEditID)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)
    }

    func testScheduleTurnsOnAndOffAtWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 14
        parts.hour = 12
        parts.minute = 0
        parts.second = 0
        let start = calendar.date(from: parts)!
        let clock = TestClock(start)
        let state = makeState(clock: clock, calendar: calendar)

        let weekday = calendar.component(.weekday, from: start)
        let minutes = 12 * 60
        state.scheduleDays = [weekday]
        state.scheduleStartMinutes = minutes + 2
        state.scheduleEndMinutes = minutes + 4
        state.scheduleEnabled = true
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.isScheduleActive(now: clock.date))

        clock.date = start.addingTimeInterval(2 * 60)
        state.tick()
        XCTAssertTrue(state.isScheduleActive(now: clock.date))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.mode, .indefinitely)
        XCTAssertEqual(state.activationReason, .schedule)
        XCTAssertEqual(state.statusSubtitle, "Awake on schedule")

        clock.date = start.addingTimeInterval(4 * 60)
        state.tick()
        XCTAssertFalse(state.isScheduleActive(now: clock.date))
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)
    }

    func testManualSessionIgnoresUnplugWhenAutoPowerIsTrue() {
        let power = FakePowerMonitor()
        power.isOnAC = true
        let state = makeState(power: power)

        state.isActive = true
        XCTAssertEqual(state.activationReason, .manual)
        state.autoOnWhenPluggedIn = true

        power.isOnAC = false
        power.notify()
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activationReason, .manual)
    }

    func testAppReasonWinsOverScheduleAndPower() {
        let power = FakePowerMonitor()
        let workspace = FakeWorkspace()
        workspace.names[textEditID] = "TextEdit"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 14
        parts.hour = 12
        parts.minute = 30
        let now = calendar.date(from: parts)!
        let clock = TestClock(now)
        let state = makeState(power: power, workspace: workspace, clock: clock, calendar: calendar)

        state.autoOnWhenPluggedIn = true
        XCTAssertEqual(state.activationReason, .power)

        state.scheduleDays = [calendar.component(.weekday, from: now)]
        state.scheduleStartMinutes = 12 * 60
        state.scheduleEndMinutes = 13 * 60
        state.scheduleEnabled = true
        XCTAssertEqual(state.activationReason, .schedule)

        state.addWatchedApp(bundleID: textEditID)
        workspace.launch(textEditID)
        XCTAssertEqual(state.activationReason, .app(bundleID: textEditID, name: "TextEdit"))
        XCTAssertEqual(state.statusSubtitle, "Awake while TextEdit runs")
    }

    func testWhileBusyTurnsOnAboveThresholdAndOffAfterIdle() {
        let cursorID = "com.todesktop.230313mzl4w5jfd"
        let workspace = FakeWorkspace()
        let usage = FakeUsage()
        workspace.names[cursorID] = "Cursor"
        let state = makeState(workspace: workspace, usage: usage)

        state.addWatchedApp(bundleID: cursorID, mode: .whileBusy)
        workspace.launch(cursorID)
        XCTAssertFalse(state.isActive)

        usage.percents[cursorID] = 40
        state.tick()
        XCTAssertFalse(state.isActive)
        state.tick()
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activationReason, .app(bundleID: cursorID, name: "Cursor", busy: true))
        XCTAssertEqual(state.statusSubtitle, "Awake while Cursor is busy")

        usage.percents[cursorID] = 2
        for _ in 0..<9 {
            state.tick()
            XCTAssertTrue(state.isActive)
        }
        state.tick()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)
    }

    func testWhileRunningStaysOnAtZeroCPU() {
        let workspace = FakeWorkspace()
        let usage = FakeUsage()
        workspace.names[textEditID] = "TextEdit"
        let state = makeState(workspace: workspace, usage: usage)

        state.addWatchedApp(bundleID: textEditID)
        workspace.launch(textEditID)
        usage.percents[textEditID] = 0
        state.tick()
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activationReason, .app(bundleID: textEditID, name: "TextEdit"))
        XCTAssertEqual(state.statusSubtitle, "Awake while TextEdit runs")
    }

    func testManualOffWhileBusyLatchesUntilBusyFiresAgain() {
        let cursorID = "com.todesktop.230313mzl4w5jfd"
        let workspace = FakeWorkspace()
        let usage = FakeUsage()
        workspace.names[cursorID] = "Cursor"
        let state = makeState(workspace: workspace, usage: usage)

        state.addWatchedApp(bundleID: cursorID, mode: .whileBusy)
        workspace.launch(cursorID)
        usage.percents[cursorID] = 40
        state.tick()
        state.tick()
        XCTAssertTrue(state.isActive)

        state.isActive = false
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.activationReason)
        state.tick()
        XCTAssertFalse(state.isActive)

        usage.percents[cursorID] = 2
        for _ in 0..<10 {
            state.tick()
        }
        XCTAssertFalse(state.isActive)

        usage.percents[cursorID] = 40
        state.tick()
        XCTAssertFalse(state.isActive)
        state.tick()
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.activationReason, .app(bundleID: cursorID, name: "Cursor", busy: true))
        XCTAssertEqual(state.statusSubtitle, "Awake while Cursor is busy")
    }

    func testMigratesWatchedBundleIDsToWhileRunning() {
        let suiteName = "SleepMasterTests.Automation.Migrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set([textEditID], forKey: AppState.watchedAppsDefaultsKey)

        let state = AppState(
            preventer: SleepPreventer(
                controller: FakeSleepController(),
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: FakePowerMonitor(),
                defaults: defaults
            ),
            powerMonitor: FakePowerMonitor(),
            workspace: FakeWorkspace(),
            usage: FakeUsage(),
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1) },
            startsClock: false
        )

        XCTAssertEqual(state.watchedApps, [WatchedApp(bundleID: textEditID, mode: .whileRunning)])
        XCTAssertEqual(state.busyCPUThresholdPercent, AppState.defaultBusyCPUPercent)
    }

    private func makeState(
        controller: SleepController? = nil,
        power: FakePowerMonitor? = nil,
        workspace: FakeWorkspace? = nil,
        usage: ProcessUsageSampling? = nil,
        clock: TestClock? = nil,
        calendar: Calendar = .current
    ) -> AppState {
        let controller = controller ?? FakeSleepController()
        let power = power ?? FakePowerMonitor()
        let workspace = workspace ?? FakeWorkspace()
        let suiteName = "SleepMasterTests.Automation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let now: () -> Date = {
            clock?.date ?? Date(timeIntervalSince1970: 1)
        }
        return AppState(
            preventer: SleepPreventer(
                controller: controller,
                lidClosed: NoOpLidClosedBackend(),
                powerMonitor: power,
                defaults: defaults
            ),
            powerMonitor: power,
            workspace: workspace,
            usage: usage ?? FakeUsage(),
            defaults: defaults,
            now: now,
            calendar: calendar,
            startsClock: false
        )
    }
}

final class ScheduleWindowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testEmptyDaysOrEqualTimesAreInactive() {
        let now = date(hour: 12, minute: 0)
        XCTAssertFalse(ScheduleWindow.isActive(now: now, days: [], startMinutes: 8 * 60, endMinutes: 17 * 60, calendar: calendar))
        XCTAssertFalse(ScheduleWindow.isActive(now: now, days: [4], startMinutes: 12 * 60, endMinutes: 12 * 60, calendar: calendar))
    }

    func testSameDayWindowUsesHalfOpenRange() {
        let wednesday = date(hour: 12, minute: 0)
        XCTAssertTrue(ScheduleWindow.isActive(now: wednesday, days: [4], startMinutes: 12 * 60, endMinutes: 13 * 60, calendar: calendar))
        XCTAssertFalse(ScheduleWindow.isActive(now: date(hour: 13, minute: 0), days: [4], startMinutes: 12 * 60, endMinutes: 13 * 60, calendar: calendar))
        XCTAssertFalse(ScheduleWindow.isActive(now: wednesday, days: [3], startMinutes: 12 * 60, endMinutes: 13 * 60, calendar: calendar))
    }

    func testOvernightWindowUsesYesterdayStartDay() {
        XCTAssertTrue(ScheduleWindow.isActive(now: date(hour: 23, minute: 0), days: [4], startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar))
        XCTAssertTrue(ScheduleWindow.isActive(now: date(day: 15, hour: 5, minute: 0), days: [4], startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar))
        XCTAssertFalse(ScheduleWindow.isActive(now: date(day: 15, hour: 7, minute: 0), days: [4], startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar))
        XCTAssertFalse(ScheduleWindow.isActive(now: date(day: 13, hour: 23, minute: 0), days: [4], startMinutes: 22 * 60, endMinutes: 6 * 60, calendar: calendar))
    }

    private func date(day: Int = 14, hour: Int, minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts)!
    }
}
