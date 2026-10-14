import Foundation

do {
    try PmsetDirect.setSleepDisabled(false)
    helperLog.info("boot reset: SleepDisabled 0")
} catch {
    helperLog.error("boot reset failed: \(error.localizedDescription, privacy: .public)")
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: CodeIdentity.machServiceName)
let delegate = HelperListener(service: service)
listener.delegate = delegate
listener.resume()

let safety = PowerSafety {
    do {
        try PmsetDirect.setSleepDisabled(false)
        helperLog.info("battery cutoff: SleepDisabled 0")
    } catch {
        helperLog.error("battery cutoff failed: \(error.localizedDescription, privacy: .public)")
    }
}
safety.start()

RunLoop.main.run()
