import Foundation
import ServiceManagement

enum LoginItemError: LocalizedError {
    case notInApplications

    var errorDescription: String? {
        "Move Sleepmaster to /Applications to launch at login."
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            let bundlePath = Bundle.main.bundleURL.path
            guard bundlePath.hasPrefix("/Applications/") else {
                throw LoginItemError.notInApplications
            }
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
