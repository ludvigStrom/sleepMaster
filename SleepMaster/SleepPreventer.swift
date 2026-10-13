import Foundation

@MainActor
final class SleepPreventer: ObservableObject {
    @Published private(set) var isSleepDisabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false

    var statusText: String {
        isSleepDisabled ? "Sleep disabled" : "Sleep allowed"
    }

    init() {
        refresh()
    }

    func refresh() {
        isSleepDisabled = Self.readSleepDisabled()
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
            try Self.runPmset(disabled: disabled)
            refresh()
        } catch {
            refresh()
            if Self.isUserCanceled(error) {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private static func readSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0] == "SleepDisabled" else { continue }
            return parts[1] == "1"
        }
        return false
    }

    private static func runPmset(disabled: Bool) throws {
        let value = disabled ? "1" : "0"
        let source = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else {
            throw SleepControlError.couldNotCreateScript
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw SleepControlError.appleScript(errorInfo)
        }
    }

    private static func isUserCanceled(_ error: Error) -> Bool {
        guard let sleepError = error as? SleepControlError,
              case .appleScript(let info) = sleepError,
              let number = info[NSAppleScript.errorNumber] as? Int
        else {
            return false
        }
        return number == -128
    }
}

private enum SleepControlError: LocalizedError {
    case couldNotCreateScript
    case appleScript(NSDictionary)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateScript:
            return "Could not create the administrator script."
        case .appleScript(let info):
            if let message = info[NSAppleScript.errorMessage] as? String, !message.isEmpty {
                return message
            }
            return "Could not change the sleep setting."
        }
    }
}
