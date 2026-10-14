import Foundation
import os.log

let helperLog = Logger(subsystem: CodeIdentity.helperBundleID, category: "daemon")

final class HelperService: NSObject, SleepMasterHelperXPC {
    func setSleepDisabled(_ disabled: Bool, withReply reply: @escaping (Bool, String?) -> Void) {
        do {
            try PmsetDirect.setSleepDisabled(disabled)
            helperLog.info("set SleepDisabled \(disabled, privacy: .public)")
            reply(true, nil)
        } catch {
            helperLog.error("set SleepDisabled failed: \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    func clientDidDrop() {
        do {
            try PmsetDirect.setSleepDisabled(false)
            helperLog.info("XPC dropped; SleepDisabled reset to 0")
        } catch {
            helperLog.error("XPC-drop reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class HelperListener: NSObject, NSXPCListenerDelegate {
    private let service: HelperService
    private let expectedTeamID: String

    init(service: HelperService) {
        self.service = service
        self.expectedTeamID = CodeIdentity.selfTeamID() ?? ""
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard CodeIdentity.isAuthorizedSleepmaster(pid: newConnection.processIdentifier, teamID: expectedTeamID) else {
            helperLog.error("rejected XPC client pid \(newConnection.processIdentifier, privacy: .public)")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: SleepMasterHelperXPC.self)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [weak service] in
            service?.clientDidDrop()
        }
        newConnection.interruptionHandler = { [weak service] in
            service?.clientDidDrop()
        }
        newConnection.resume()
        return true
    }
}
