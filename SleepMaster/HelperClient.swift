import Foundation
import ServiceManagement

final class HelperClient {
    var status: SMAppService.Status {
        SMAppService.daemon(plistName: CodeIdentity.daemonPlistName).status
    }

    var isAvailable: Bool {
        status == .enabled
    }

    private var connection: NSXPCConnection?

    static func registerIfNeeded() {
        let service = SMAppService.daemon(plistName: CodeIdentity.daemonPlistName)
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            NSLog("SleepMaster: failed to register helper: %@", error.localizedDescription)
        }
    }

    func openApproval() {
        Self.registerIfNeeded()
        SMAppService.openSystemSettingsLoginItems()
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        let proxy = try remoteProxy()
        let box = ReplyBox()
        let semaphore = DispatchSemaphore(value: 0)
        proxy.setSleepDisabled(disabled) { success, message in
            box.success = success
            box.message = message
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 8) == .timedOut {
            throw SleepControlError.helperUnavailable
        }
        if !box.success {
            throw SleepControlError.helperFailed(box.message ?? "The helper could not change the sleep setting.")
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func remoteProxy() throws -> SleepMasterHelperXPC {
        let connection = persistentConnection()
        guard let proxy = connection.remoteObjectProxy as? SleepMasterHelperXPC else {
            throw SleepControlError.helperUnavailable
        }
        return proxy
    }

    private func persistentConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(
            machServiceName: CodeIdentity.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SleepMasterHelperXPC.self)
        connection.resume()
        self.connection = connection
        return connection
    }
}

private final class ReplyBox: @unchecked Sendable {
    var success = false
    var message: String?
}
