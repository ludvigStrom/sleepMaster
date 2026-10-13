import Foundation
import ServiceManagement

enum LoginItem {
    static func registerIfNeeded() {
        let bundlePath = Bundle.main.bundleURL.path
        guard bundlePath.hasPrefix("/Applications/") else {
            NSLog("SleepMaster: skip login item registration (not in /Applications)")
            return
        }

        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }

        do {
            try service.register()
        } catch {
            NSLog("SleepMaster: failed to register login item: %@", error.localizedDescription)
        }
    }
}
