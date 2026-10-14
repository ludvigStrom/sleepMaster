import AppKit
import Foundation
import Observation

enum SleepMode: String, CaseIterable {
    case indefinitely
    case timer
}

enum TimerDurations {
    static let chips: [(label: String, seconds: TimeInterval)] = [
        ("15 min", 15 * 60),
        ("30 min", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60),
        ("8 hours", 8 * 60 * 60),
    ]

    static let defaultDuration: TimeInterval = 2 * 60 * 60
}

@MainActor
@Observable
final class AppState {
    static let modeDefaultsKey = "sleepMode"
    static let durationDefaultsKey = "selectedDuration"
    static let plugOnlyDefaultsKey = "onlyWhilePluggedIn"
    static let batteryFloorDefaultsKey = "batteryFloorPercent"
    static let displaySleepDefaultsKey = "allowDisplaySleep"
    static let showTimeDefaultsKey = "showTimeInMenuBar"
    static let rememberLastDefaultsKey = "rememberLastChoice"
    static let defaultModeDefaultsKey = "defaultMode"
    static let defaultDurationDefaultsKey = "defaultDuration"
    static let warningLeadDefaultsKey = "timerWarningLead"
    static let notifyPauseDefaultsKey = "notifyOnBatteryPause"
    static let defaultWarningLead: TimeInterval = 5 * 60
    static let defaultPauseNotifyDelay: TimeInterval = 2

    var isActive = false {
        didSet {
            guard oldValue != isActive, !isSyncing else { return }
            if isActive {
                if mode == .timer, endDate == nil {
                    endDate = now().addingTimeInterval(selectedDuration)
                }
            } else {
                endDate = nil
            }
            applyHold()
            syncTimerNotifications()
            syncPauseNotification()
        }
    }

    var lidClosedEnabled = true {
        didSet {
            guard oldValue != lidClosedEnabled, !isSyncing else { return }
            preventer.setLidClosedEnabled(lidClosedEnabled)
            syncFromPreventer()
        }
    }

    var onlyWhilePluggedIn: Bool {
        didSet {
            guard oldValue != onlyWhilePluggedIn, !isSyncing else { return }
            persistPreferences()
            applyHold()
        }
    }

    var batteryFloorPercent: Int {
        didSet {
            guard oldValue != batteryFloorPercent, !isSyncing else { return }
            persistPreferences()
            applyHold()
        }
    }

    var allowDisplaySleep: Bool {
        didSet {
            guard oldValue != allowDisplaySleep, !isSyncing else { return }
            persistPreferences()
            preventer.setAllowDisplaySleep(allowDisplaySleep)
            syncFromPreventer()
        }
    }

    var mode: SleepMode {
        didSet {
            guard oldValue != mode, !isSyncing else { return }
            persistPreferences()
            if isActive {
                switch mode {
                case .indefinitely:
                    endDate = nil
                case .timer:
                    endDate = now().addingTimeInterval(selectedDuration)
                }
            }
            syncTimerNotifications()
        }
    }

    var selectedDuration: TimeInterval {
        didSet {
            guard oldValue != selectedDuration, !isSyncing else { return }
            persistPreferences()
        }
    }

    var showTimeInMenuBar: Bool {
        didSet {
            guard oldValue != showTimeInMenuBar, !isSyncing else { return }
            persistPreferences()
        }
    }

    var rememberLastChoice: Bool {
        didSet {
            guard oldValue != rememberLastChoice, !isSyncing else { return }
            persistPreferences()
        }
    }

    var defaultMode: SleepMode {
        didSet {
            guard oldValue != defaultMode, !isSyncing else { return }
            persistPreferences()
        }
    }

    var defaultDuration: TimeInterval {
        didSet {
            guard oldValue != defaultDuration, !isSyncing else { return }
            persistPreferences()
        }
    }

    var timerWarningLead: TimeInterval {
        didSet {
            guard oldValue != timerWarningLead, !isSyncing else { return }
            persistPreferences()
            syncTimerNotifications()
        }
    }

    var notifyOnBatteryPause: Bool {
        didSet {
            guard oldValue != notifyOnBatteryPause, !isSyncing else { return }
            persistPreferences()
        }
    }

    private(set) var endDate: Date?
    private(set) var clockNow: Date
    private(set) var isOnAC: Bool
    private(set) var batteryPercent: Int?
    private(set) var helperNeedsApproval = false
    private(set) var errorMessage: String?
    private(set) var isBusy = false

    var now: () -> Date

    var isPaused: Bool {
        isActive && wouldPause
    }

    var statusTitle: String {
        if !isActive {
            return "Sleep allowed"
        }
        if isPaused {
            return "Paused on battery"
        }
        if mode == .timer, let remaining {
            return "Awake · \(Self.formatHMS(remaining))"
        }
        return "Staying awake"
    }

    var statusSubtitle: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        if !isActive {
            return "Your Mac follows its normal energy settings."
        }
        if isPaused {
            if isFloorOnlyPause {
                return "Allows sleep below \(batteryFloorPercent)%."
            }
            return "Resumes when the power adapter is connected."
        }
        if mode == .timer, let endDate {
            return "Allows sleep at \(Self.formatClock(endDate))"
        }
        return "Until you turn it off"
    }

    var plugInSubtitle: String {
        if isOnAC {
            return "Power adapter connected"
        }
        if let batteryPercent {
            return "On battery now — sleep is allowed · \(batteryPercent)%"
        }
        return "On battery now — sleep is allowed"
    }

    var countdownMenuLabel: String? {
        guard isActive, !isPaused, mode == .timer, let remaining else { return nil }
        return Self.formatHM(remaining)
    }

    var menuBarLabel: String? {
        if isPaused {
            return "Paused"
        }
        guard showTimeInMenuBar else { return nil }
        return countdownMenuLabel
    }

    var showExtendButtons: Bool {
        isActive && mode == .timer && endDate != nil
    }

    var remaining: TimeInterval? {
        guard isActive, mode == .timer, let endDate else { return nil }
        return max(0, endDate.timeIntervalSince(clockNow))
    }

    private let preventer: SleepPreventer
    private let powerMonitor: PowerMonitoring
    private let notifications: NotificationPosting
    private let defaults: UserDefaults
    private let pauseNotifyDelay: TimeInterval
    private let runAfter: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var isSyncing = false
    private var wasPaused = false
    private var cancelPauseNotify: (() -> Void)?
    private let clock = ClockRuntime()

    convenience init() {
        let power = PowerMonitor()
        self.init(
            preventer: SleepPreventer(
                controller: AssertionSleepController(),
                lidClosed: CompositeLidClosedBackend(),
                powerMonitor: power
            ),
            powerMonitor: power,
            notifications: UserNotificationClient()
        )
    }

    convenience init(controller: SleepController) {
        self.init(preventer: SleepPreventer(controller: controller), startsClock: false)
    }

    init(
        preventer: SleepPreventer,
        powerMonitor: PowerMonitoring? = nil,
        notifications: NotificationPosting? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        startsClock: Bool = true,
        pauseNotifyDelay: TimeInterval = AppState.defaultPauseNotifyDelay,
        runAfter: ((TimeInterval, @escaping () -> Void) -> () -> Void)? = nil
    ) {
        self.preventer = preventer
        self.powerMonitor = powerMonitor ?? preventer.powerMonitor
        self.notifications = notifications ?? IdleNotificationClient()
        self.defaults = defaults
        self.pauseNotifyDelay = pauseNotifyDelay
        self.runAfter = runAfter ?? { delay, work in
            let item = DispatchWorkItem(block: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
        self.now = now
        self.clockNow = now()
        self.isOnAC = self.powerMonitor.isOnAC
        self.batteryPercent = self.powerMonitor.batteryPercent
        let remember = defaults.object(forKey: Self.rememberLastDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.rememberLastDefaultsKey)
        let storedDefaultMode = defaults.string(forKey: Self.defaultModeDefaultsKey)
            .flatMap(SleepMode.init(rawValue:)) ?? .indefinitely
        let storedDefaultDuration = defaults.object(forKey: Self.defaultDurationDefaultsKey) != nil
            ? defaults.double(forKey: Self.defaultDurationDefaultsKey)
            : TimerDurations.defaultDuration
        showTimeInMenuBar = defaults.object(forKey: Self.showTimeDefaultsKey) == nil
            ? true
            : defaults.bool(forKey: Self.showTimeDefaultsKey)
        rememberLastChoice = remember
        defaultMode = storedDefaultMode
        defaultDuration = storedDefaultDuration
        if remember, let raw = defaults.string(forKey: Self.modeDefaultsKey), let stored = SleepMode(rawValue: raw) {
            mode = stored
        } else if remember {
            mode = .indefinitely
        } else {
            mode = storedDefaultMode
        }
        if remember, defaults.object(forKey: Self.durationDefaultsKey) != nil {
            selectedDuration = defaults.double(forKey: Self.durationDefaultsKey)
        } else if remember {
            selectedDuration = TimerDurations.defaultDuration
        } else {
            selectedDuration = storedDefaultDuration
        }
        if defaults.object(forKey: Self.plugOnlyDefaultsKey) == nil {
            onlyWhilePluggedIn = true
        } else {
            onlyWhilePluggedIn = defaults.bool(forKey: Self.plugOnlyDefaultsKey)
        }
        if defaults.object(forKey: Self.batteryFloorDefaultsKey) == nil {
            batteryFloorPercent = BatteryFloor.defaultPercent
        } else {
            batteryFloorPercent = defaults.integer(forKey: Self.batteryFloorDefaultsKey)
        }
        if defaults.object(forKey: Self.displaySleepDefaultsKey) == nil {
            allowDisplaySleep = false
        } else {
            allowDisplaySleep = defaults.bool(forKey: Self.displaySleepDefaultsKey)
        }
        if defaults.object(forKey: Self.warningLeadDefaultsKey) == nil {
            timerWarningLead = Self.defaultWarningLead
        } else {
            timerWarningLead = defaults.double(forKey: Self.warningLeadDefaultsKey)
        }
        if defaults.object(forKey: Self.notifyPauseDefaultsKey) == nil {
            notifyOnBatteryPause = true
        } else {
            notifyOnBatteryPause = defaults.bool(forKey: Self.notifyPauseDefaultsKey)
        }
        syncFromPreventer()
        endDate = nil
        isActive = false
        preventer.setAllowDisplaySleep(allowDisplaySleep)
        self.powerMonitor.addChangeHandler { [weak self] in
            self?.handlePowerChange()
        }
        if startsClock {
            startClock()
        }
    }

    func toggle() {
        isActive.toggle()
    }

    func refresh() {
        syncPowerSnapshot()
        preventer.refresh()
        syncFromPreventer()
        tick()
    }

    func stop() {
        isActive = false
    }

    func openHelperApproval() {
        preventer.openHelperApproval()
        syncFromPreventer()
    }

    func selectDuration(_ seconds: TimeInterval) {
        selectedDuration = seconds
        mode = .timer
        endDate = now().addingTimeInterval(seconds)
        clockNow = now()
        if !isActive {
            isActive = true
        } else {
            syncTimerNotifications()
        }
    }

    func extend(by seconds: TimeInterval) {
        guard isActive, mode == .timer, let endDate else { return }
        self.endDate = endDate.addingTimeInterval(seconds)
        syncTimerNotifications()
    }

    func setUntil(hour: Int, minute: Int, calendar: Calendar = .current) {
        let current = now()
        var components = calendar.dateComponents([.year, .month, .day], from: current)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var date = calendar.date(from: components) else { return }
        if date <= current {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        mode = .timer
        endDate = date
        clockNow = current
        if !isActive {
            isActive = true
        } else {
            syncTimerNotifications()
        }
    }

    func handleNotificationAction(_ identifier: String) {
        switch identifier {
        case NotificationAction.extend30:
            extend(by: 30 * 60)
        case NotificationAction.keepAwake:
            mode = .indefinitely
        case NotificationAction.letSleep:
            isActive = false
        default:
            break
        }
    }

    func tick() {
        clockNow = now()
        guard isActive, let endDate, clockNow >= endDate else { return }
        isActive = false
    }

    static func formatHMS(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    static func formatHM(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    static func formatClock(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private var wouldPause: Bool {
        if onlyWhilePluggedIn && !isOnAC {
            return true
        }
        return BatteryFloor.shouldAllowSleep(
            isOnAC: isOnAC,
            batteryPercent: batteryPercent,
            floor: batteryFloorPercent
        )
    }

    private var isFloorOnlyPause: Bool {
        BatteryFloor.shouldAllowSleep(
            isOnAC: isOnAC,
            batteryPercent: batteryPercent,
            floor: batteryFloorPercent
        ) && !(onlyWhilePluggedIn && !isOnAC)
    }

    private func handlePowerChange() {
        syncPowerSnapshot()
        applyHold()
        syncPauseNotification()
    }

    private func syncTimerNotifications() {
        guard isActive, mode == .timer, let endDate else {
            notifications.cancelTimerWarning()
            return
        }
        notifications.requestPermissionIfNeeded()
        let fire = endDate.addingTimeInterval(-timerWarningLead)
        if fire > now() {
            notifications.scheduleTimerWarning(at: fire)
        } else {
            notifications.cancelTimerWarning()
        }
    }

    private func syncPauseNotification() {
        let paused = isPaused
        if paused && !wasPaused {
            wasPaused = true
            guard notifyOnBatteryPause else { return }
            cancelPauseNotify?()
            cancelPauseNotify = runAfter(pauseNotifyDelay) { [weak self] in
                guard let self, self.isPaused, self.notifyOnBatteryPause else { return }
                self.notifications.notifyPausedOnBattery()
            }
        } else if !paused && wasPaused {
            wasPaused = false
            cancelPauseNotify?()
            cancelPauseNotify = nil
        }
    }

    private func syncPowerSnapshot() {
        isOnAC = powerMonitor.isOnAC
        batteryPercent = powerMonitor.batteryPercent
    }

    private func applyHold() {
        syncPowerSnapshot()
        let wantHold = isActive && !wouldPause
        if wantHold != preventer.isSleepDisabled {
            preventer.setSleepDisabled(wantHold)
        }
        syncFromPreventer()
        if isActive && wantHold && !preventer.isSleepDisabled {
            isSyncing = true
            isActive = false
            endDate = nil
            isSyncing = false
        }
    }

    private func persistPreferences() {
        if rememberLastChoice {
            defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
            defaults.set(selectedDuration, forKey: Self.durationDefaultsKey)
        }
        defaults.set(onlyWhilePluggedIn, forKey: Self.plugOnlyDefaultsKey)
        defaults.set(batteryFloorPercent, forKey: Self.batteryFloorDefaultsKey)
        defaults.set(allowDisplaySleep, forKey: Self.displaySleepDefaultsKey)
        defaults.set(showTimeInMenuBar, forKey: Self.showTimeDefaultsKey)
        defaults.set(rememberLastChoice, forKey: Self.rememberLastDefaultsKey)
        defaults.set(defaultMode.rawValue, forKey: Self.defaultModeDefaultsKey)
        defaults.set(defaultDuration, forKey: Self.defaultDurationDefaultsKey)
        defaults.set(timerWarningLead, forKey: Self.warningLeadDefaultsKey)
        defaults.set(notifyOnBatteryPause, forKey: Self.notifyPauseDefaultsKey)
    }

    private func startClock() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock.timer = timer

        clock.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func syncFromPreventer() {
        isSyncing = true
        lidClosedEnabled = preventer.lidClosedEnabled
        helperNeedsApproval = preventer.helperNeedsApproval
        errorMessage = preventer.errorMessage
        isBusy = preventer.isBusy
        isSyncing = false
    }
}

private final class ClockRuntime: @unchecked Sendable {
    var timer: Timer?
    var wakeObserver: NSObjectProtocol?

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
