import Foundation

@MainActor
protocol LidClosedBackend: AnyObject {
    var needsApproval: Bool { get }
    func setSleepDisabled(_ disabled: Bool) throws
}

extension LidClosedBackend {
    var needsApproval: Bool { false }
}

@MainActor
final class NoOpLidClosedBackend: LidClosedBackend {
    func setSleepDisabled(_ disabled: Bool) throws {}
}

@MainActor
final class CompositeLidClosedBackend: LidClosedBackend {
    private let helper: HelperClient
    private let fallback: LidClosedBackend

    var needsApproval: Bool {
        helper.status == .requiresApproval
    }

    convenience init() {
        self.init(helper: HelperClient(), fallback: PmsetSleepController())
    }

    init(helper: HelperClient, fallback: LidClosedBackend) {
        self.helper = helper
        self.fallback = fallback
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        if helper.isAvailable {
            do {
                try helper.setSleepDisabled(disabled)
                return
            } catch {
                NSLog("SleepMaster: helper failed, using password fallback: %@", error.localizedDescription)
            }
        }
        try fallback.setSleepDisabled(disabled)
    }

    func openApproval() {
        helper.openApproval()
    }
}

extension PmsetSleepController: LidClosedBackend {
    func setSleepDisabled(_ disabled: Bool) throws {
        if disabled {
            try start()
        } else {
            try stop()
        }
    }
}
