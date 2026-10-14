import Foundation

enum HelperError: LocalizedError {
    case pmsetFailed(String)

    var errorDescription: String? {
        switch self {
        case .pmsetFailed(let message):
            return message
        }
    }
}

enum PmsetDirect {
    static func setSleepDisabled(_ disabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw HelperError.pmsetFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw HelperError.pmsetFailed(message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "pmset failed.")
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
