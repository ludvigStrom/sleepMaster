import Foundation

@objc protocol SleepMasterHelperXPC {
    func setSleepDisabled(_ disabled: Bool, withReply reply: @escaping (Bool, String?) -> Void)
}
