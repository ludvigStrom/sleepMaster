import Foundation

enum PmsetStatus {
    static func parseSleepDisabled(_ output: String) -> Bool {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0] == "SleepDisabled" else { continue }
            return parts[1] == "1"
        }
        return false
    }
}

@MainActor
final class PmsetSleepController: SleepController {
    var isActive: Bool {
        Self.readSleepDisabled()
    }

    func start() throws {
        try Self.runPmset(disabled: true)
    }

    func stop() throws {
        try Self.runPmset(disabled: false)
    }

    static func readSleepDisabled() -> Bool {
        guard let output = runPmsetQuery() else { return false }
        return PmsetStatus.parseSleepDisabled(output)
    }

    private static func runPmsetQuery() -> String? {
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
            return nil
        }

        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
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
}
