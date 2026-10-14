import AppKit
import Foundation
import Observation

enum SleepMode: String, CaseIterable {
    case indefinitely
    case timer
}

enum ActivationReason: Equatable {
    case manual
    case app(bundleID: String, name: String, busy: Bool = false)
    case power
    case schedule

    var kind: AutoReasonKind {
        switch self {
        case .manual: return .manual
        case .app: return .app
        case .power: return .power
        case .schedule: return .schedule
        }
    }
}

enum AutoReasonKind: String, Hashable {
    case manual
    case app
    case power
    case schedule
}

enum WatchedAppMode: String, Codable, CaseIterable {
    case whileRunning
    case whileBusy
}

struct WatchedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var mode: WatchedAppMode

    var id: String { bundleID }
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
    static let autoOnPlugDefaultsKey = "autoOnWhenPluggedIn"
    static let watchedAppsDefaultsKey = "watchedBundleIDs"
    static let watchedAppsJSONDefaultsKey = "watchedApps"
    static let busyCPUDefaultsKey = "busyCPUThresholdPercent"
    static let defaultBusyCPUPercent = 25
    static let scheduleEnabledDefaultsKey = "scheduleEnabled"
    static let scheduleDaysDefaultsKey = "scheduleDays"
    static let scheduleStartDefaultsKey = "scheduleStartMinutes"
    static let scheduleEndDefaultsKey = "scheduleEndMinutes"
    static let onboardingDefaultsKey = "didCompleteOnboarding"
    static let appearanceDefaultsKey = "appearancePreference"
    static let defaultWarningLead: TimeInterval = 5 * 60
    static let defaultPauseNotifyDelay: TimeInterval = 2

    var isActive = false {
        didSet {
            guard oldValue != isActive, !isSyncing else { return }
            if !isEvaluatingAutomation {
                if isActive {
                    activationReason = .manual
                } else {
                    latchCurrentAutoReasons()
                    activationReason = nil
                }
            }
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

    var autoOnWhenPluggedIn: Bool {
        didSet {
            guard oldValue != autoOnWhenPluggedIn, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var watchedApps: [WatchedApp] {
        didSet {
            guard oldValue != watchedApps, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var watchedBundleIDs: [String] {
        watchedApps.map(\.bundleID)
    }

    var busyCPUThresholdPercent: Int {
        didSet {
            guard oldValue != busyCPUThresholdPercent, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var scheduleEnabled: Bool {
        didSet {
            guard oldValue != scheduleEnabled, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var scheduleDays: Set<Int> {
        didSet {
            guard oldValue != scheduleDays, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var scheduleStartMinutes: Int {
        didSet {
            guard oldValue != scheduleStartMinutes, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var scheduleEndMinutes: Int {
        didSet {
            guard oldValue != scheduleEndMinutes, !isSyncing else { return }
            persistPreferences()
            applyAutomation()
        }
    }

    var didCompleteOnboarding: Bool {
        didSet {
            guard oldValue != didCompleteOnboarding, !isSyncing else { return }
            persistPreferences()
        }
    }

    var appearancePreference: AppearancePreference {
        didSet {
            guard oldValue != appearancePreference, !isSyncing else { return }
            persistPreferences()
            applyAppearance()
        }
    }

    private(set) var endDate: Date?
    private(set) var clockNow: Date
    private(set) var isOnAC: Bool
    private(set) var batteryPercent: Int?
    private(set) var helperNeedsApproval = false
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    private(set) var activationReason: ActivationReason?

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
        if let activationReason {
            switch activationReason {
            case .manual:
                break
            case .app(_, let name, let busy):
                return busy ? "Awake while \(name) is busy" : "Awake while \(name) runs"
            case .power:
                return "Awake while plugged in"
            case .schedule:
                return "Awake on schedule"
            }
        }
        if mode == .timer, let endDate {
            return withDisplaySleepSuffix("Allows sleep at \(Self.formatClock(endDate))")
        }
        return withDisplaySleepSuffix("Until you turn it off")
    }

    var powerAccessibilityValue: String {
        if isPaused { return "Paused" }
        return isActive ? "On" : "Off"
    }

    var scheduleSummary: String {
        let window = "\(Self.formatMinutes(scheduleStartMinutes))–\(Self.formatMinutes(scheduleEndMinutes))"
        if scheduleDays == Set(2...6) {
            return "Weekdays \(window)"
        }
        if scheduleDays == Set(1...7) {
            return "Every day \(window)"
        }
        if scheduleDays.isEmpty {
            return "No days selected · \(window)"
        }
        let symbols = calendar.shortWeekdaySymbols
        let names = (1...7).compactMap { day -> String? in
            guard scheduleDays.contains(day), symbols.indices.contains(day - 1) else { return nil }
            return symbols[day - 1]
        }
        return "\(names.joined(separator: ", ")) \(window)"
    }

    var needsOnboarding: Bool {
        !didCompleteOnboarding
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
    private let workspace: WorkspaceWatching
    private let usage: ProcessUsageSampling
    private let defaults: UserDefaults
    private var busyTrackers: [String: BusyHysteresis] = [:]
    var calendar: Calendar
    private let pauseNotifyDelay: TimeInterval
    private let runAfter: (TimeInterval, @escaping () -> Void) -> () -> Void
    private var isSyncing = false
    private var isEvaluatingAutomation = false
    private var latchedReasons: Set<AutoReasonKind> = []
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
            notifications: UserNotificationClient(),
            workspace: WorkspaceWatcher(),
            usage: ProcessUsageMonitor()
        )
    }

    convenience init(controller: SleepController) {
        self.init(preventer: SleepPreventer(controller: controller), startsClock: false)
    }

    init(
        preventer: SleepPreventer,
        powerMonitor: PowerMonitoring? = nil,
        notifications: NotificationPosting? = nil,
        workspace: WorkspaceWatching? = nil,
        usage: ProcessUsageSampling? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        startsClock: Bool = true,
        pauseNotifyDelay: TimeInterval = AppState.defaultPauseNotifyDelay,
        runAfter: ((TimeInterval, @escaping () -> Void) -> () -> Void)? = nil
    ) {
        self.preventer = preventer
        self.powerMonitor = powerMonitor ?? preventer.powerMonitor
        self.notifications = notifications ?? IdleNotificationClient()
        self.workspace = workspace ?? IdleWorkspace()
        self.usage = usage ?? IdleProcessUsage()
        self.defaults = defaults
        self.calendar = calendar
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
        autoOnWhenPluggedIn = defaults.bool(forKey: Self.autoOnPlugDefaultsKey)
        if let data = defaults.data(forKey: Self.watchedAppsJSONDefaultsKey),
           let decoded = try? JSONDecoder().decode([WatchedApp].self, from: data) {
            watchedApps = decoded
        } else {
            watchedApps = (defaults.stringArray(forKey: Self.watchedAppsDefaultsKey) ?? []).map {
                WatchedApp(bundleID: $0, mode: .whileRunning)
            }
        }
        if defaults.object(forKey: Self.busyCPUDefaultsKey) != nil {
            busyCPUThresholdPercent = min(80, max(5, defaults.integer(forKey: Self.busyCPUDefaultsKey)))
        } else {
            busyCPUThresholdPercent = Self.defaultBusyCPUPercent
        }
        scheduleEnabled = defaults.bool(forKey: Self.scheduleEnabledDefaultsKey)
        if let days = defaults.array(forKey: Self.scheduleDaysDefaultsKey) as? [Int] {
            scheduleDays = Set(days)
        } else {
            scheduleDays = []
        }
        if defaults.object(forKey: Self.scheduleStartDefaultsKey) != nil {
            scheduleStartMinutes = defaults.integer(forKey: Self.scheduleStartDefaultsKey)
        } else {
            scheduleStartMinutes = 9 * 60
        }
        if defaults.object(forKey: Self.scheduleEndDefaultsKey) != nil {
            scheduleEndMinutes = defaults.integer(forKey: Self.scheduleEndDefaultsKey)
        } else {
            scheduleEndMinutes = 17 * 60
        }
        didCompleteOnboarding = defaults.bool(forKey: Self.onboardingDefaultsKey)
        if let raw = defaults.string(forKey: Self.appearanceDefaultsKey),
           let stored = AppearancePreference(rawValue: raw) {
            appearancePreference = stored
        } else {
            appearancePreference = .system
        }
        applyAppearance()
        syncFromPreventer()
        endDate = nil
        isActive = false
        preventer.setAllowDisplaySleep(allowDisplaySleep)
        self.powerMonitor.addChangeHandler { [weak self] in
            self?.handlePowerChange()
        }
        self.workspace.addChangeHandler { [weak self] in
            self?.applyAutomation()
        }
        self.workspace.start()
        if startsClock {
            startClock()
        }
    }

    func addWatchedApp(bundleID: String, mode: WatchedAppMode = .whileRunning) {
        guard !bundleID.isEmpty, !watchedApps.contains(where: { $0.bundleID == bundleID }) else { return }
        watchedApps.append(WatchedApp(bundleID: bundleID, mode: mode))
    }

    func setWatchedAppMode(_ mode: WatchedAppMode, for bundleID: String) {
        guard let index = watchedApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        watchedApps[index].mode = mode
    }

    func removeWatchedApp(bundleID: String) {
        watchedApps.removeAll { $0.bundleID == bundleID }
        busyTrackers[bundleID] = nil
    }

    func displayName(forBundleID bundleID: String) -> String {
        workspace.displayName(for: bundleID)
    }

    func completeOnboarding() {
        didCompleteOnboarding = true
    }

    func isScheduleActive(now date: Date? = nil) -> Bool {
        ScheduleWindow.isActive(
            now: date ?? now(),
            days: scheduleDays,
            startMinutes: scheduleStartMinutes,
            endMinutes: scheduleEndMinutes,
            calendar: calendar
        )
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
        activationReason = .manual
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
        activationReason = .manual
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
            activationReason = .manual
        case NotificationAction.letSleep:
            isActive = false
        default:
            break
        }
    }

    func tick() {
        clockNow = now()
        refreshBusyState()
        if isActive, let endDate, clockNow >= endDate {
            isActive = false
        }
        applyAutomation()
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
        applyAutomation()
    }

    private func latchCurrentAutoReasons() {
        latchedReasons = Set(currentTrueReasons().map(\.kind))
    }

    private func currentTrueReasons() -> [ActivationReason] {
        var reasons: [ActivationReason] = []
        if let app = firstMatchingWatchedApp() {
            reasons.append(.app(bundleID: app.id, name: app.name, busy: app.busy))
        }
        if scheduleEnabled, isScheduleActive() {
            reasons.append(.schedule)
        }
        if autoOnWhenPluggedIn && isOnAC {
            reasons.append(.power)
        }
        return reasons
    }

    private func refreshBusyState() {
        usage.sample(bundleIDs: watchedBundleIDs)
        let threshold = Double(busyCPUThresholdPercent)
        for app in watchedApps where app.mode == .whileBusy {
            var tracker = busyTrackers[app.bundleID] ?? BusyHysteresis()
            _ = tracker.sample(usage.cpuPercent(for: app.bundleID), threshold: threshold)
            busyTrackers[app.bundleID] = tracker
        }
    }

    private func firstMatchingWatchedApp() -> (id: String, name: String, busy: Bool)? {
        let running = workspace.runningBundleIDs
        for app in watchedApps {
            guard running.contains(app.bundleID) else { continue }
            switch app.mode {
            case .whileRunning:
                return (app.bundleID, workspace.displayName(for: app.bundleID), false)
            case .whileBusy:
                if busyTrackers[app.bundleID]?.isBusy == true {
                    return (app.bundleID, workspace.displayName(for: app.bundleID), true)
                }
            }
        }
        return nil
    }

    private func applyAutomation() {
        let trueReasons = currentTrueReasons()
        latchedReasons = latchedReasons.intersection(Set(trueReasons.map(\.kind)))
        let effective = trueReasons.filter { !latchedReasons.contains($0.kind) }

        if isActive, activationReason == .manual {
            return
        }

        if let preferred = effective.first {
            if !isActive {
                startAutomatically(preferred)
            } else if activationReason != .manual {
                activationReason = preferred
            }
            return
        }

        if isActive, let activationReason, activationReason != .manual {
            stopAutomatically()
        }
    }

    private func startAutomatically(_ reason: ActivationReason) {
        isEvaluatingAutomation = true
        activationReason = reason
        mode = .indefinitely
        isActive = true
        isEvaluatingAutomation = false
        applyHold()
        syncTimerNotifications()
        syncPauseNotification()
    }

    private func stopAutomatically() {
        isEvaluatingAutomation = true
        activationReason = nil
        isActive = false
        isEvaluatingAutomation = false
        applyHold()
        syncTimerNotifications()
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
            notifications.scheduleTimerWarning(at: fire, minutesBeforeEnd: Int(timerWarningLead / 60))
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
        defaults.set(autoOnWhenPluggedIn, forKey: Self.autoOnPlugDefaultsKey)
        if let data = try? JSONEncoder().encode(watchedApps) {
            defaults.set(data, forKey: Self.watchedAppsJSONDefaultsKey)
        }
        defaults.set(watchedBundleIDs, forKey: Self.watchedAppsDefaultsKey)
        defaults.set(busyCPUThresholdPercent, forKey: Self.busyCPUDefaultsKey)
        defaults.set(scheduleEnabled, forKey: Self.scheduleEnabledDefaultsKey)
        defaults.set(Array(scheduleDays), forKey: Self.scheduleDaysDefaultsKey)
        defaults.set(scheduleStartMinutes, forKey: Self.scheduleStartDefaultsKey)
        defaults.set(scheduleEndMinutes, forKey: Self.scheduleEndDefaultsKey)
        defaults.set(didCompleteOnboarding, forKey: Self.onboardingDefaultsKey)
        defaults.set(appearancePreference.rawValue, forKey: Self.appearanceDefaultsKey)
    }

    private func applyAppearance() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        NSApp.appearance = appearancePreference.nsAppearance
    }

    private func withDisplaySleepSuffix(_ text: String) -> String {
        if allowDisplaySleep {
            return "\(text) · display may sleep"
        }
        return text
    }

    static func formatMinutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
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
