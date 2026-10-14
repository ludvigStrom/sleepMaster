import Combine
import Foundation

@MainActor
final class SleepPreventer: ObservableObject {
    @Published private(set) var isSleepDisabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published var lidClosedEnabled: Bool
    @Published private(set) var helperNeedsApproval = false

    private let controller: SleepController
    private let lidClosed: LidClosedBackend
    let powerMonitor: PowerMonitoring
    private let lidClosedBatteryCutoff: Int
    private let defaults: UserDefaults
    private var lidClosedHeld = false

    static let lidClosedDefaultsKey = "lidClosedEnabled"

    var statusText: String {
        isSleepDisabled ? "Sleep disabled" : "Sleep allowed"
    }

    convenience init() {
        self.init(
            controller: AssertionSleepController(),
            lidClosed: CompositeLidClosedBackend(),
            powerMonitor: PowerMonitor()
        )
    }

    convenience init(controller: SleepController) {
        self.init(
            controller: controller,
            lidClosed: NoOpLidClosedBackend(),
            powerMonitor: nil,
            lidClosedBatteryCutoff: LidClosedSafety.defaultCutoffPercent,
            defaults: .standard
        )
    }

    init(
        controller: SleepController,
        lidClosed: LidClosedBackend,
        powerMonitor: PowerMonitoring? = nil,
        lidClosedBatteryCutoff: Int = LidClosedSafety.defaultCutoffPercent,
        defaults: UserDefaults = .standard
    ) {
        self.controller = controller
        self.lidClosed = lidClosed
        self.powerMonitor = powerMonitor ?? IdlePowerMonitor()
        self.lidClosedBatteryCutoff = lidClosedBatteryCutoff
        self.defaults = defaults
        if defaults.object(forKey: Self.lidClosedDefaultsKey) == nil {
            lidClosedEnabled = true
        } else {
            lidClosedEnabled = defaults.bool(forKey: Self.lidClosedDefaultsKey)
        }
        refresh()
        refreshHelperStatus()
        self.powerMonitor.addChangeHandler { [weak self] in
            self?.applyBatteryCutoff()
        }
        self.powerMonitor.start()
    }

    func refresh() {
        isSleepDisabled = controller.isActive
        refreshHelperStatus()
    }

    func refreshHelperStatus() {
        helperNeedsApproval = lidClosed.needsApproval
    }

    func toggle() {
        setSleepDisabled(!isSleepDisabled)
    }

    func setSleepDisabled(_ disabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            if disabled {
                try controller.start()
                if lidClosedEnabled {
                    do {
                        try lidClosed.setSleepDisabled(true)
                        lidClosedHeld = true
                    } catch {
                        try? controller.stop()
                        throw error
                    }
                }
            } else {
                try releaseLidClosed()
                try controller.stop()
            }
            refresh()
        } catch {
            refresh()
            if SleepControlError.isUserCanceled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func setAllowDisplaySleep(_ allow: Bool) {
        errorMessage = nil
        do {
            try controller.setAllowDisplaySleep(allow)
        } catch {
            if !SleepControlError.isUserCanceled(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func setLidClosedEnabled(_ enabled: Bool) {
        let previous = lidClosedEnabled
        lidClosedEnabled = enabled
        defaults.set(enabled, forKey: Self.lidClosedDefaultsKey)
        errorMessage = nil

        guard isSleepDisabled else { return }

        do {
            if enabled {
                try lidClosed.setSleepDisabled(true)
                lidClosedHeld = true
            } else {
                try releaseLidClosed()
            }
        } catch {
            lidClosedEnabled = previous
            defaults.set(previous, forKey: Self.lidClosedDefaultsKey)
            if !SleepControlError.isUserCanceled(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        setSleepDisabled(false)
    }

    func openHelperApproval() {
        if let composite = lidClosed as? CompositeLidClosedBackend {
            composite.openApproval()
        }
        refreshHelperStatus()
    }

    private func releaseLidClosed() throws {
        guard lidClosedHeld || lidClosedEnabled else { return }
        try lidClosed.setSleepDisabled(false)
        lidClosedHeld = false
    }

    private func applyBatteryCutoff() {
        guard lidClosedHeld else { return }
        guard LidClosedSafety.shouldDisableLidClosed(
            isOnAC: powerMonitor.isOnAC,
            batteryPercent: powerMonitor.batteryPercent,
            cutoff: lidClosedBatteryCutoff
        ) else { return }

        do {
            try lidClosed.setSleepDisabled(false)
            lidClosedHeld = false
            NSLog(
                "SleepMaster: lid-closed off; battery %d%% below %d%%",
                powerMonitor.batteryPercent ?? -1,
                lidClosedBatteryCutoff
            )
        } catch {
            if !SleepControlError.isUserCanceled(error) {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
private final class IdlePowerMonitor: PowerMonitoring {
    var isOnAC = true
    var batteryPercent: Int?
    private var changeHandlers: [() -> Void] = []

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    func start() {}
}
