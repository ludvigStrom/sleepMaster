import Foundation
import IOKit

@MainActor
protocol SleepController: AnyObject {
    var isActive: Bool { get }
    func start() throws
    func stop() throws
}

enum SleepControlError: LocalizedError {
    case couldNotCreateScript
    case appleScript(code: Int, message: String?)
    case assertionFailed(IOReturn)
    case helperUnavailable
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateScript:
            return "Could not create the administrator script."
        case .appleScript(_, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Could not change the sleep setting."
        case .assertionFailed:
            return "Could not change the sleep assertion."
        case .helperUnavailable:
            return "The Sleepmaster helper is not available."
        case .helperFailed(let message):
            return message
        }
    }

    static func isUserCanceled(_ error: Error) -> Bool {
        guard let sleepError = error as? SleepControlError,
              case .appleScript(let code, _) = sleepError
        else {
            return false
        }
        return code == -128
    }

    static func userCanceled() -> SleepControlError {
        .appleScript(code: -128, message: nil)
    }

    static func appleScript(_ info: NSDictionary) -> SleepControlError {
        let code = info[NSAppleScript.errorNumber] as? Int ?? 0
        let message = info[NSAppleScript.errorMessage] as? String
        return .appleScript(code: code, message: message)
    }
}
